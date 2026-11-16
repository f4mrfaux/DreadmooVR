// Desk test for the plugin's pure core. Build: see plugin/CMakeLists.txt (target test_core).
#undef NDEBUG  // asserts must run in Release too
#include <cassert>
#include <fstream>
#include <sstream>
#include <cstdio>
#include "../src/core.hpp"

static void parse_manifest_finds_actions() {
    const char* json = R"({
      "actions": [
        { "name": "/actions/default/in/Squeeze", "type": "vector1" },
        { "name": "/actions/default/in/SkeletonLeftHand", "type": "skeleton", "skeleton": "/skeleton/hand/left" }
      ],
      "action_sets": [ { "name": "/actions/default", "usage": "single" } ]
    })";
    auto v = dvr::parse_manifest(json);
    assert(v.size() == 2);
    assert(v[0].name == "/actions/default/in/Squeeze" && v[0].type == "vector1");
    assert(v[1].type == "skeleton");
}

static void parse_manifest_bad_input() {
    assert(dvr::parse_manifest("{").empty());
    assert(dvr::parse_manifest("").empty());
    assert(dvr::parse_manifest(R"({"actions": [ { "name": "/a" )").empty());
}

static void edge_cap() {
    dvr::EdgeLog log(3);
    auto a = log.change("A@R", "1");
    assert(a && *a == "A@R=1");
    assert(!log.change("A@R", "1"));          // unchanged: nothing
    assert(log.change("A@R", "0"));            // 2nd logged change
    assert(log.change("B@L", "1"));            // 3rd logged change
    assert(!log.change("B@L", "0"));           // over cap: suppressed...
    assert(log.dropped() == 1);                // ...and counted as dropped
    assert(log.count() == 3);
}

static void runtime_gate() {
    assert(dvr::runtime_gate(true, true));
    assert(!dvr::runtime_gate(false, true));
    assert(!dvr::runtime_gate(true, false));
}

static void config_defaults() {
    auto d = dvr::parse_config("");
    assert(d.analog_step == 0.25f && d.analog_min_ms == 250 && d.digital_cap == 3000 && d.analog_cap == 600 && d.report_s == 30);
    auto g = dvr::parse_config("analog_step=x\nfoo=1\n=3\nreport_s=");
    assert(g.analog_step == 0.25f && g.report_s == 30);
}

static void config_values() {
    auto c = dvr::parse_config("analog_step=0.5\r\nanalog_min_ms=100\nreport_s=10\n# comment\n");
    assert(c.analog_step == 0.5f && c.analog_min_ms == 100 && c.report_s == 10);
}

static void analog_step() {
    dvr::AnalogFilter f(0.25f, 250);
    assert(f.feed("J@L", 0.0f, 0));              // first sight of a key always emits
    assert(!f.feed("J@L", 0.01f, 10));           // jitter around zero: nothing
    assert(!f.feed("J@L", 0.02f, 20));
    auto a = f.feed("J@L", 0.30f, 300);
    assert(a && *a == 0.25f);
    assert(!f.feed("J@L", 0.55f, 350));          // changed bucket but within min_ms
    auto z = f.feed("J@L", 0.0f, 360);           // to-zero always emits
    assert(z && *z == 0.0f);
}

static void mapping_multi() {
    dvr::MapAggregator m;
    m.observe({"X@R"}, 0x4000);
    m.observe({"X@R"}, 0x4000);
    m.observe({"A@R", "X@R"}, 0x5000);           // two at once: not a single mapping
    m.observe({}, 0x0010);                       // pad without action: not counted
    assert(m.summary() == "X@R->0x4000 x2");
}

static void budgets_separate() {
    dvr::EdgeLog analog(2), digital(2);
    assert(analog.change("J@L", "0.25") && analog.change("J@L", "0.50"));
    assert(!analog.change("J@L", "0.75") && analog.dropped() == 1);
    assert(digital.change("X@R", "1"));          // digital still logs
}

int main(int argc, char** argv) {
    parse_manifest_finds_actions();
    parse_manifest_bad_input();
    edge_cap();
    runtime_gate();
    config_defaults();
    config_values();
    analog_step();
    mapping_multi();
    budgets_separate();
    if (argc > 1) {  // optional: parse a real actions.json and list it
        std::ifstream f(argv[1]); std::stringstream ss; ss << f.rdbuf();
        auto v = dvr::parse_manifest(ss.str());
        assert(!v.empty());
        for (auto& a : v) std::printf("%s %s\n", a.type.c_str(), a.name.c_str());
        std::printf("parsed %zu actions\n", v.size());
    }
    std::puts("test_core: 9 passed");
    return 0;
}
