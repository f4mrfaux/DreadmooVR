-- DreadmoorVR arms tuning. Edited live: the bridge reloads this file every second, no restart.
-- Rotations are degrees in the controller's frame (p = pitch, y = yaw, r = roll).
return {
    left_rot = { p = 0, y = 0, r = 0 },
    right_rot = { p = 0, y = 0, r = 0 },
    elbow_out = 30,        -- cm outward from the body
    elbow_down = 45,       -- cm down
    arm_length = 50.7,     -- cm, shoulder to hand (measured)
    shoulder_follow = 1,   -- 0..1, shoulder moves toward an out-of-reach hand
}
