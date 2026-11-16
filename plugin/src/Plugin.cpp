// DreadmoorVR.dll — Phase 1 native input adapter (read-only).
// Loads in UEVR nightly 01143 (plugin SDK 2.39). Lists UEVR's OpenVR actions with handles, types and
// Frame binding origins; logs passive action state changes; proves C++ <-> Lua delivery with a
// ping/ack round trip. Never calls UpdateActionState / SetActionManifestPath, never edits bindings.
//
// Polling order (UEVR 4ee5c6b): Mods run VR -> PluginLoader -> LuaLoader. VR::on_pre_engine_tick
// calls UpdateActionState at its end (VR.cpp:1386), so this plugin's on_pre_engine_tick reads data
// refreshed in the same tick (one frame stale only on frames UEVR skips the update).
#include <Windows.h>

#include <chrono>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "openvr.h"
#include "uevr/Plugin.hpp"
#include "core.hpp"

using namespace uevr;

namespace {
using GetGenericInterfaceFn = void* (*)(const char*, vr::EVRInitError*);

struct ActionInfo {
    dvr::ActionDecl decl;
    vr::VRActionHandle_t handle{vr::k_ulInvalidActionHandle};
};

const char* hand_name(int i) { return i == 0 ? "L" : "R"; }
} // namespace

class DreadmoorVRPlugin : public Plugin {
public:
    void on_initialize() override {
        log("loaded; SDK %d.%d.%d; runtime openvr=%d openxr=%d", UEVR_PLUGIN_VERSION_MAJOR,
            UEVR_PLUGIN_VERSION_MINOR, UEVR_PLUGIN_VERSION_PATCH, (int)vr_fn()->is_openvr(),
            (int)vr_fn()->is_openxr());
        log("persistent dir: %s", API::get()->get_persistent_dir().string().c_str());
    }

    void on_pre_engine_tick(API::UGameEngine*, float) override {
        ping_lua();
        if (!m_inventoried) {
            if (!dvr::runtime_gate(vr_fn()->is_openvr(), vr_fn()->is_runtime_ready())) {
                if (!m_logged_wait) { log("waiting: OpenVR not active/ready (Phase 1 is OpenVR-only)"); m_logged_wait = true; }
                return;
            }
            inventory();
            m_inventoried = true;
        }
        if (m_input != nullptr) capture();
    }

    void on_custom_event(const char* name, const char* data) override {
        if (std::string_view{name} == "dreadmoorvr_ack" && !m_acked) {
            m_acked = true;
            log("Lua -> C++ ack received: '%s' (round trip verified after %d ping(s))", data, m_pings);
        }
    }

private:
    template <typename... Args> void log(const char* fmt, Args... args) {
        std::string f = std::string("[DreadmoorVR.dll] ") + fmt;
        API::get()->log_info(f.c_str(), args...);
    }
    static const UEVR_VRData* vr_fn() { return API::get()->param()->vr; }

    // C++ -> Lua: ping every 2 s until the Lua listener acks (Lua scripts load after plugins).
    void ping_lua() {
        if (m_acked || m_pings >= 60) return;
        auto now = std::chrono::steady_clock::now();
        if (now - m_last_ping < std::chrono::seconds(2)) return;
        m_last_ping = now;
        ++m_pings;
        API::get()->dispatch_lua_event("dreadmoorvr_ping", std::to_string(m_pings));
        if (m_pings == 60) log("no Lua ack after 60 pings; is m0_probe.lua deployed?");
    }

