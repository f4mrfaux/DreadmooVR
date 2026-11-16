local wf = require("wristfit")

local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-3) end
local function v(x, y, z) return { X = x, Y = y, Z = z } end

-- Controller frame aligned with world: forward +X, right +Y, up +Z.
local F, R, U = v(1, 0, 0), v(0, 1, 0), v(0, 0, 1)

return {
    test_rotator_matrix_roundtrip = function()
        for _, r in ipairs({ { 0, 0, 0 }, { 10, 20, 30 }, { -45, 170, -80 }, { 0, 90, 90 } }) do
            local p, y, rl = wf.matrix_to_rotator(wf.rotator_to_matrix(r[1], r[2], r[3]))
            assert(near(p, r[1]) and near(y, r[2]) and near(rl, r[3]), string.format("%g %g %g", p, y, rl))
        end
    end,

    test_already_aligned_keeps_current_offset = function()
        -- fingers forward (+X), index above pinky (+Z): already a natural grip.
        local s = wf.suggest({ F = F, R = R, U = U, hand = v(0, 0, 0), middle = v(10, 0, 0),
            index = v(10, 0, 2), pinky = v(10, 0, -2), current = { p = 5, y = -5, r = 3 } })
        assert(near(s.p, 5) and near(s.y, -5) and near(s.r, 3), string.format("%g %g %g", s.p, s.y, s.r))
    end,

    test_fingers_pointing_up_needs_pitch_down = function()
        -- fingers point up (+Z), knuckle line points back (-X): rotate -90 pitch to bring fingers forward.
        local s = wf.suggest({ F = F, R = R, U = U, hand = v(0, 0, 0), middle = v(0, 0, 10),
            index = v(-2, 0, 10), pinky = v(2, 0, 10), current = { p = 0, y = 0, r = 0 } })
        local m = wf.rotator_to_matrix(s.p, s.y, s.r)
        -- applying the suggested offset to the measured finger axis must give +X
        local fx = m[1][3] * 1  -- column X of matrix times measured axis (0,0,1): row-wise product
        assert(near(s.p, -90, 0.5), "pitch " .. s.p)
    end,

    test_rolled_hand_needs_roll_correction = function()
        -- fingers forward, but knuckle line points right (+Y) instead of up: a 90 roll error.
        local s = wf.suggest({ F = F, R = R, U = U, hand = v(0, 0, 0), middle = v(10, 0, 0),
            index = v(10, 2, 0), pinky = v(10, -2, 0), current = { p = 0, y = 0, r = 0 } })
        assert(near(math.abs(s.r), 90, 0.5) and near(s.p, 0, 0.5) and near(s.y, 0, 0.5),
            string.format("%g %g %g", s.p, s.y, s.r))
    end,
}
