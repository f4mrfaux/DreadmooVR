local m1flow = require("m1flow")

return {
    test_requests_after_two_seconds_walking = function()
        local f = m1flow.new()
        assert(f:step(0.0, true) == nil)
        assert(f:step(1.9, true) == nil)
        assert(f:step(2.0, true) == "request")
        assert(f:step(2.5, true) == nil, "no repeat before the retry interval")
    end,

    test_not_walking_resets_timer = function()
        local f = m1flow.new()
        f:step(0.0, true); f:step(1.5, true)
        assert(f:step(1.6, false) == nil)
        assert(f:step(3.0, true) == nil, "timer restarted when walking resumed")
        assert(f:step(5.0, true) == "request")
    end,

    test_retries_until_reply_then_spawns_once = function()
        local f = m1flow.new()
        f:step(0.0, true)
        assert(f:step(2.0, true) == "request")
        assert(f:step(5.0, true) == "request", "retry after 3 s without a reply")
        f:on_reply("ok|/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C")
        assert(f:step(5.1, true) == "spawn")
        f:spawned(true)
        assert(f:step(9.0, true) == nil, "done after a spawn")
    end,

    test_fail_reply_stops_and_keeps_reason = function()
        local f = m1flow.new()
        f:step(0.0, true); f:step(2.0, true)
        f:on_reply("fail|LoadAsset_Blocking not found")
        assert(f:step(10.0, true) == nil)
        assert(f.status == "fail" and f.reason == "LoadAsset_Blocking not found", tostring(f.reason))
    end,

    test_gives_up_after_max_requests = function()
        local f = m1flow.new()
        local n, t = 0, 0
        f:step(t, true)
        for _ = 1, 40 do
            t = t + 3
            if f:step(t, true) == "request" then n = n + 1 end
        end
        assert(n == 10, "capped at 10 requests, got " .. n)
        assert(f.status == "no_reply")
    end,
}
