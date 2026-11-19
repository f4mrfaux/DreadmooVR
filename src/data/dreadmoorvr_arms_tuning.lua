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
    boat_camera_forward = -30, -- cm, pull helm view back from the forward-mounted game camera to clear the dash/compass
    item_rot = { p = 0, y = 15, r = 0 },    -- Claude's final live sweep (2026-11-17); turns the barrel toward the observed hook-shot line
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
        crank_radius_hysteresis_m = 0.025,                -- tolerate small radial tracking jitter after crank acquisition
        crank_min_deg_s = 110, crank_step_deg = 90,       -- slower natural turns; one reel press per 90 degrees
        swing_min_m_s = 2.0, swing_frames = 3, swing_cooldown_s = 0.4,
        guard_enabled = true,
        guard_enter_z = -0.65, guard_exit_z = -0.50,      -- thumb-down hysteresis; lower = more vertical
        guard_front_z = -0.05,                            -- hand must be in front of HMD/body plane
        guard_min_y = -0.65, guard_max_y = 0.10,          -- low, in front of the chest
        guard_max_x = 0.45,                                -- stay near body center
        fishing_fight_deadzone_m = 0.08, fishing_fight_range_m = 0.28,
        fishing_cast_ear_side_m = 0.12,               -- hand must be to the right of the HMD to load a cast
        fishing_cast_release_forward_m = 0.22,         -- forward reach that releases the charged cast
        fishing_cast_load_confirm_s = 0.12,            -- avoid triggering when the hand passes the ear
        fishing_hook_set_rise_m = 0.07,                 -- quick upward travel during QTE.Type.FishingBite
        craft_cursor_span_m = 0.40,                        -- hand travel across full screen
        boat_steer_range_m = 0.22,                         -- left hand travel to full rudder
        boat_steer_deadzone_m = 0.02,                      -- ignore small center noise (2 cm)
        boat_steer_curve = 1.25,                           -- softer center, still reaches full rudder
        boat_steer_smoothing_s = 0.08,                     -- light low-pass smoothing for tracking noise
        boat_throttle_enter_m = 0.05,                       -- small forward hand travel begins incremental acceleration
        boat_throttle_release_m = 0.025,                    -- return to neutral inside this range
        boat_throttle_turnaround_m = 0.08,                  -- cross through neutral to change direction
        boat_throttle_reverse_enter_m = 0.22,               -- deliberate pull toward/behind the hip for reverse
    },
}
