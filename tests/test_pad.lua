local pad = require("pad")

local function real(t)
    local r = { buttons = 0, lt = 0, rt = 0, lx = 0, ly = 0, rx = 0, ry = 0 }
    for k, v in pairs(t or {}) do r[k] = v end
    return r
end

return {
    test_pad_merge_or_buttons = function()
        pad.reset()
        pad.press("A", true)
        local m = pad.merge(real({ buttons = 0x1000 | 0x2000 }))  -- real A and B
        assert(m.buttons & 0x1000 ~= 0, "A set")
        assert(m.buttons & 0x2000 ~= 0, "B set")
        pad.press("A", false)
        m = pad.merge(real({ buttons = 0x1000 }))
        assert(m.buttons & 0x1000 ~= 0, "real A survives virtual release")
    end,

    test_pad_merge_trigger = function()
        pad.reset()
        pad.press("RT", true)
        assert(pad.merge(real()).rt == 255)
        pad.press("RT", false)
        assert(pad.merge(real({ rt = 40 })).rt == 40)
    end,

    test_pad_merge_axis_override_and_release = function()
        pad.reset()
        pad.hold_axis("LX", -1)
        assert(pad.merge(real({ lx = 12000 })).lx == -32767)
        pad.hold_axis("LX", nil)
        assert(pad.merge(real({ lx = 12000 })).lx == 12000)
    end,

    test_pad_axis_clamped = function()
        pad.reset()
        pad.hold_axis("RY", 3)
        assert(pad.merge(real()).ry == 32767)
    end,

    test_pad_tap_lasts_n_frames = function()
        pad.reset()
        pad.tap("X", 2)
        assert(pad.merge(real()).buttons & 0x4000 ~= 0)
        pad.end_frame()
        assert(pad.merge(real()).buttons & 0x4000 ~= 0)
        pad.end_frame()
        assert(pad.merge(real()).buttons & 0x4000 == 0)
    end,

    test_pad_merge_does_not_mutate_input = function()
        pad.reset()
        pad.press("A", true)
        local r = real()
        pad.merge(r)
        assert(r.buttons == 0)
    end,

    test_pad_unknown_button_errors = function()
        pad.reset()
        assert(not pcall(pad.press, "Q", true))
    end,

    test_pad_replace_face_x_only = function()
        -- Incoming A+X plus LB; physically only X is down -> X and LB remain.
        assert(pad.replace_face(0x5100, false, false, true, false) == 0x4100)
    end,

    test_pad_replace_face_all_and_none = function()
        assert(pad.replace_face(0x0000, true, true, true, true) == 0xF000)
        assert(pad.replace_face(0xF00F, false, false, false, false) == 0x000F)
    end,
}
