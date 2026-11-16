// Pure, UEVR-free logic for DreadmoorVR.dll. Desk-tested by tests/test_core.cpp.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace dvr {

struct ActionDecl {
    std::string name;
    std::string type;
};

namespace detail {
// Reads a JSON string starting at s[i] == '"'. Returns end index past the closing quote, or npos.
inline size_t read_string(std::string_view s, size_t i, std::string& out) {
    out.clear();
    for (size_t j = i + 1; j < s.size(); ++j) {
        if (s[j] == '\\' && j + 1 < s.size()) { out += s[++j]; continue; }
        if (s[j] == '"') return j + 1;
        out += s[j];
    }
    return std::string_view::npos;
}
} // namespace detail

// Extracts {name, type} for every object in the top-level "actions" array of an OpenVR action
// manifest. No JSON library: scans objects by brace depth. Malformed input -> empty vector.
inline std::vector<ActionDecl> parse_manifest(std::string_view json) {
    std::vector<ActionDecl> out;
    size_t k = json.find("\"actions\"");
    if (k == std::string_view::npos) return {};
    size_t i = json.find('[', k);
    if (i == std::string_view::npos) return {};

    int depth = 0;
    ActionDecl cur;
    std::string key, val;
    bool closed = false;
    for (++i; i < json.size(); ++i) {
        char c = json[i];
        if (c == '"') {
            size_t e = detail::read_string(json, i, key);
            if (e == std::string_view::npos) return {};
            i = e;
            while (i < json.size() && (json[i] == ' ' || json[i] == '\t' || json[i] == '\n' || json[i] == '\r')) ++i;
            if (i < json.size() && json[i] == ':' && depth == 1) {
                ++i;
                while (i < json.size() && json[i] != '"' && json[i] != '{' && json[i] != '[' && json[i] != ',' && json[i] != '}') ++i;
                if (i < json.size() && json[i] == '"') {
                    size_t e2 = detail::read_string(json, i, val);
                    if (e2 == std::string_view::npos) return {};
                    if (key == "name") cur.name = val;
                    else if (key == "type") cur.type = val;
                    i = e2;
                }
            }
            --i; // loop increments
            continue;
        }
        if (c == '{') { if (++depth == 1) cur = {}; }
        else if (c == '}') {
            if (depth == 1 && !cur.name.empty()) out.push_back(cur);
            --depth;
        } else if (c == ']' && depth == 0) { closed = true; break; }
    }
    if (!closed) return {};
    return out;
}

// Edge-triggered change log with a cap. change() returns "key=value" when the value differs from
// the last one seen for key and the cap is not reached; changes past the cap are counted as dropped.
class EdgeLog {
public:
    explicit EdgeLog(size_t cap) : m_cap(cap) {}

    std::optional<std::string> change(const std::string& key, const std::string& value) {
        auto it = m_last.find(key);
        if (it != m_last.end() && it->second == value) return std::nullopt;
        m_last[key] = value;
        if (m_count >= m_cap) { ++m_dropped; return std::nullopt; }
        ++m_count;
        return key + "=" + value;
    }

    size_t count() const { return m_count; }
    size_t dropped() const { return m_dropped; }

private:
    size_t m_cap;
    size_t m_count{0};
    size_t m_dropped{0};
    std::unordered_map<std::string, std::string> m_last;
};

// Phase 2 telemetry settings, read from <profile>\dreadmoorvr_telemetry.txt (optional).
struct TelemetryConfig {
    float analog_step = 0.25f;   // analog values are quantised to this step
    int analog_min_ms = 250;     // min time between logged changes of one analog key
    size_t digital_cap = 3000;   // log budget for digital edges
    size_t analog_cap = 600;     // separate budget for analog changes
    int report_s = 30;           // report file rewrite interval
};

// "key=value" lines; '#' comments, unknown keys and unparsable values are ignored.
inline TelemetryConfig parse_config(std::string_view text) {
    TelemetryConfig c;
    size_t pos = 0;
    while (pos < text.size()) {
        size_t end = text.find('\n', pos);
        if (end == std::string_view::npos) end = text.size();
        std::string line(text.substr(pos, end - pos));
        pos = end + 1;
        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
        size_t eq = line.find('=');
        if (line.empty() || line[0] == '#' || eq == std::string::npos || eq == 0 || eq + 1 >= line.size()) continue;
        std::string k = line.substr(0, eq), v = line.substr(eq + 1);
        try {
            size_t used = 0;
            if (k == "analog_step") { float f = std::stof(v, &used); if (used == v.size() && f > 0) c.analog_step = f; }
            else if (k == "analog_min_ms") { int i = std::stoi(v, &used); if (used == v.size() && i >= 0) c.analog_min_ms = i; }
            else if (k == "digital_cap") { long long i = std::stoll(v, &used); if (used == v.size() && i > 0) c.digital_cap = (size_t)i; }
            else if (k == "analog_cap") { long long i = std::stoll(v, &used); if (used == v.size() && i > 0) c.analog_cap = (size_t)i; }
            else if (k == "report_s") { int i = std::stoi(v, &used); if (used == v.size() && i > 0) c.report_s = i; }
        } catch (...) {
        }
    }
    return c;
}

// Quantises analog values and rate-limits per key. Emits on the first sight of a key, on any
// change to or from zero, and on other bucket changes at least min_ms after the key's last emit.
class AnalogFilter {
public:
    AnalogFilter(float step, int min_ms) : m_step(step), m_min_ms(min_ms) {}

    std::optional<float> feed(const std::string& key, float v, int64_t now_ms) {
        float q = (float)((long long)(v / m_step + (v >= 0 ? 0.5f : -0.5f))) * m_step;
        auto it = m_state.find(key);
        if (it == m_state.end()) { m_state[key] = {q, now_ms}; return q; }
        auto& s = it->second;
        if (q == s.value) return std::nullopt;
        bool zero_edge = (q == 0.0f) || (s.value == 0.0f);
        if (!zero_edge && now_ms - s.last_ms < m_min_ms) return std::nullopt;
        s = {q, now_ms};
        return q;
    }

private:
    struct State { float value; int64_t last_ms; };
    float m_step;
    int m_min_ms;
    std::unordered_map<std::string, State> m_state;
};

// Counts "action -> gamepad buttons" when exactly one digital action is down and the pad the
// game received has buttons set. Summary in first-seen order: "X@R->0x4000 x2; ...".
class MapAggregator {
public:
    void observe(const std::vector<std::string>& down, uint16_t pad) {
        if (down.size() != 1 || pad == 0) return;
        char buf[16];
        snprintf(buf, sizeof(buf), "0x%04X", pad);
        std::string key = down[0] + "->" + buf;
        auto it = m_counts.find(key);
        if (it == m_counts.end()) { m_order.push_back(key); m_counts[key] = 1; }
        else ++it->second;
    }

    std::string summary() const {
        std::string out;
        for (auto& k : m_order) {
            if (!out.empty()) out += "; ";
            out += k + " x" + std::to_string(m_counts.at(k));
        }
        return out;
    }

private:
    std::vector<std::string> m_order;
    std::unordered_map<std::string, size_t> m_counts;
};

// The plugin only touches IVRInput when UEVR runs OpenVR and its runtime is ready.
inline bool runtime_gate(bool is_openvr, bool runtime_ready) { return is_openvr && runtime_ready; }

} // namespace dvr
