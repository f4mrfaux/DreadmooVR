local tuning = require("tuning")

return {
    test_defaults_when_nil = function()
        local t = tuning.merge(nil)
        assert(t.left_rot.p == 0 and t.right_rot.r == 0)
        assert(t.elbow_out == 30 and t.elbow_down == 45 and t.arm_length == 50.7 and t.shoulder_follow == 1)
    end,

    test_partial_override_keeps_other_defaults = function()
        local t = tuning.merge({ left_rot = { r = 90 }, elbow_out = 20 })
        assert(t.left_rot.r == 90 and t.left_rot.p == 0 and t.left_rot.y == 0)
        assert(t.elbow_out == 20 and t.elbow_down == 45)
    end,

    test_bad_values_fall_back = function()
        local t = tuning.merge({ elbow_out = "lots", left_rot = { p = 1e9 }, shoulder_follow = -3 })
        assert(t.elbow_out == 30, "non-number ignored")
        assert(t.left_rot.p == 0, "out-of-range angle ignored")
        assert(t.shoulder_follow == 0, "clamped to 0..1")
    end,

    test_flatten_names_match_blueprint_variables = function()
        local f = tuning.flatten(tuning.merge({ right_rot = { y = -15 } }))
        assert(f.RightRotY == -15 and f.LeftRotP == 0 and f.ElbowOut == 30 and f.ArmLength == 50.7 and f.ShoulderFollow == 1)
        local n = 0
        for _ in pairs(f) do n = n + 1 end
        assert(n == 10, "10 Blueprint variables, got " .. n)
    end,
}
