local armstats = require("armstats")

local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function r(p, y, rl) return { Pitch = p, Yaw = y, Roll = rl } end

return {
    test_sample_reach_and_rotation = function()
        local s = armstats.sample({
            target = v(100, 0, 0), target_rot = r(0, 90, 0),
            hand = v(97, 4, 0), hand_rot = r(10, 80, -170),
            shoulder = v(0, 0, 0), elbow = v(30, 0, -10),
        })
        assert(math.abs(s.reach_err - 5) < 1e-6, s.reach_err)
        assert(math.abs(s.shoulder_to_target - 100) < 1e-6)
        assert(math.abs(s.arm_len - (math.sqrt(1000) + math.sqrt(67*67 + 4*4 + 10*10))) < 1e-6)
        assert(s.over_reach == true, "100 cm target beyond a ~99 cm arm")
        assert(s.d_pitch == 10 and s.d_yaw == -10 and s.d_roll == -170, s.d_pitch .. " " .. s.d_yaw .. " " .. s.d_roll)
    end,

    test_angle_wraps_to_plus_minus_180 = function()
        assert(armstats.wrap(190) == -170)
        assert(armstats.wrap(-190) == 170)
        assert(armstats.wrap(180) == 180)
    end,

    test_summary_means_and_out_of_reach_percent = function()
        local acc = armstats.new()
        acc:add("L", { reach_err = 2, over_reach = false, d_pitch = 10, d_yaw = 0, d_roll = 0 })
        acc:add("L", { reach_err = 4, over_reach = true, d_pitch = 20, d_yaw = 0, d_roll = 0 })
        local line = acc:summary("L")
        assert(line == "L n=2 reach_err mean=3.0 max=4.0 out_of_reach=50% rot_offset(p,y,r)=(15.0,0.0,0.0)", line)
        assert(acc:summary("R") == "R n=0", acc:summary("R"))
    end,
}
