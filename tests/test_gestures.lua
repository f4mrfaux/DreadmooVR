local gestures = require("gestures")

-- SteamVR tracking space, metres. Crank axis = X (the gun hand's sideways axis), up = Y.
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local AXIS, UP, PIVOT = v(1, 0, 0), v(0, 1, 0), v(0, 1.2, -0.3)
local DT = 1 / 60

-- Left hand circling the pivot in the Y/Z plane: radius r, deg_per_s (sign = direction), seconds.
local function circle(c, r, deg_per_s, seconds, t0)
    local clicks, t = 0, t0 or 0
    for i = 0, math.floor(seconds / DT) do
        local a = math.rad(deg_per_s * i * DT)
        local hand = v(PIVOT.X + 0.02, PIVOT.Y + r * math.cos(a), PIVOT.Z + r * math.sin(a))
        clicks = clicks + c:update(t, hand, PIVOT, AXIS, UP)
        t = t + DT
    end
    return clicks, t
end

return {
    test_crank_clicks_every_90_degrees = function()
        local c = gestures.crank({})
        local clicks = circle(c, 0.10, 360, 1.0)
        assert(clicks >= 3 and clicks <= 4, "one turn = 4 clicks (minus spin-up), got " .. clicks)
    end,

    test_crank_counts_either_direction = function()
        local c = gestures.crank({})
        local clicks = circle(c, 0.10, -360, 1.0)
        assert(clicks >= 3 and clicks <= 4, "reverse turn, got " .. clicks)
    end,

    test_slow_turning_is_not_a_crank = function()
        assert(circle(gestures.crank({}), 0.10, 90, 2.0) == 0, "90 deg/s is below the 180 deg/s gate")
    end,

    test_hand_too_far_from_the_crank_point = function()
        assert(circle(gestures.crank({}), 0.40, 360, 1.0) == 0, "40 cm is outside 4..25 cm")
        assert(circle(gestures.crank({}), 0.02, 360, 1.0) == 0, "2 cm is inside the dead centre")
    end,

    test_wiggling_back_and_forth_does_not_click = function()
        local c, clicks, t = gestures.crank({}), 0, 0
        for i = 0, 120 do   -- +/-30 degrees at 3 Hz: fast, but never 90 degrees one way
            local a = math.rad(30 * math.sin(2 * math.pi * 3 * i * DT))
            clicks = clicks + c:update(t, v(PIVOT.X, PIVOT.Y + 0.1 * math.cos(a), PIVOT.Z + 0.1 * math.sin(a)), PIVOT, AXIS, UP)
            t = t + DT
        end
        assert(clicks == 0, "wiggle clicked " .. clicks)
    end,

    test_swing_fires_once_per_swing = function()
        local s, hits, t, x = gestures.swing({}), 0, 0, 0
        for _ = 1, 18 do x = x + 3.0 * DT; if s:update(t, v(x, 1.2, -0.3)) then hits = hits + 1 end; t = t + DT end
        assert(hits == 1, "0.3 s at 3 m/s is one swing, got " .. hits)
        for _ = 1, 30 do if s:update(t, v(x, 1.2, -0.3)) then hits = hits + 1 end; t = t + DT end   -- rest 0.5 s
        for _ = 1, 10 do x = x - 3.0 * DT; if s:update(t, v(x, 1.2, -0.3)) then hits = hits + 1 end; t = t + DT end
        assert(hits == 2, "a second swing after the cooldown, got " .. hits)
    end,

    test_slow_arm_moves_are_not_swings = function()
        local s, t, x = gestures.swing({}), 0, 0
        for _ = 1, 60 do x = x + 1.0 * DT; assert(not s:update(t, v(x, 1.2, -0.3)), "1 m/s is not a swing"); t = t + DT end
    end,

    test_one_frame_tracking_jump_is_not_a_swing = function()
        local s, t = gestures.swing({}), 0
        for i = 1, 30 do
            local x = (i == 10) and 0.5 or 0   -- a single bad frame: 0.5 m jump and back
            assert(not s:update(t, v(x, 1.2, -0.3)), "glitch at frame " .. i)
            t = t + DT
        end
    end,

    test_tapper_turns_clicks_into_separate_presses = function()
        local p = gestures.tapper({ hold = 0.05, gap = 0.05 })
        p:add(2)
        local edges, last, t = 0, false, 0
        for _ = 1, 30 do
            local down = p:pressed(t)
            if down and not last then edges = edges + 1 end
            last = down; t = t + 0.01
        end
        assert(edges == 2, "two distinct presses, got " .. edges)
        assert(not p:pressed(t), "released afterwards")
    end,
}
