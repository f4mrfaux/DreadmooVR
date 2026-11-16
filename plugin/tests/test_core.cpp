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

int main(int argc, char** argv) {
    parse_manifest_finds_actions();
    parse_manifest_bad_input();
    edge_cap();
    runtime_gate();
    if (argc > 1) {  // optional: parse a real actions.json and list it
        std::ifstream f(argv[1]); std::stringstream ss; ss << f.rdbuf();
        auto v = dvr::parse_manifest(ss.str());
        assert(!v.empty());
        for (auto& a : v) std::printf("%s %s\n", a.type.c_str(), a.name.c_str());
        std::printf("parsed %zu actions\n", v.size());
    }
    std::puts("test_core: 4 passed");
    return 0;
}
