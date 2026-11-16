// Pure, UEVR-free logic for DreadmoorVR.dll. Desk-tested by tests/test_core.cpp.
#pragma once
#include <cstddef>
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

// The plugin only touches IVRInput when UEVR runs OpenVR and its runtime is ready.
inline bool runtime_gate(bool is_openvr, bool runtime_ready) { return is_openvr && runtime_ready; }

} // namespace dvr