    void inventory() {
        auto get = reinterpret_cast<GetGenericInterfaceFn>(
            GetProcAddress(GetModuleHandleA("openvr_api.dll"), "VR_GetGenericInterface"));
        if (get == nullptr) { log("ERROR: openvr_api.dll / VR_GetGenericInterface not found"); return; }
        vr::EVRInitError e1 = vr::VRInitError_None, e2 = vr::VRInitError_None;
        m_input = static_cast<vr::IVRInput*>(get(vr::IVRInput_Version, &e1));
        m_system = static_cast<vr::IVRSystem*>(get(vr::IVRSystem_Version, &e2));
        log("IVRInput %s (err %d), IVRSystem %s (err %d)", m_input ? "ok" : "MISSING", (int)e1,
            m_system ? "ok" : "MISSING", (int)e2);
        if (m_input == nullptr) return;

        const char* hands[2] = {"/user/hand/left", "/user/hand/right"};
        for (int i = 0; i < 2; ++i) {
            auto err = m_input->GetInputSourceHandle(hands[i], &m_source[i]);
            vr::InputOriginInfo_t info{};
            auto err2 = m_input->GetOriginTrackedDeviceInfo(m_source[i], &info, sizeof(info));
            char type[64] = "?";
            if (m_system && err2 == vr::VRInputError_None) {
                m_system->GetStringTrackedDeviceProperty(info.trackedDeviceIndex, vr::Prop_ControllerType_String, type, sizeof(type));
            }
            log("hand %s: source 0x%llx (err %d) device %u (err %d) controller_type=%s", hand_name(i),
                (unsigned long long)m_source[i], (int)err, info.trackedDeviceIndex, (int)err2, type);
        }

        auto manifest_path = API::get()->get_persistent_dir() / "actions.json";
        std::ifstream f(manifest_path);
        std::stringstream ss;
        ss << f.rdbuf();
        auto decls = dvr::parse_manifest(ss.str());
        log("manifest %s: %zu actions", manifest_path.string().c_str(), decls.size());

        for (auto& d : decls) {
            ActionInfo a{d};
            auto err = m_input->GetActionHandle(d.name.c_str(), &a.handle);
            std::string bound;
            vr::InputBindingInfo_t bi[8]{};
            uint32_t n = 0;
            auto berr = m_input->GetActionBindingInfo(a.handle, bi, sizeof(vr::InputBindingInfo_t), 8, &n);
            for (uint32_t k = 0; k < n; ++k) {
                if (!bound.empty()) bound += " | ";
                bound += std::string(bi[k].rchDevicePathName) + bi[k].rchInputPathName + " (" + bi[k].rchModeName + "/" + bi[k].rchSlotName + ")";
            }
            if (bound.empty()) bound = "unbound";
            log("action %s type=%s handle=0x%llx err=%d binding_err=%d -> %s", d.name.c_str(), d.type.c_str(),
                (unsigned long long)a.handle, (int)err, (int)berr, bound.c_str());
            m_actions.push_back(a);
        }
    }

    // Read-only capture of action state on both hands. Edge-triggered and capped.
    void capture() {
        for (auto& a : m_actions) {
            if (a.handle == vr::k_ulInvalidActionHandle) continue;
            const auto short_name = a.decl.name.substr(a.decl.name.find_last_of('/') + 1);
            for (int i = 0; i < 2; ++i) {
                std::string value;
                if (a.decl.type == "boolean") {
                    vr::InputDigitalActionData_t d{};
                    auto err = m_input->GetDigitalActionData(a.handle, &d, sizeof(d), m_source[i]);
                    value = err != vr::VRInputError_None ? "err" + std::to_string((int)err) : !d.bActive ? "inactive" : d.bState ? "1" : "0";
                } else if (a.decl.type == "vector1" || a.decl.type == "vector2") {
                    vr::InputAnalogActionData_t d{};
                    auto err = m_input->GetAnalogActionData(a.handle, &d, sizeof(d), m_source[i]);
                    if (err != vr::VRInputError_None) value = "err" + std::to_string((int)err);
                    else if (!d.bActive) value = "inactive";
                    else {
                        char buf[48];
                        if (a.decl.type == "vector1") snprintf(buf, sizeof(buf), "%.1f", d.x);
                        else snprintf(buf, sizeof(buf), "%.1f,%.1f", d.x, d.y);
                        value = buf;
                    }
                } else if (a.decl.type == "skeleton") {
                    if (i != 0) continue; // skeleton actions are per hand already
                    vr::EVRSkeletalTrackingLevel lvl{};
                    auto err = m_input->GetSkeletalTrackingLevel(a.handle, &lvl);
                    value = err != vr::VRInputError_None ? "err" + std::to_string((int)err) : "tracking_level=" + std::to_string((int)lvl);
                } else {
                    continue; // poses and haptics: not captured in Phase 1
                }
                if (auto line = m_edges.change(short_name + "@" + hand_name(i), value)) {
                    log("input %s", line->c_str());
                    if (!m_first_change_sent && value != "inactive" && value.rfind("err", 0) != 0) {
                        m_first_change_sent = true;
                        API::get()->dispatch_lua_event("dreadmoorvr_input", *line);
                    }
                }
            }
        }
        if (m_edges.dropped() != m_reported_dropped && (m_edges.dropped() - m_reported_dropped) >= 50) {
            m_reported_dropped = m_edges.dropped();
            log("telemetry cap reached (%zu lines); %zu changes dropped so far", m_edges.count(), m_edges.dropped());
        }
    }

    vr::IVRInput* m_input{nullptr};
    vr::IVRSystem* m_system{nullptr};
    vr::VRInputValueHandle_t m_source[2]{};
    std::vector<ActionInfo> m_actions;
    dvr::EdgeLog m_edges{200};
    size_t m_reported_dropped{0};
    bool m_inventoried{false}, m_logged_wait{false}, m_first_change_sent{false}, m_acked{false};
    int m_pings{0};
    std::chrono::steady_clock::time_point m_last_ping{};
};

std::unique_ptr<DreadmoorVRPlugin> g_plugin{new DreadmoorVRPlugin()};
