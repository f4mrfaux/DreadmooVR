-- Virtual gamepad. Gesture units ask for buttons and axes; merge() folds them into the real
-- XInput state each frame. Buttons are OR-ed; an axis is overridden only while held.
local pad = {}

local BUTTONS = {
    DUp = 0x0001, DDown = 0x0002, DLeft = 0x0004, DRight = 0x0008,
    Start = 0x0010, Back = 0x0020, LS = 0x0040, RS = 0x0080,
    LB = 0x0100, RB = 0x0200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000,
}
local TRIGGERS = { LT = "lt", RT = "rt" }
local AXES = { LX = "lx", LY = "ly", RX = "rx", RY = "ry" }

local held, taps, axes

function pad.reset()
    held, taps, axes = {}, {}, {}
end
pad.reset()

local function check(button)
    if not BUTTONS[button] and not TRIGGERS[button] then error("pad: unknown button " .. tostring(button), 3) end
end

function pad.press(button, on)
    check(button)
    held[button] = on and true or nil
end

-- Hold the button for `frames` calls of end_frame().
function pad.tap(button, frames)
    check(button)
    taps[button] = math.max(taps[button] or 0, frames or 1)
end

function pad.hold_axis(axis, value)
    if not AXES[axis] then error("pad: unknown axis " .. tostring(axis), 2) end
    axes[axis] = value
end

function pad.end_frame()
    for b, n in pairs(taps) do
        taps[b] = (n > 1) and (n - 1) or nil
    end
end

local function active(button)
    return held[button] or taps[button]
end

-- real: { buttons, lt, rt, lx, ly, rx, ry } with XInput ranges. Returns a new table.
function pad.merge(real)
    local m = { buttons = real.buttons, lt = real.lt, rt = real.rt,
                lx = real.lx, ly = real.ly, rx = real.rx, ry = real.ry }
    for name, bit in pairs(BUTTONS) do
        if active(name) then m.buttons = m.buttons | bit end
    end
    for name, field in pairs(TRIGGERS) do
        if active(name) then m[field] = 255 end
    end
    for name, field in pairs(AXES) do
        local v = axes[name]
        if v ~= nil then
            v = math.max(-1, math.min(1, v))
            local x = v * 32767
            m[field] = x >= 0 and math.floor(x + 0.5) or -math.floor(-x + 0.5)
        end
    end
    return m
end

-- Replaces the four face-button bits of buttons with the physical state (a, b, x, y booleans).
-- Used when more than one input path sets face buttons and they arrive mixed.
function pad.replace_face(buttons, a, b, x, y)
    local out = buttons & ~0xF000
    if a then out = out | 0x1000 end
    if b then out = out | 0x2000 end
    if x then out = out | 0x4000 end
    if y then out = out | 0x8000 end
    return out
end

return pad
