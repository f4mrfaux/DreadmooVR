-- DreadmoorVR arms tuning. Edited live: the bridge reloads this file every second, no restart.
-- Rotations are degrees in the controller's frame (p = pitch, y = yaw, r = roll).
return {
    left_rot = { p = -4, y = -3, r = 177 },
    right_rot = { p = 4, y = -177, r = -3 },
    elbow_out = 5,        -- cm outward from the body
    elbow_down = 70,       -- cm down
    arm_length = 50.7,     -- cm, shoulder to hand (measured)
    shoulder_follow = 0,   -- 0..1, shoulder moves toward an out-of-reach hand
}
