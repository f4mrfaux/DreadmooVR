-- DreadmoorVR arms tuning. Edited live: the bridge reloads this file every second, no restart.
-- Rotations are degrees in the controller's frame (p = pitch, y = yaw, r = roll).
return {
    left_rot = { p = -4, y = -3, r = 177 },
    right_rot = { p = 4, y = -177, r = -3 },
    elbow_out = 5,        -- cm outward from the body
    elbow_down = 70,       -- cm down
    arm_length = 50.7,     -- cm, shoulder to hand (measured)
    shoulder_follow = 0.5,        -- capped Lua follow for out-of-reach hands
    shoulder_follow_max = 12,     -- cm per shoulder; prevent the old unbounded lift
    shoulder_widen = 8,    -- cm each shoulder moves outward (you are wider than the character)
    shoulder_swing = 0.3,  -- 0..1 of the forward shoulder turn when reaching (1 = full UBIK)
    grip_back = 8,         -- cm from the controller grip back to your wrist
    camera_forward = -12,  -- cm, recent harness measured eye 2 cm behind shoulders; move 12 cm forward
    item_rot = { p = 0, y = 90, r = 0 },   -- held tools turned in the hand (deg); yaw 90 picked from a live sweep (18:39)
    level_torso = true,          -- the game's torso and head ignore look pitch (keeps the view out of the face)
    items_follow_hands = true,   -- held tools ride on the VR hands (false = game's own hand position)
    aim_method = 2,              -- UEVR: 1 = head, 2 = right controller (aim + hook gun follow the hand)
    movement_orientation = 1,    -- UEVR: 0 = game aim, 1 = head (walking follows where you look)
    camera_up = 0,         -- cm, UEVR camera up offset (profile had 34: view + hands sat ~32 cm above the body)
    -- M3 gestures (m3_gestures.lua). Distances in metres, SteamVR space, gun hand's frame
    -- (x right, y up, z back). The crank only presses while the hook is out.
    gestures = {
        enabled = true,
        crank_offset = { x = -0.06, y = 0.0, z = 0.04 },  -- crank point beside the gun
        crank_r_min = 0.04, crank_r_max = 0.25,           -- left hand distance from the crank axis
        crank_min_deg_s = 180, crank_step_deg = 90,       -- one reel press per 90 degrees turned
        swing_min_m_s = 2.0, swing_frames = 3, swing_cooldown_s = 0.4,
    },
}
