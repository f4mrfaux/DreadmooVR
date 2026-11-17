local reticle = require("reticle")
local function near(a, b, e) return math.abs(a - b) < (e or 1e-6) end

return {
    test_direction_matches_unreal_rotator_to_vector = function()
        local f = reticle.direction(0, 0)            -- pitch, yaw (deg): straight along +X
        assert(near(f.X, 1) and near(f.Y, 0) and near(f.Z, 0))
        local r = reticle.direction(0, 90)           -- yaw 90: +Y
        assert(near(r.X, 0) and near(r.Y, 1))
        local u = reticle.direction(90, 0)           -- pitch 90: straight up
        assert(near(u.Z, 1) and near(u.X, 0))
        local d = reticle.direction(-45, 0)
        assert(near(d.X, math.sqrt(0.5)) and near(d.Z, -math.sqrt(0.5)))
    end,

    test_trace_end_is_start_plus_length_along_view = function()
        local e = reticle.trace_end({ X = 100, Y = 0, Z = 170 }, 0, 90, 5000)
        assert(near(e.X, 100) and near(e.Y, 5000) and near(e.Z, 170))
    end,

    test_dot_keeps_the_same_apparent_size = function()
        -- Scale of a 100 cm engine sphere: about 0.4 degrees across at any distance.
        local near_s, far_s = reticle.dot_scale(200), reticle.dot_scale(2000)
        assert(near(far_s / near_s, 10, 1e-6), "ten times further, ten times bigger")
        assert(reticle.dot_scale(1) >= reticle.MIN_SCALE and reticle.dot_scale(1e7) <= reticle.MAX_SCALE, "clamped")
    end,
}
