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

    test_body_fit_values_default_to_zero_and_clamp = function()
        local t = tuning.merge(nil)
        assert(t.shoulder_widen == 0 and t.grip_back == 0, "defaults leave the body as built")
        local u = tuning.merge({ shoulder_widen = 8, grip_back = 9 })
        assert(u.shoulder_widen == 8 and u.grip_back == 9)
        local bad = tuning.merge({ shoulder_widen = 500, grip_back = "far" })
        assert(bad.shoulder_widen == 0 and bad.grip_back == 0, "out of range falls back")
    end,

    test_camera_offsets_are_optional = function()
        local t = tuning.merge(nil)
        assert(t.camera_forward == nil and t.camera_up == nil, "absent = leave UEVR's own setting alone")
        local u = tuning.merge({ camera_forward = 10, camera_up = 42 })
        assert(u.camera_forward == 10 and u.camera_up == 42)
        local bad = tuning.merge({ camera_forward = 900, camera_up = "x" })
        assert(bad.camera_forward == nil and bad.camera_up == nil, "bad values are ignored, not defaulted")
    end,

    test_aim_and_movement_methods_are_optional_integers = function()
        local t = tuning.merge(nil)
        assert(t.aim_method == nil and t.movement_orientation == nil)
        local u = tuning.merge({ aim_method = 2, movement_orientation = 1 })
        assert(u.aim_method == 2 and u.movement_orientation == 1)
        local bad = tuning.merge({ aim_method = 9, movement_orientation = 1.5 })
        assert(bad.aim_method == nil and bad.movement_orientation == nil, "UEVR AimMethod is 0..5, whole numbers")
    end,

    test_items_follow_hands_is_off_unless_true = function()
        assert(tuning.merge(nil).items_follow_hands == false)
        assert(tuning.merge({ items_follow_hands = true }).items_follow_hands == true)
        assert(tuning.merge({ items_follow_hands = "yes" }).items_follow_hands == false, "only a real true turns it on")
    end,

    test_level_torso_is_off_unless_true = function()
        assert(tuning.merge(nil).level_torso == false)
        assert(tuning.merge({ level_torso = true }).level_torso == true)
        assert(tuning.merge({ level_torso = 1 }).level_torso == false)
    end,

    test_shoulder_swing_scales_the_forward_shoulder_turn = function()
        assert(tuning.merge(nil).shoulder_swing == 1, "full UBIK by default")
        assert(tuning.merge({ shoulder_swing = 0.3 }).shoulder_swing == 0.3)
        assert(tuning.merge({ shoulder_swing = 2 }).shoulder_swing == 1, "0..1 only")
    end,

    test_flatten_names_match_blueprint_variables = function()
        local f = tuning.flatten(tuning.merge({ right_rot = { y = -15 } }))
        assert(f.RightRotY == -15 and f.LeftRotP == 0 and f.ElbowOut == 30 and f.ArmLength == 50.7 and f.ShoulderFollow == 1)
        local n = 0
        for _ in pairs(f) do n = n + 1 end
        assert(n == 10, "10 Blueprint variables, got " .. n)
    end,
}
