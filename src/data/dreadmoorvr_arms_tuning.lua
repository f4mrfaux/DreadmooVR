-- DreadmoorVR arms tuning. Edited live: the bridge reloads this file every second, no restart.
-- Rotations are degrees in the controller's frame (p = pitch, y = yaw, r = roll).
return {
    left_rot = { p = -4, y = -3, r = 177 },
    right_rot = { p = 4, y = -177, r = -3 },
    elbow_out = 5,        -- cm outward from the body
    elbow_down = 70,       -- cm down
    arm_length = 50.7,     -- cm, shoulder to hand (measured)
    shoulder_follow = 0,   -- 0..1, shoulder moves toward an out-of-reach hand
    shoulder_widen = 5,    -- cm each shoulder moves outward (you are wider than the character)
    grip_back = 8,         -- cm from the controller grip back to your wrist
    camera_forward = -30,  -- cm, UEVR camera forward offset: view sat ~40 cm ahead of the shoulders (real ~10)
    items_follow_hands = true,   -- held tools ride on the VR hands (false = game's own hand position)
    aim_method = 2,              -- UEVR: 1 = head, 2 = right controller (aim + hook gun follow the hand)
    movement_orientation = 1,    -- UEVR: 0 = game aim, 1 = head (walking follows where you look)
    camera_up = 0,         -- cm, UEVR camera up offset (profile had 34: view + hands sat ~32 cm above the body)
}
