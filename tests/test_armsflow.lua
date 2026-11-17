local armsflow = require("armsflow")

local function walk_until_request(f)
    f:step(0.0, "walking", "pawnA")
    return f:step(2.0, "walking", "pawnA")
end

return {
    test_requests_after_walking_then_spawns = function()
        local f = armsflow.new()
        assert(walk_until_request(f) == "request")
        f:on_reply("ok|/Game/DreadmoorVR/BP_VRArms.BP_VRArms_C")
        assert(f:step(2.1, "walking", "pawnA") == "spawn")
        f:spawned(true)
        assert(f:step(2.2, "walking", "pawnA") == nil)
    end,

    test_hides_off_foot_and_shows_on_return = function()
        local f = armsflow.new()
        walk_until_request(f)
        f:on_reply("ok|x"); f:step(2.1, "walking", "pawnA"); f:spawned(true)
        assert(f:step(3.0, "fishing", "rig") == "hide")
        assert(f:step(3.1, "fishing", "rig") == nil, "hide once")
        assert(f:step(4.0, "walking", "pawnA") == "show")
        assert(f:step(4.1, "walking", "pawnA") == nil)
    end,

    test_new_walking_pawn_reattaches = function()
        local f = armsflow.new()
        walk_until_request(f)
        f:on_reply("ok|x"); f:step(2.1, "walking", "pawnA"); f:spawned(true)
        assert(f:step(5.0, "walking", "pawnB") == "reattach", "different pawn object")
        assert(f:step(5.1, "walking", "pawnB") == nil)
    end,

    test_lost_arms_respawn_on_foot = function()
        -- In game 2026-11-17: the pawn was replaced, the old arms actor died with it and the
        -- reattach threw. The flow must spawn fresh arms, not keep using the dead one.
        local f = armsflow.new()
        walk_until_request(f)
        f:on_reply("ok|x"); f:step(2.1, "walking", "pawnA"); f:spawned(true)
        assert(f:step(5.0, "walking", "pawnB") == "reattach")
        f:lost()
        assert(f:step(5.1, "boat", "pawnC") == nil, "waits until on foot")
        assert(f:step(5.2, "walking", "pawnB") == "spawn", "fresh arms")
        f:spawned(true)
        assert(f.status == "active" and f:step(5.3, "walking", "pawnB") == nil)
    end,

    test_respawning_gives_up_after_repeated_losses = function()
        local f = armsflow.new()
        walk_until_request(f)
        f:on_reply("ok|x"); f:step(2.1, "walking", "pawnA"); f:spawned(true)
        for i = 1, armsflow.MAX_RESPAWNS do
            f:lost()
            assert(f:step(3 + i, "walking", "pawnA") == "spawn", "respawn " .. i)
            f:spawned(true)
        end
        f:lost()
        assert(f:step(20, "walking", "pawnA") == nil and f.status == "fail", "stops instead of looping")
    end,

    test_failed_spawn_stops = function()
        local f = armsflow.new()
        walk_until_request(f)
        f:on_reply("ok|x"); f:step(2.1, "walking", "pawnA"); f:spawned(false)
        assert(f:step(3.0, "walking", "pawnA") == nil)
        assert(f.status == "spawn_failed")
    end,

    test_fail_reply_stops = function()
        local f = armsflow.new()
        walk_until_request(f)
        f:on_reply("fail|LoadAsset_Blocking not found")
        assert(f:step(9.0, "walking", "pawnA") == nil)
        assert(f.status == "fail" and f.reason == "LoadAsset_Blocking not found")
    end,
}
