// DreadmoorVR.dll — native Steam Frame input adapter (read-only). Phase 1 + Phase 2 telemetry.
// Loads in UEVR nightly 01143 (plugin SDK 2.39). Never calls UpdateActionState / SetActionManifestPath,
// never edits bindings, never modifies the gamepad state.
//
// Polling order (UEVR 4ee5c6b): Mods run VR -> PluginLoader -> LuaLoader. VR::on_pre_engine_tick
// calls UpdateActionState at its end (VR.cpp:1386), so on_pre_engine_tick here reads data refreshed
// in the same tick (one frame stale only on frames UEVR skips the update). on_xinput_get_state here
// runs after VR's, so it sees the gamepad the game receives.
#include <Windows.h>

#include <chrono>
#include <cmath>
#include <fstream>
#include <map>
#include <mutex>
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
    std::string short_name;
    vr::VRActionHandle_t handle{vr::k_ulInvalidActionHandle};
};

const char* hand_name(int i) { return i == 0 ? "L" : "R"; }

std::string fmt_float(float v) {
    char b[24];
    snprintf(b, sizeof(b), "%.2f", v);
    return b;
}
} // namespace

class DreadmoorVRPlugin : public Plugin {
public:
    void on_initialize() override {
        m_t0 = std::chrono::steady_clock::now();
        log("loaded; SDK %d.%d.%d; runtime openvr=%d openxr=%d", UEVR_PLUGIN_VERSION_MAJOR,
            UEVR_PLUGIN_VERSION_MINOR, UEVR_PLUGIN_VERSION_PATCH, (int)vr_fn()->is_openvr(),
            (int)vr_fn()->is_openxr());
        auto dir = API::get()->get_persistent_dir();
        log("persistent dir: %s", dir.string().c_str());

        std::ifstream f(dir / "dreadmoorvr_telemetry.txt");
        std::stringstream ss;
        ss << f.rdbuf();
        m_cfg = dvr::parse_config(ss.str());
        m_digital = dvr::EdgeLog(m_cfg.digital_cap);
        m_analog_log = dvr::EdgeLog(m_cfg.analog_cap);
        m_filter = dvr::AnalogFilter(m_cfg.analog_step, m_cfg.analog_min_ms);
        log("telemetry config (%s): analog_step=%.2f analog_min_ms=%d digital_cap=%zu analog_cap=%zu report_s=%d",
            f.is_open() ? "file" : "defaults", m_cfg.analog_step, m_cfg.analog_min_ms, m_cfg.digital_cap,
            m_cfg.analog_cap, m_cfg.report_s);
    }

    void on_pre_engine_tick(API::UGameEngine*, float) override {
        ping_lua();
        if (!m_inventoried) {
            if (!dvr::runtime_gate(vr_fn()->is_openvr(), vr_fn()->is_runtime_ready())) {
                if (!m_logged_wait) { log("waiting: OpenVR not active/ready (OpenVR-only)"); m_logged_wait = true; }
                return;
            }
            inventory();
            m_inventoried = true;
        }
        if (m_input == nullptr) return;
        std::lock_guard lock{m_mtx};
        if (!m_pending_class.empty()) {
            std::string path = m_pending_class;
            m_pending_class.clear();
            std::string result = load_class(path);
            log("M1 class load %s -> %s", path.c_str(), result.c_str());
            API::get()->dispatch_lua_event("dreadmoorvr_class_loaded", result);
        }
        capture();
        if (now_ms() - m_last_report_ms >= (int64_t)m_cfg.report_s * 1000) {
            m_last_report_ms = now_ms();
            write_report();
        }
    }

    // Observe only: the gamepad the game receives (runs after UEVR's VR mapping).
    void on_xinput_get_state(uint32_t*, uint32_t user_index, XINPUT_STATE* state) override {
        if (state == nullptr || user_index != 0 || !m_inventoried) return;
        std::lock_guard lock{m_mtx};  // XInput thread vs game thread
        const uint16_t pad = state->Gamepad.wButtons;
        if (pad == m_last_pad) return;
        m_last_pad = pad;
        char b[16];
        snprintf(b, sizeof(b), "0x%04X", pad);
        if (auto line = m_digital.change("pad", b)) log("t=%lld %s down=[%s]", (long long)now_ms(), line->c_str(), joined_down().c_str());
        m_map.observe(m_down, pad);
    }

