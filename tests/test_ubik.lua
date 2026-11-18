local ubik = require("ubik")

local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function near(a, b, e) return math.abs(a - b) < (e or 1e-3) end
local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end

-- Body faces +X (yaw 0): forward +X, right +Y, up +Z. Left shoulder at -Y.
local F, R = v(1, 0, 0), v(0, 1, 0)

return {
    test_cosine_rule_matches_ubik = function()
        assert(near(ubik.cosine_rule(1, 1, math.sqrt(2)), 90, 1e-6))
        assert(near(ubik.cosine_rule(3, 4, 5), 90, 1e-6))
    end,

    test_elbow_respects_bone_lengths = function()
        local S, H = v(0, -20, 140), v(30, -25, 110)
        local e = ubik.elbow({ shoulder = S, hand = H, upper = 28, lower = 26, swivel = 26, outward = v(0, -1, 0) })
        assert(near(dist(S, e), 28, 1e-3), "upper " .. dist(S, e))
        assert(near(dist(H, e), 26, 1e-3), "lower " .. dist(H, e))
    end,

    test_swivel_zero_points_elbow_down_positive_points_out = function()
        local S, H = v(0, -20, 140), v(40, -20, 140)  -- hand straight ahead at shoulder height
        local down = ubik.elbow({ shoulder = S, hand = H, upper = 28, lower = 26, swivel = 0, outward = v(0, -1, 0) })
        assert(down.Z < 140 - 10 and near(down.Y, -20, 1e-3), "swivel 0 hangs below the shoulder-hand line")
        local out = ubik.elbow({ shoulder = S, hand = H, upper = 28, lower = 26, swivel = 90, outward = v(0, -1, 0) })
        assert(out.Y < -30 and near(out.Z, 140, 1e-3), "swivel 90 points the left elbow out to -Y")
    end,

    test_out_of_reach_hand_gives_straight_arm = function()
        local S, H = v(0, 0, 0), v(100, 0, 0)
        local e = ubik.elbow({ shoulder = S, hand = H, upper = 28, lower = 26, swivel = 26, outward = v(0, -1, 0) })
        assert(near(e.X, 28, 1e-2) and near(e.Y, 0, 1e-2) and near(e.Z, 0, 1e-2), "elbow on the line, upper length out")
    end,

    test_base_swivel_ubik_formula = function()
        -- RotateElbowByHandPosition: 90 + 130*max(0, outward/armLen + 0.2), our swivel = that - 90.
        assert(near(ubik.base_swivel(0, 55), 26))            -- hand in line with the shoulder: 130*0.2
        assert(near(ubik.base_swivel(-11, 55), 0))           -- hand 0.2 armLen inward: clamps to 0
        assert(near(ubik.base_swivel(27.5, 55), 91))         -- half an arm outward: 130*0.7
    end,

    test_clavicle_angles_ubik_formula = function()
        -- RotateUpperArm: forward ratio 1.0 -> yaw (1-0.5)*60 = 30; up ratio 0.7 -> roll (0.7-0.2)*60 = 30.
        local yaw, roll = ubik.clavicle_angles(55, 38.5, 55)
        assert(near(yaw, 30) and near(roll, 30), yaw .. " " .. roll)
        local y2, r2 = ubik.clavicle_angles(0, 0, 55)        -- hand at the shoulder: back side, clamps
        assert(near(y2, -0.08 * 60) and near(r2, 0), y2 .. " " .. r2)
        local y3 = ubik.clavicle_angles(200, 0, 55)
        assert(near(y3, 45), "yaw limited to 45")
    end,

    test_shoulder_shift_zero_at_rest_and_forward_when_reaching = function()
        local K, P0 = v(0, -5, 140), v(0, -20, 140)     -- clavicle root, upper arm rest
        local s0 = ubik.shoulder_shift({ clavicle = K, rest = P0, yaw = 0, roll = 0, forward = F, up = v(0, 0, 1) })
        assert(near(s0.X, 0) and near(s0.Y, 0) and near(s0.Z, 0))
        local s1 = ubik.shoulder_shift({ clavicle = K, rest = P0, yaw = 30, roll = 0, forward = F, up = v(0, 0, 1) })
        assert(s1.X > 5 and near(math.sqrt((s1.X)^2 + (s1.Y + 0)^2) , s1.X / math.cos(math.rad(15)) * math.cos(math.rad(15)), 1), "moves forward")
        assert(near(dist(v(K.X, K.Y, K.Z), v(P0.X + s1.X, P0.Y + s1.Y, P0.Z + s1.Z)), 15, 1e-3), "stays on the clavicle radius")
    end,

    test_shoulder_follow_is_proportional_then_hard_capped = function()
        local S = v(0, 0, 0)
        local small = ubik.shoulder_follow_shift(S, v(60, 0, 0), 50, 0.5, 12)
        assert(near(small.X, 5) and small.Y == 0 and small.Z == 0, "small overreach follows by influence")
        local far = ubik.shoulder_follow_shift(S, v(500, 0, 0), 50, 0.5, 12)
        assert(near(far.X, 12) and far.Y == 0 and far.Z == 0, "tracking spikes cannot exceed the cap")
        local inward = ubik.shoulder_follow_shift(S, v(40, 0, 0), 50, 0.5, 12)
        assert(inward.X == 0 and inward.Y == 0 and inward.Z == 0, "no shift while the arm is in reach")
    end,

    test_calibration_tracks_widest_span = function()
        local c = ubik.calibration.new()
        c:add(v(0, -60, 140), v(0, 60, 140), 30)   -- span 120, shoulders 30 apart -> arm 45
        c:add(v(0, -70, 140), v(0, 70, 140), 30)   -- span 140 -> arm 55
        c:add(v(0, -10, 140), v(0, 10, 140), 30)   -- narrower: ignored
        assert(near(c:arm_length(), 55), tostring(c:arm_length()))
        assert(ubik.calibration.new():arm_length() == nil, "no data yet")
    end,
}
