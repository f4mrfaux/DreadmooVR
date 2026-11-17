-- Arms tuning values (pure): merge a user table over defaults with validation, and flatten to the
-- BP_VRArms float variable names the bridge writes.
local tuning = {}

tuning.DEFAULTS = {
    left_rot = { p = 0, y = 0, r = 0 },   -- hand rotation offset in the controller's frame (deg)
    right_rot = { p = 0, y = 0, r = 0 },
    elbow_out = 30,                        -- elbow hint: cm outward from the body
    elbow_down = 45,                       -- elbow hint: cm down
    arm_length = 50.7,                     -- shoulder to hand (cm), measured in game 2026-11-16
    shoulder_follow = 1,                   -- 0..1: how much the shoulder moves toward an out-of-reach hand
    shoulder_widen = 0,                    -- cm each shoulder moves outward (player wider than character)
    grip_back = 0,                         -- cm from the controller grip back to the wrist (IK target)
}

local function num(v, lo, hi, default)
    if type(v) ~= "number" or v ~= v or v < lo or v > hi then return default end
    return v
end

-- Whole number in lo..hi, else nil (optional settings: absent or bad = leave UEVR's own value).
local function int(v, lo, hi)
    if type(v) ~= "number" or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

local function rot(u, d)
    u = type(u) == "table" and u or {}
    return { p = num(u.p, -360, 360, d.p), y = num(u.y, -360, 360, d.y), r = num(u.r, -360, 360, d.r) }
end

function tuning.merge(u)
    u = type(u) == "table" and u or {}
    local d = tuning.DEFAULTS
    local sf = type(u.shoulder_follow) == "number" and math.max(0, math.min(1, u.shoulder_follow)) or d.shoulder_follow
    return {
        left_rot = rot(u.left_rot, d.left_rot),
        right_rot = rot(u.right_rot, d.right_rot),
        elbow_out = num(u.elbow_out, -100, 100, d.elbow_out),
        elbow_down = num(u.elbow_down, -100, 100, d.elbow_down),
        arm_length = num(u.arm_length, 20, 120, d.arm_length),
        shoulder_follow = sf,
        shoulder_widen = num(u.shoulder_widen, -10, 30, d.shoulder_widen),
        grip_back = num(u.grip_back, -20, 20, d.grip_back),
        camera_forward = num(u.camera_forward, -100, 100, nil),   -- UEVR VR_CameraForwardOffset (cm)
        camera_up = num(u.camera_up, -100, 100, nil),             -- UEVR VR_CameraUpOffset (cm)
        aim_method = int(u.aim_method, 0, 5),                     -- UEVR VR_AimMethod (VR.hpp:45)
        movement_orientation = int(u.movement_orientation, 0, 5), -- UEVR VR_MovementOrientation
        items_follow_hands = u.items_follow_hands == true,        -- held tools move onto the VR hands
        shoulder_swing = num(u.shoulder_swing, 0, 1, 1),          -- 0..1 of UBIK's forward clavicle turn
        item_rot = rot(u.item_rot, { p = 0, y = 0, r = 0 }),       -- held tools, turned in the hand's frame (deg)
        level_torso = u.level_torso == true,                      -- the game's torso ignores look pitch
    }
end

function tuning.flatten(t)
    return {
        LeftRotP = t.left_rot.p, LeftRotY = t.left_rot.y, LeftRotR = t.left_rot.r,
        RightRotP = t.right_rot.p, RightRotY = t.right_rot.y, RightRotR = t.right_rot.r,
        ElbowOut = t.elbow_out, ElbowDown = t.elbow_down,
        ArmLength = t.arm_length, ShoulderFollow = t.shoulder_follow,
    }
end

return tuning