    void on_custom_event(const char* name, const char* data) override {
        if (std::string_view{name} == "dreadmoorvr_request_class" && data != nullptr) {
            std::lock_guard lock{m_mtx};
            m_pending_class = data;
            return;
        }
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
    int64_t now_ms() const {
        return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - m_t0).count();
    }
    std::string joined_down() const {
        std::string s;
        for (auto& d : m_down) { if (!s.empty()) s += ","; s += d; }
        return s;
    }

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

    // M1: load a Blueprint class from the mod pak. UEVR's Lua cannot marshal soft references, so this
    // calls KismetSystemLibrary's MakeSoftObjectPath -> Conv_SoftObjPathToSoftObjRef ->
    // LoadAsset_Blocking with parameter blocks laid out from the engine's own reflection.
    // Returns "ok|<path>" or "fail|<reason>". Game thread only.
    std::string load_class(const std::string& path) {
        auto& api = API::get();
        auto ksl_class = api->find_uobject<API::UClass>(L"Class /Script/Engine.KismetSystemLibrary");
        if (ksl_class == nullptr) return "fail|KismetSystemLibrary class not found";
        auto ksl = ksl_class->get_class_default_object();
        if (ksl == nullptr) return "fail|KismetSystemLibrary CDO not found";

        struct Call {
            API::UFunction* fn{nullptr};
            std::vector<uint8_t> buf;
            int32_t off(const wchar_t* prop) const {
                auto p = fn->find_property(prop);
                return p ? p->get_offset() : -1;
            }
        };
        auto make_call = [&](const wchar_t* name, Call& c) -> bool {
            c.fn = ksl_class->find_function(name);
            if (c.fn == nullptr) return false;
            c.buf.assign((size_t)c.fn->get_properties_size() + 16, 0);
            return true;
        };
        Call mk, conv, load;
        if (!make_call(L"MakeSoftObjectPath", mk)) return "fail|MakeSoftObjectPath not found";
        if (!make_call(L"Conv_SoftObjPathToSoftObjRef", conv)) return "fail|Conv_SoftObjPathToSoftObjRef not found";
        if (!make_call(L"LoadAsset_Blocking", load)) return "fail|LoadAsset_Blocking not found";

        const int32_t mk_in = mk.off(L"PathString"), mk_ret = mk.off(L"ReturnValue");
        const int32_t cv_in = conv.off(L"SoftObjectPath"), cv_ret = conv.off(L"ReturnValue");
        const int32_t ld_in = load.off(L"Asset"), ld_ret = load.off(L"ReturnValue");
        log("M1 param offsets: Make(PathString=%d, Ret=%d size=%d) Conv(In=%d, Ret=%d size=%d) Load(Asset=%d, Ret=%d size=%d)",
            mk_in, mk_ret, mk.fn->get_properties_size(), cv_in, cv_ret, conv.fn->get_properties_size(),
            ld_in, ld_ret, load.fn->get_properties_size());
        if (mk_in < 0 || mk_ret < 0 || cv_in < 0 || cv_ret < 0 || ld_in < 0 || ld_ret < 0) return "fail|parameter not found by name";

        // FString { TCHAR* Data; int32 Num (incl. terminator); int32 Max; } pointing at our buffer.
        std::wstring wpath(path.begin(), path.end());
        struct FStr { const wchar_t* data; int32_t num; int32_t max; } fs{wpath.c_str(), (int32_t)wpath.size() + 1, (int32_t)wpath.size() + 1};
        memcpy(mk.buf.data() + mk_in, &fs, sizeof(fs));
        ksl->process_event(mk.fn, mk.buf.data());

        // FSoftObjectPath: copy Make's return into Conv's input (size = gap to Conv's return).
        const int32_t path_size = cv_ret - cv_in;
        if (path_size <= 0 || mk_ret + path_size > (int32_t)mk.buf.size()) return "fail|unexpected FSoftObjectPath layout";
        memcpy(conv.buf.data() + cv_in, mk.buf.data() + mk_ret, (size_t)path_size);
        ksl->process_event(conv.fn, conv.buf.data());

        // TSoftObjectPtr: copy Conv's return into Load's input (size = gap to Load's return).
        const int32_t ptr_size = ld_ret - ld_in;
        if (ptr_size <= 0 || cv_ret + ptr_size > (int32_t)conv.buf.size()) return "fail|unexpected TSoftObjectPtr layout";
        memcpy(load.buf.data() + ld_in, conv.buf.data() + cv_ret, (size_t)ptr_size);
        ksl->process_event(load.fn, load.buf.data());

        API::UObject* loaded = nullptr;
        memcpy(&loaded, load.buf.data() + ld_ret, sizeof(loaded));
        std::wstring lookup = L"BlueprintGeneratedClass " + wpath;
        auto found = api->find_uobject<API::UClass>(lookup);
        char b[160];
        snprintf(b, sizeof(b), "LoadAsset_Blocking returned %p; find_uobject after load %p", (void*)loaded, (void*)found);
        log("M1 %s", b);
        if (loaded == nullptr && found == nullptr) return "fail|not loaded (" + std::string(b) + ")";
        return "ok|" + path;
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
            m_device[i] = info.trackedDeviceIndex;
            m_type[i] = type;
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
            ActionInfo a{d, d.name.substr(d.name.find_last_of('/') + 1)};
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
            if (a.short_name == "Pose") m_pose = a.handle;
            m_actions.push_back(a);
        }
    }

    // Read-only capture. Digital edges and analog changes have separate budgets so stick noise
    // can never starve button edges.
    void capture() {
        const int64_t t = now_ms();
        ++m_ticks;
        if (vr_fn()->is_hmd_active()) ++m_ticks_hmd;
        if (vr_fn()->is_using_controllers()) ++m_ticks_ctl;

        std::vector<std::string> down;
        for (auto& a : m_actions) {
            if (a.handle == vr::k_ulInvalidActionHandle) continue;
            for (int i = 0; i < 2; ++i) {
                const std::string key = a.short_name + "@" + hand_name(i);
                if (a.decl.type == "boolean") {
                    vr::InputDigitalActionData_t d{};
                    auto err = m_input->GetDigitalActionData(a.handle, &d, sizeof(d), m_source[i]);
                    std::string v = err != vr::VRInputError_None ? "err" + std::to_string((int)err) : !d.bActive ? "inactive" : d.bState ? "1" : "0";
                    if (v == "1") down.push_back(key);
                    if (auto line = m_digital.change(key, v)) {
                        log("t=%lld dev=%u %s", (long long)t, m_device[i], line->c_str());
                        if (v == "1") ++m_presses[key];
                        first_change_to_lua(*line, v);
                    }
                } else if (a.decl.type == "vector1" || a.decl.type == "vector2") {
                    vr::InputAnalogActionData_t d{};
                    auto err = m_input->GetAnalogActionData(a.handle, &d, sizeof(d), m_source[i]);
                    if (err != vr::VRInputError_None || !d.bActive) {
                        std::string v = err != vr::VRInputError_None ? "err" + std::to_string((int)err) : "inactive";
                        if (auto line = m_analog_log.change(key, v)) log("t=%lld dev=%u %s", (long long)t, m_device[i], line->c_str());
                        continue;
                    }
                    m_analog_log.change(key, "active");
                    analog(t, i, key + ".x", d.x);
                    if (a.decl.type == "vector2") analog(t, i, key + ".y", d.y);
                } else if (a.decl.type == "skeleton") {
                    if ((i == 0) != (a.short_name.find("Left") != std::string::npos)) continue; // own hand only
                    vr::EVRSkeletalTrackingLevel lvl{};
                    auto err = m_input->GetSkeletalTrackingLevel(a.handle, &lvl);
                    std::string v = err != vr::VRInputError_None ? "err" + std::to_string((int)err) : "tracking_level=" + std::to_string((int)lvl);
                    if (auto line = m_digital.change(key, v)) {
                        log("t=%lld dev=%u %s", (long long)t, m_device[i], line->c_str());
                        first_change_to_lua(*line, v);
                    }
                    vr::InputSkeletalActionData_t action{};
                    vr::VRSkeletalSummaryData_t summary{};
                    auto data_err = m_input->GetSkeletalActionData(a.handle, &action, sizeof(action));
                    auto summary_err = data_err == vr::VRInputError_None && action.bActive
                        ? m_input->GetSkeletalSummaryData(a.handle, vr::VRSummaryType_FromDevice, &summary)
                        : vr::VRInputError_NoData;
                    const bool curls_valid = data_err == vr::VRInputError_None && action.bActive
                        && summary_err == vr::VRInputError_None;
                    if (curls_valid) {
                        const dvr::FingerCurls curls{summary.flFingerCurl[vr::VRFinger_Thumb],
                            summary.flFingerCurl[vr::VRFinger_Index], summary.flFingerCurl[vr::VRFinger_Middle],
                            summary.flFingerCurl[vr::VRFinger_Ring], summary.flFingerCurl[vr::VRFinger_Pinky]};
                        if (dvr::valid_finger_curls(curls)) {
                            m_finger_curls[i] = curls;
                            m_finger_valid[i] = true;
                            static const char* names[] = {"thumb", "index", "middle", "ring", "pinky"};
                            for (size_t finger = 0; finger < curls.size(); ++finger)
                                analog(t, i, std::string("FingerCurl.") + names[finger] + "@" + hand_name(i), curls[finger]);
                            if (t - m_last_finger_event_ms[i] >= 33) {
                                m_last_finger_event_ms[i] = t;
                                char sample[96];
                                snprintf(sample, sizeof(sample), "%s|%.3f,%.3f,%.3f,%.3f,%.3f", hand_name(i),
                                    curls[0], curls[1], curls[2], curls[3], curls[4]);
                                API::get()->dispatch_lua_event("dreadmoorvr_finger_curls", sample);
                            }
                            continue;
                        }
                    }
                    m_finger_valid[i] = false;
                    if (t - m_last_finger_event_ms[i] >= 250) {
                        m_last_finger_event_ms[i] = t;
                        std::string sample = std::string(hand_name(i)) + "|inactive";
                        API::get()->dispatch_lua_event("dreadmoorvr_finger_curls", sample);
                    }
                }
            }
        }
        m_down = down;

        // Tracking validity per hand from the Pose action.
        if (m_pose != vr::k_ulInvalidActionHandle) {
            for (int i = 0; i < 2; ++i) {
                vr::InputPoseActionData_t pd{};
                auto err = m_input->GetPoseActionDataRelativeToNow(m_pose, vr::TrackingUniverseStanding, 0.0f, &pd, sizeof(pd), m_source[i]);
                bool valid = err == vr::VRInputError_None && pd.bActive && pd.pose.bPoseIsValid;
                if (valid) ++m_pose_valid[i];
                // Lua uses this independent SteamVR validity signal to reject stale UEVR
                // controller coordinates. Send changes immediately and a 10 Hz heartbeat so
                // a stopped plugin/input poll cannot leave a valid state latched indefinitely.
                if (!m_pose_event_initialized[i] || valid != m_pose_event_valid[i]
                    || t - m_pose_event_ms[i] >= 100) {
                    m_pose_event_initialized[i] = true;
                    m_pose_event_valid[i] = valid;
                    m_pose_event_ms[i] = t;
                    const std::string sample = std::string(hand_name(i)) + (valid ? "|1" : "|0");
                    API::get()->dispatch_lua_event("dreadmoorvr_pose_validity", sample);
                }
                std::string v = err != vr::VRInputError_None ? "err" + std::to_string((int)err)
                                : valid ? "valid" : "invalid(result=" + std::to_string((int)pd.pose.eTrackingResult) + ")";
                if (auto line = m_digital.change(std::string("Pose@") + hand_name(i), v)) log("t=%lld dev=%u %s", (long long)t, m_device[i], line->c_str());
            }
        }

        report_drops(m_digital, m_dropped_digital_reported, "digital");
        report_drops(m_analog_log, m_dropped_analog_reported, "analog");
    }

    void analog(int64_t t, int hand, const std::string& key, float v) {
        if (auto q = m_filter.feed(key, v, t)) {
            if (auto line = m_analog_log.change(key, fmt_float(*q))) log("t=%lld dev=%u %s", (long long)t, m_device[hand], line->c_str());
        }
    }

    void first_change_to_lua(const std::string& line, const std::string& v) {
        if (m_first_change_sent || v == "inactive" || v.rfind("err", 0) == 0) return;
        m_first_change_sent = true;
        API::get()->dispatch_lua_event("dreadmoorvr_input", line);
    }

    void report_drops(const dvr::EdgeLog& e, size_t& reported, const char* budget) {
        if (e.dropped() >= reported + 50) {
            reported = e.dropped();
            log("%s telemetry cap reached (%zu lines); %zu changes dropped so far", budget, e.count(), e.dropped());
        }
    }

    void write_report() {
        auto dir = API::get()->get_persistent_dir();
        auto tmp = dir / "dreadmoorvr_input_report.tmp";
        auto out = dir / "dreadmoorvr_input_report.txt";
        {
            std::ofstream r(tmp, std::ios::trunc);
            if (!r) { if (!m_report_failed) { log("report write failed: %s", tmp.string().c_str()); m_report_failed = true; } return; }
            auto pct = [&](size_t n) { return m_ticks ? 100.0 * (double)n / (double)m_ticks : 0.0; };
            r << "DreadmoorVR input report (t=" << now_ms() / 1000 << " s since plugin load, " << m_ticks << " ticks)\n";
            r << "config: analog_step=" << m_cfg.analog_step << " analog_min_ms=" << m_cfg.analog_min_ms
              << " digital_cap=" << m_cfg.digital_cap << " analog_cap=" << m_cfg.analog_cap << " report_s=" << m_cfg.report_s << "\n";
            for (int i = 0; i < 2; ++i)
                r << "hand " << hand_name(i) << ": device " << m_device[i] << " type " << m_type[i]
                  << " pose valid " << pct(m_pose_valid[i]) << "%\n";
            r << "finger curls (0=open, 1=curled; FromDevice summary):\n";
            for (int i = 0; i < 2; ++i) {
                r << "  " << hand_name(i) << ": " << (m_finger_valid[i] ? "valid" : "unavailable")
                  << " thumb=" << m_finger_curls[i][0] << " index=" << m_finger_curls[i][1]
                  << " middle=" << m_finger_curls[i][2] << " ring=" << m_finger_curls[i][3]
                  << " pinky=" << m_finger_curls[i][4] << "\n";
            }
            r << "uevr: hmd_active " << pct(m_ticks_hmd) << "% of ticks, using_controllers " << pct(m_ticks_ctl) << "%\n";
            r << "presses (digital action -> count):\n";
            for (auto& [k, n] : m_presses) r << "  " << k << " " << n << "\n";
            r << "mapping (single action down -> pad the game received): " << m_map.summary() << "\n";
            r << "telemetry: digital " << m_digital.count() << " lines, " << m_digital.dropped() << " dropped; analog "
              << m_analog_log.count() << " lines, " << m_analog_log.dropped() << " dropped\n";
        }
        if (!MoveFileExW(tmp.wstring().c_str(), out.wstring().c_str(), MOVEFILE_REPLACE_EXISTING) && !m_report_failed) {
            log("report rename failed (%lu)", GetLastError());
            m_report_failed = true;
        }
    }

    std::mutex m_mtx;  // guards telemetry state shared with on_xinput_get_state
    std::string m_pending_class;  // M1: class path requested by Lua, loaded on the game thread
    dvr::TelemetryConfig m_cfg{};
    vr::IVRInput* m_input{nullptr};
    vr::IVRSystem* m_system{nullptr};
    vr::VRInputValueHandle_t m_source[2]{};
    vr::TrackedDeviceIndex_t m_device[2]{vr::k_unTrackedDeviceIndexInvalid, vr::k_unTrackedDeviceIndexInvalid};
    std::string m_type[2]{"?", "?"};
    vr::VRActionHandle_t m_pose{vr::k_ulInvalidActionHandle};
    std::vector<ActionInfo> m_actions;
    dvr::EdgeLog m_digital{3000};
    dvr::EdgeLog m_analog_log{600};
    dvr::AnalogFilter m_filter{0.25f, 250};
    dvr::MapAggregator m_map;
    std::vector<std::string> m_down;
    std::map<std::string, size_t> m_presses;
    dvr::FingerCurls m_finger_curls[2]{};
    bool m_finger_valid[2]{};
    int64_t m_last_finger_event_ms[2]{};
    bool m_pose_event_initialized[2]{};
    bool m_pose_event_valid[2]{};
    int64_t m_pose_event_ms[2]{};
    uint16_t m_last_pad{0xFFFF};
    size_t m_ticks{0}, m_ticks_hmd{0}, m_ticks_ctl{0}, m_pose_valid[2]{0, 0};
    size_t m_dropped_digital_reported{0}, m_dropped_analog_reported{0};
    int64_t m_last_report_ms{0};
    bool m_inventoried{false}, m_logged_wait{false}, m_first_change_sent{false}, m_acked{false}, m_report_failed{false};
    int m_pings{0};
    std::chrono::steady_clock::time_point m_last_ping{}, m_t0{};
};

std::unique_ptr<DreadmoorVRPlugin> g_plugin{new DreadmoorVRPlugin()};
