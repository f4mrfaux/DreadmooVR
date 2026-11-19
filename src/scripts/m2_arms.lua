-- M2 arms: spawns BP_VRArms from the mod pak, binds its hand targets to the Frame controllers
-- through UEVR's UObjectHook, attaches its Body to the walking character's mesh (so ABP_VRArms
-- copies the game's pose), and hides the game body's arms and head. Every engine call is listed in
-- docs/research/validated-engine-calls.md.
local ARMS = "/Game/DreadmoorVR/BP_VRArms.BP_VRArms_C"
local SNAP_TO_TARGET = 2   -- EAttachmentRule::SnapToTarget (EngineTypes.h)
local PBO_NONE = 0         -- EPhysBodyOp::PBO_None (SkinnedMeshComponent.h:85)
local HAND_LEFT, HAND_RIGHT = 0, 1  -- UEVR MotionControllerState hand index (UObjectHook.cpp)
local GAME_BONES_TO_HIDE = { "upperarm_l", "upperarm_r", "neck_01" }

local function log(msg)
    pcall(function() uevr.params.functions.log_info("[DreadmoorVR M2] " .. msg) end)
end

local function lib_dir()
    if package and package.path then
        for entry in package.path:gmatch("[^;]+") do
            local base = entry:match("^(.-[/\\]scripts)[/\\]%?%.lua$")
            if base then return base .. "\\lib\\" end
        end
    end
    return ".\\scripts\\lib\\"
end

local loaded = {}
local function load_module(name)
    local chunk, err = loadfile(lib_dir() .. name .. ".lua")
    if not chunk then error("cannot load " .. name .. ": " .. tostring(err)) end
    loaded[name] = chunk(loaded)
    return loaded[name]
end

local gameapi = load_module("gameapi")
local modes = load_module("modes")
local armsloader = load_module("armsloader")
load_module("m1flow")
local flow = load_module("armsflow").new(loaded)
local armstats = load_module("armstats")
local tuning = load_module("tuning")
local wristfit = load_module("wristfit")
local ubik = load_module("ubik")
local itemfollow = load_module("itemfollow")
local boatcontrols = load_module("boatcontrols").new(
    function(key) return uevr.params.vr.get_mod_value(key) end,
    function(key, value) uevr.params.vr.set_mod_value(key, value); log(key .. "=" .. value .. " (boat transition)") end,
    function(key, reason) log("boat setting " .. key .. " FAILED: " .. reason) end)
local stats = { walking = armstats.new(), boat = armstats.new() }
log("loaded")

local actor = nil
local arms_body_visible_mode = nil
local sample_err_logged = false
local solve_err_logged = false
local boat_solver_active_logged = false
local items_err_logged = false
local torso_err_logged = false

-- Live tuning: <profile>\dreadmoorvr_arms_tuning.lua, reloaded every second, pushed into BP_VRArms
-- float variables (names from tuning.flatten). Bad values fall back to defaults (tuning.merge).
local TUNING_FILE = (lib_dir():gsub("scripts[/\\]lib[/\\]$", "")) .. "dreadmoorvr_arms_tuning.lua"
local last_tuning_check, last_tuning_mode, applied = -1, nil, {}
local fit = { shoulder_widen = 0, shoulder_follow = 0.5, shoulder_follow_max = 12, grip_back = 0,
    items_follow_hands = false, level_torso = false, shoulder_swing = 1 }
local hand_states = {}                               -- UEVR MotionControllerStates, set at spawn
local finger_curls = { L = nil, R = nil }            -- SteamVR skeleton summary, 0=open, 1=curled
local finger_curl_received_at = { L = nil, R = nil }
local FINGER_CURL_STALE_SECONDS = 0.5
local finger_channel_names = {
    { field = "thumb", name = "Thumb" }, { field = "index", name = "Index" },
    { field = "middle", name = "Middle" }, { field = "ring", name = "Ring" },
    { field = "pinky", name = "Pinky" },
}
local finger_smoothed = {
    L = { thumb = 0, index = 0, middle = 0, ring = 0, pinky = 0 },
    R = { thumb = 0, index = 0, middle = 0, ring = 0, pinky = 0 },
}
local finger_anim_error_logged, finger_anim_probe_logged, finger_anim_nil_logged = false, false, false
local finger_anim_class, last_finger_anim_log = "unknown", -math.huge
local boat_hand_anchor_active, boat_hand_anchor_last_log = false, -math.huge
local boat_hand_anchor_degraded = false
local boat_hand_anchor_offsets = {}
local boat_hand_anchor_direct = false
local boat_hand_anchor_saved_transforms = {}
local boat_solver_hand_targets = {}
local boat_hand_anchor_last_valid_world = nil
local boat_body_saved_relative_transform = nil
local boat_alignment_error_last_log = -math.huge
local function apply_tuning(now, mode)
    local previous_mode = last_tuning_mode
    local mode_changed = mode ~= previous_mode
    if now - last_tuning_check < 1.0 and not mode_changed then return end
    last_tuning_check = now
    last_tuning_mode = mode
    local chunk = loadfile(TUNING_FILE, "t", {})
    local ok, user = false, nil
    if chunk then ok, user = pcall(chunk) end
    local merged = tuning.merge(ok and user or nil)
    fit.shoulder_widen = merged.shoulder_widen
    fit.shoulder_follow = merged.shoulder_follow
    fit.shoulder_follow_max = merged.shoulder_follow_max
    fit.items_follow_hands = merged.items_follow_hands
    fit.level_torso = merged.level_torso
    fit.shoulder_swing = merged.shoulder_swing
    fit.item_rot = merged.item_rot
    if merged.grip_back ~= fit.grip_back and hand_states.L ~= nil then
        -- MotionControllerState offset is in the controller's OpenVR frame (UObjectHook.cpp:925,
        -- cm); OpenVR grip forward is -Z, so +Z moves the target back toward the wrist.
        if boat_hand_anchor_active then
            fit.grip_back = merged.grip_back
            log("grip_back=" .. merged.grip_back .. " (restore value; boat hands remain on grip sockets)")
        else
            local ok2, err = pcall(function()
                hand_states.L:set_location_offset(Vector3f.new(0, 0, merged.grip_back))
                hand_states.R:set_location_offset(Vector3f.new(0, 0, merged.grip_back))
            end)
            if ok2 then fit.grip_back = merged.grip_back; log("grip_back=" .. merged.grip_back)
            else log("grip_back FAILED: " .. tostring(err)) end
        end
    end
    -- Eye position relative to the character's shoulders: UEVR's own camera offsets, set live
    -- through the plugin API's set_mod_value (uevr/API.h; Lua binding ScriptContext.cpp:481).
    for key, mod in pairs({ camera_forward = "VR_CameraForwardOffset", camera_up = "VR_CameraUpOffset",
                             aim_method = "VR_AimMethod", movement_orientation = "VR_MovementOrientation" }) do
        local v = key == "camera_forward" and mode == "boat" and merged.boat_camera_forward or merged[key]
        -- Fishing's cast gesture moves the right hand from the ear to forward reach. Keep UEVR's
        -- aim/camera reference on the HMD during that gesture and through fishing QTEs; using the
        -- configured hand-aim mode makes the view follow that arm motion. Leaving fishing restores
        -- the user's configured aim method on the next mode transition.
        if key == "aim_method" and mode == "fishing" then v = 1 end
        local transition_restore = previous_mode == "boat" and mode_changed
            and (key == "aim_method" or key == "movement_orientation")
        local allowed = key == "camera_forward"
            or (not transition_restore and mode ~= "boat" and next(boatcontrols.saved) == nil)
        if allowed and v ~= nil and v ~= fit[key] then
            local ok3, err = pcall(function() uevr.params.vr.set_mod_value(mod, key:find("^camera_") and string.format("%.6f", v) or string.format("%d", v)) end)
            if ok3 then fit[key] = v; log(mod .. "=" .. v) else log(mod .. " FAILED: " .. tostring(err)) end
        end
    end
    local flat = tuning.flatten(merged)
    local changed = {}
    for k, v in pairs(flat) do
        if applied[k] ~= v then
            actor[k] = v
            applied[k] = v
            changed[#changed + 1] = k .. "=" .. v
        end
    end
    if #changed > 0 then table.sort(changed); log("tuning applied: " .. table.concat(changed, " ")) end
end

-- Refinement harness: 1 Hz sample per hand (controller target vs the arms' actual bones), 10 s
-- summary. Read-only; also runs at the first-person helm to validate target-to-joint reach.
-- GetSocketLocation/GetSocketRotation: SceneComponent.h:791/799.
local SAMPLE_S, SUMMARY_S = 1.0, 10.0
local last_sample, last_summary = 0, 0
local function f3(v) return string.format("%.0f,%.0f,%.0f", v.X, v.Y, v.Z) end
local function r3(r) return string.format("%.0f,%.0f,%.0f", r.Pitch, r.Yaw, r.Roll) end

local function arms_ready()
    return actor ~= nil and actor.Body ~= nil and actor.LeftHandTarget ~= nil and actor.RightHandTarget ~= nil
end

-- UBIK solver, every frame: elbow joint targets and clavicle offsets (world) -> BP_VRArms floats
-- read by ABP_VRArms. The shift we applied last frame is subtracted to get rest positions.
local calib = ubik.calibration.new()
local shift = { L = { X = 0, Y = 0, Z = 0 }, R = { X = 0, Y = 0, Z = 0 } }
local last_calib_logged = nil
local function vsub(a, b) return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z } end
local function vadd(a, b) return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z } end
local function vlen(a) return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
local function vdot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end

local function restore_boat_body_alignment()
    if boat_body_saved_relative_transform == nil or actor == nil or actor.Body == nil then return end
    local saved = boat_body_saved_relative_transform
    boat_body_saved_relative_transform = nil
    local ok, err = pcall(function() actor.Body:K2_SetRelativeTransform(saved, false, {}, true) end)
    if ok then log("boat body/camera alignment restored")
    else log("boat body alignment restore FAILED: " .. tostring(err)) end
end

-- The boat camera component sits well forward of the original character pose. Use UEVR's active
-- camera offset to place the copied head 10 cm behind the rendered eye, then translate only the
-- visual body copy. Live headset comparison showed the previous positive helm offset moved the
-- view farther forward; use the opposite sign to pull the helm eye back from the game camera.
local function align_boat_body_to_camera(pawn)
    if boat_body_saved_relative_transform == nil then
        boat_body_saved_relative_transform = actor.Body:GetRelativeTransform()
        if boat_body_saved_relative_transform == nil then error("body relative transform unavailable") end
    end
    local camera = pawn.FirstPersonCamera_GEN_VARIABLE
    if camera == nil then camera = pawn.FirstPersonSpringArm_GEN_VARIABLE end
    if camera == nil then camera = pawn.FirstPersonSpringArm end
    if camera == nil then error("live first-person camera component unavailable") end
    local camera_pos = camera:K2_GetComponentLocation()
    local forward, up = camera:GetForwardVector(), camera:GetUpVector()
    local head = actor.Body:GetSocketLocation("head")
    local function finite_vec(v)
        return v ~= nil and type(v.X) == "number" and v.X == v.X and math.abs(v.X) < 100000
            and type(v.Y) == "number" and v.Y == v.Y and math.abs(v.Y) < 100000
            and type(v.Z) == "number" and v.Z == v.Z and math.abs(v.Z) < 100000
    end
    if not finite_vec(camera_pos) or not finite_vec(forward) or not finite_vec(up) or not finite_vec(head) then
        error("non-finite camera/body transform")
    end
    -- Use the active offset in the observed direction: the previous positive helm value made the
    -- headset view feel farther forward. Keep the head socket 10 cm behind the shifted eye.
    local eye_forward = fit.camera_forward or 0
    local head_target = vadd(vadd(camera_pos,
        { X = forward.X * (eye_forward - 10), Y = forward.Y * (eye_forward - 10),
          Z = forward.Z * (eye_forward - 10) }),
        { X = up.X * 5, Y = up.Y * 5, Z = up.Z * 5 })
    local delta = vsub(head_target, head)
    local distance = vlen(delta)
    if distance > 150 then error(string.format("camera/body separation %.1f cm exceeds safe helm correction", distance)) end
    if distance > 1.0 then
        local root = actor.Body:K2_GetComponentLocation()
        root.X, root.Y, root.Z = root.X + delta.X, root.Y + delta.Y, root.Z + delta.Z
        actor.Body:K2_SetWorldLocation(root, false, {}, true)
        if distance > 20 then log(string.format("boat visual rig aligned to camera/head socket (%.1f cm correction)", distance)) end
    end
end

local function solve_arms(pawn, mode)
    if not arms_ready() then return end
    local yaw = math.rad(pawn:K2_GetActorRotation().Yaw)
    local F = { X = math.cos(yaw), Y = math.sin(yaw), Z = 0 }
    local Rv = { X = -math.sin(yaw), Y = math.cos(yaw), Z = 0 }
    local UP = { X = 0, Y = 0, Z = 1 }
    local body = actor.Body
    local rest, clav, hands = {}, {}, {}
    for _, h in ipairs({ { "L", "_l", actor.LeftHandTarget }, { "R", "_r", actor.RightHandTarget } }) do
        local side, sfx, target = h[1], h[2], h[3]
        rest[side] = vsub(body:GetSocketLocation("upperarm" .. sfx), shift[side])
        clav[side] = vsub(body:GetSocketLocation("clavicle" .. sfx), shift[side])
        hands[side] = boat_solver_hand_targets[side] or target:K2_GetComponentLocation()
    end
    calib:add(hands.L, hands.R, vlen(vsub(rest.L, rest.R)))
    local upper = vlen(vsub(body:GetSocketLocation("upperarm_l"), body:GetSocketLocation("lowerarm_l")))
    local lower = vlen(vsub(body:GetSocketLocation("lowerarm_l"), body:GetSocketLocation("hand_l")))
    local arm_len = math.max(calib:arm_length() or 0, upper + lower)  -- calibration only lengthens
    for _, side in ipairs({ "L", "R" }) do
        local outward = side == "L" and { X = -Rv.X, Y = -Rv.Y, Z = 0 } or Rv
        local rel = vsub(hands[side], rest[side])
        local cyaw, croll = ubik.clavicle_angles(vdot(rel, F), vdot(rel, UP), arm_len)
        cyaw = cyaw * fit.shoulder_swing   -- full UBIK swing read as a V from above (Bob, 18:02)
        local shoulder_shift = vadd(ubik.shoulder_shift({ clavicle = clav[side], rest = rest[side], yaw = cyaw, roll = croll, forward = F, up = UP }),
            { X = outward.X * fit.shoulder_widen, Y = outward.Y * fit.shoulder_widen, Z = 0 })
        local shoulder = vadd(rest[side], shoulder_shift)
        local follow_influence = fit.shoulder_follow
        local follow_cap = fit.shoulder_follow_max
        if mode == "boat" then
            -- The eye has moved back from the game's forward-mounted helm camera, while the
            -- authored grips remain at the dashboard. Let the clavicles reach toward those grips,
            -- bounded per shoulder, without dragging the torso into the dash.
            follow_influence, follow_cap = 1.0, 30
        end
        local follow = ubik.shoulder_follow_shift(shoulder, hands[side], arm_len,
            follow_influence, follow_cap)
        shoulder_shift = vadd(shoulder_shift, follow)
        shift[side] = shoulder_shift  -- subtract the complete offset next frame to prevent drift
        shoulder = vadd(shoulder, follow)
        local swivel = ubik.base_swivel(vdot(vsub(hands[side], shoulder), outward), arm_len)
        local e = ubik.elbow({ shoulder = shoulder, hand = hands[side], upper = upper, lower = lower, swivel = swivel, outward = outward })
        actor[side .. "ElbowX"], actor[side .. "ElbowY"], actor[side .. "ElbowZ"] = e.X, e.Y, e.Z
        local sh = shift[side]
        actor[side .. "ShoulderX"], actor[side .. "ShoulderY"], actor[side .. "ShoulderZ"] = sh.X, sh.Y, sh.Z
    end
    local a = calib:arm_length()
    if a and a > upper + lower and (last_calib_logged == nil or math.abs(a - last_calib_logged) >= 1) then
        last_calib_logged = a
        log(string.format("calibration: player arm %.1f cm (character %.1f)", a, upper + lower))
    end
end

-- Rendered eye position (world), from UEVR's post stereo-view callback (ScriptContext.cpp:157,
-- :1367; UE5 passes Vector3d). Averaged over both eyes. Read-only.
local place_items          -- defined with the held-item code below; called per frame from here
local pin_boat_hands_after_hook -- UObjectHook updates controller targets before this callback.
local eye = { X = 0, Y = 0, Z = 0, n = 0 }
uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function(_, view_index, _, position)
    if view_index == 0 then
        if place_items then place_items() end
        eye.X, eye.Y, eye.Z, eye.n = position.x, position.y, position.z, 1
    elseif eye.n == 1 then eye.X, eye.Y, eye.Z = (eye.X + position.x) / 2, (eye.Y + position.y) / 2, (eye.Z + position.z) / 2; eye.n = 2 end
    -- UObjectHook writes motion-controller component transforms during its pre-stereo callback.
    -- Pin socket-fallback targets after that update, so the rendered hands stay on the controls.
    if view_index == 0 and pin_boat_hands_after_hook then pin_boat_hands_after_hook() end
end)

-- Raw SteamVR device position in metres (tracking space), uevr.params.vr.get_pose
-- (ScriptContext.cpp:456, PluginLoader get_pose = VR::get_transform).
local function raw_pos(index)
    local p, q = UEVR_Vector3f.new(), UEVR_Quaternionf.new()
    uevr.params.vr.get_pose(index, p, q)
    return { X = p.x, Y = p.y, Z = p.z }
end

local function sample_arms(pawn, now, mode)
    if not arms_ready() then return end
    if now - last_sample < SAMPLE_S then return end
    last_sample = now
    -- Use the copied body for sampled joints in every mode. In the helm the local pawn is the
    -- boat, whose Mesh is a boat component and has no character head socket.
    local head = actor.Body:GetSocketLocation("head")
    local mode_stats = stats[mode] or stats.walking
    for _, h in ipairs({ { "L", actor.LeftHandTarget, "_l" }, { "R", actor.RightHandTarget, "_r" } }) do
        local side, target, sfx = h[1], h[2], h[3]
        local solver_target = boat_solver_hand_targets[side] or target:K2_GetComponentLocation()
        local s = {
            target = solver_target, target_rot = target:K2_GetComponentRotation(),
            hand = actor.Body:GetSocketLocation("hand" .. sfx), hand_rot = actor.Body:GetSocketRotation("hand" .. sfx),
            elbow = actor.Body:GetSocketLocation("lowerarm" .. sfx), shoulder = actor.Body:GetSocketLocation("upperarm" .. sfx),
        }
        local m = armstats.sample(s)
        mode_stats:add(side, m)
        -- Wrist fit: finger bones in the controller frame -> suggested hand rotation offset.
        local pre = side == "L" and "Left" or "Right"
        local okw, sug = pcall(wristfit.suggest, {
            F = target:GetForwardVector(), R = target:GetRightVector(), U = target:GetUpVector(),
            hand = s.hand, middle = actor.Body:GetSocketLocation("middle_01" .. sfx),
            index = actor.Body:GetSocketLocation("index_01" .. sfx), pinky = actor.Body:GetSocketLocation("pinky_01" .. sfx),
            current = { p = applied[pre .. "RotP"] or 0, y = applied[pre .. "RotY"] or 0, r = applied[pre .. "RotR"] or 0 } })
        if okw then log(string.format("wrist %s suggest p=%.0f y=%.0f r=%.0f", side, sug.p, sug.y, sug.r)) end
        log(string.format("arm %s target=%s hand=%s elbow=%s shoulder=%s head=%s reach_err=%.1f to_target=%.1f arm_len=%.1f d_rot=%.0f,%.0f,%.0f target_rot=%s hand_rot=%s",
            side, f3(s.target), f3(s.hand), f3(s.elbow), f3(s.shoulder), f3(head), m.reach_err, m.shoulder_to_target, m.arm_len,
            m.d_pitch, m.d_yaw, m.d_roll, r3(s.target_rot), r3(s.hand_rot)))
    end
    -- Body fit: where the eyes sit relative to the character's shoulders (cm, body frame), and
    -- SteamVR's raw hand span (m) against the in-game target span (cm) = effective world scale.
    pcall(function()
        local yaw = math.rad(pawn:K2_GetActorRotation().Yaw)
        local F = { X = math.cos(yaw), Y = math.sin(yaw), Z = 0 }
        local sl, sr = actor.Body:GetSocketLocation("upperarm_l"), actor.Body:GetSocketLocation("upperarm_r")
        local mid = { X = (sl.X + sr.X) / 2, Y = (sl.Y + sr.Y) / 2, Z = (sl.Z + sr.Z) / 2 }
        local d = { X = eye.X - mid.X, Y = eye.Y - mid.Y, Z = eye.Z - mid.Z }
        local vr = uevr.params.vr
        local rl, rr, rh = raw_pos(vr.get_left_controller_index()), raw_pos(vr.get_right_controller_index()), raw_pos(vr.get_hmd_index())
        local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
        local tl, tr = actor.LeftHandTarget:K2_GetComponentLocation(), actor.RightHandTarget:K2_GetComponentLocation()
        local raw_span, ue_span = dist(rl, rr), dist(tl, tr)
        log(string.format("fit eye_ahead=%.1f eye_above=%.1f shoulder_w=%.1f raw_span=%.3fm ue_span=%.1f scale=%.2f raw_eye_h=%.2fm raw_handL_below_eye=%.2fm raw_handR_below_eye=%.2fm",
            d.X * F.X + d.Y * F.Y, d.Z, dist(sl, sr), raw_span, ue_span, raw_span > 0.05 and ue_span / (raw_span * 100) or 0,
            rh.Y, rh.Y - rl.Y, rh.Y - rr.Y))
        -- Torso levelling check: with level_torso on, spine pitch should stop following ctrl pitch.
        -- The copied body supplies the character spine socket even when pawn is the boat.
        -- Pawn.Controller Pawn.h:198, GetControlRotation Controller.h:159.
        log(string.format("torso ctrl_pitch=%.0f spine_pitch=%.0f level_torso=%s",
            pawn.Controller:GetControlRotation().Pitch, actor.Body:GetSocketRotation("spine_05").Pitch, tostring(fit.level_torso)))
    end)
    if now - last_summary >= SUMMARY_S then
        last_summary = now
        log("arms summary " .. tostring(mode) .. " " .. mode_stats:summary("L") .. " | " .. mode_stats:summary("R"))
    end
end

-- Held items (game chain: docs/research/2026-11-17-held-items.md). The game attaches tools to
-- CharacterMesh0 at hand sockets, and on unequip finds and destroys them through its own native,
-- non-recursive search. Re-parenting tools onto the VR arms hid them from that search (in game
-- 17:01-17:43: old tools piled up in the hand). So tools stay attached where the game put them,
-- and every frame, after the game's tick and before rendering (stereo view callback), each is
-- placed at the same socket on the VR arms' Body with the game's own grip offset.
-- Calls (UE 5.6, validated): AttachChildren SceneComponent.h:116, GetAttachSocketName :687,
-- GetAttachParent :683, GetRelativeTransform :446, K2_SetRelativeTransform :441,
-- K2_SetWorldTransform :578, GetSocketTransform :782, GetSocketBoneName SkinnedMeshComponent.h:1094,
-- GetParentBone :1181, KismetMathLibrary.ComposeTransforms KismetMathLibrary.h:3960.
local RTS_WORLD = 0       -- ERelativeTransformSpace::RTS_World
local moved = {}          -- component address -> { comp, socket, rel (game grip offset), side, name }
local seen_children = {}  -- component address -> true (one discovery log line each)
local last_item_scan = -1
local kml = nil           -- KismetMathLibrary default object
local function name_str(n)
    if type(n) == "string" then return n end
    local ok, v = pcall(function() return n:to_string() end)
    return ok and v or tostring(n)
end
local function addr(o) local ok, a = pcall(function() return o:get_address() end); return ok and a or tostring(o) end
local function full_name(o) local ok, v = pcall(function() return o:get_full_name() end); return ok and v or tostring(o) end

-- Put every followed tool back on the game's hand (its original offset) and forget it.
local function restore_items()
    for _, m in pairs(moved) do pcall(function() m.comp:K2_SetRelativeTransform(m.rel, false, {}, true) end) end
    if next(moved) then log("held items back on the game's hand") end
    moved = {}
end

-- 4 Hz: which tools are in a hand. Tools the game removed (or moved off its mesh) are forgotten.
local function follow_items(pawn, now)
    if now - last_item_scan < 0.25 then return end
    last_item_scan = now
    local mesh = pawn.Mesh
    local mesh_addr, body_addr = addr(mesh), addr(actor.Body)
    for a, m in pairs(moved) do
        local ok, parent = pcall(function() return m.comp:GetAttachParent() end)
        if not ok or parent == nil or addr(parent) ~= mesh_addr then moved[a] = nil; log("held item gone: " .. m.name) end
    end
    if not fit.items_follow_hands then
        if next(moved) then restore_items() end
        return
    end
    local children, comps = {}, {}
    for _, comp in ipairs(mesh.AttachChildren or {}) do
        local a = addr(comp)
        if comp ~= nil and a ~= body_addr and moved[a] == nil then
            local ok, socket, bone = pcall(function()
                local sk = name_str(comp:GetAttachSocketName())
                return sk, sk ~= "None" and name_str(mesh:GetSocketBoneName(sk)) or "None"
            end)
            if not seen_children[a] then
                seen_children[a] = true
                log(ok and string.format("attached to game mesh: %s socket=%s bone=%s", full_name(comp), socket, bone)
                    or ("attached to game mesh: " .. full_name(comp) .. " unreadable: " .. tostring(socket)))
            end
            if ok then
                comps[#comps + 1] = comp
                children[#children + 1] = { id = #comps, socket = socket, bone = bone }
            end
        end
    end
    local plan = itemfollow.plan(children, function(b) return name_str(mesh:GetParentBone(b)) end)
    for _, m in ipairs(plan) do
        local comp = comps[m.id]
        local ok, rel = pcall(function() return comp:GetRelativeTransform() end)
        if ok and rel ~= nil then
            moved[addr(comp)] = { comp = comp, socket = m.socket, rel = rel, side = m.side, name = full_name(comp) }
            log(string.format("held item -> VR hand %s: %s socket=%s", m.side, full_name(comp), m.socket))
        else
            log("held item FAILED: " .. full_name(comp) .. ": " .. tostring(rel))
        end
    end
end

-- Every frame, before rendering: each followed tool goes to the VR hand.
local place_err_logged, placing = false, false
local item_off, item_off_key = nil, nil   -- MakeTransform of fit.item_rot (KismetMathLibrary.h:3930)
function place_items()
    if not placing or actor == nil or next(moved) == nil then return end
    if kml == nil then
        local c = uevr.api:find_uobject("Class /Script/Engine.KismetMathLibrary")
        kml = c and c:get_class_default_object()
        if kml == nil then return end
    end
    -- Our hand bone is turned to fit the controller, unlike the game's, so tools can sit turned in
    -- the hand (in game 18:20 the gun was about 180 off). item_rot turns them about the grip.
    local r = fit.item_rot or { p = 0, y = 0, r = 0 }
    local key = r.p .. "," .. r.y .. "," .. r.r
    if key ~= item_off_key then
        item_off = kml:MakeTransform({ X = 0, Y = 0, Z = 0 }, { Pitch = r.p, Yaw = r.y, Roll = r.r }, { X = 1, Y = 1, Z = 1 })
        item_off_key = key
        log(string.format("held item local rotation offset p=%s y=%s r=%s", r.p, r.y, r.r))
    end
    local body = actor.Body
    for a, m in pairs(moved) do
        local ok, err = pcall(function()
            local sock = body:GetSocketTransform(m.socket, RTS_WORLD)
            -- ComposeTransforms(delta, local_to_world) applies the delta in local space (UE 5.6
            -- KismetMathLibrary.h:3955-3956). Put item_rot before the captured grip-to-world
            -- transform so it turns the tool around its own grip, not around the hand socket.
            local grip_to_world = kml:ComposeTransforms(m.rel, sock)
            m.comp:K2_SetWorldTransform(kml:ComposeTransforms(item_off, grip_to_world), false, {}, true)
        end)
        if not ok then
            moved[a] = nil
            if not place_err_logged then place_err_logged = true; log("held item place FAILED: " .. tostring(err)) end
        end
    end
end

-- Level torso. The game's ABP_V03 copies control rotation into ControlRotaton every update
-- (bp-dumps/ABP_V03.txt L0356), and its Control Rig CR_AimingRotation bends spine_05 by Pitch.
-- The camera rides the head bone, so with aim on the hand, raising a hand bent the torso and moved
-- the view into the face. After BlueprintUpdateAnimation we zero only that copy's pitch: the real
-- control rotation, which the hook gun and melee aim with, is untouched. That the rig's Pitch pin
-- reads ControlRotaton is likely but unverified (fast-path data); the fit line's spine pitch
-- shows whether it works. UEVR: UFunction:hook_ptr(pre, post) ScriptContext.cpp:805, post gets
-- (fn, obj, locals, result) :1209; a UE5 rotator property is a live Vector3d (x = Pitch),
-- ScriptUtility.cpp:165.
-- The function is taken from the live anim instance's class: in game, find_uobject by path
-- returned nothing (16:33). GetAnimInstance SkeletalMeshComponent.h:1016; UStruct:find_function
-- ScriptContext.cpp:720.
local torso_hooked, last_torso_try, torso_missing_logged = false, -10, false
local function install_torso_hook(pawn, now)
    if torso_hooked or now - last_torso_try < 5 then return end
    last_torso_try = now
    local anim = pawn.Mesh:GetAnimInstance()
    local cls = anim ~= nil and anim:get_class() or nil
    local fn = cls ~= nil and cls:find_function("BlueprintUpdateAnimation") or nil
    if fn == nil then
        if not torso_missing_logged then
            torso_missing_logged = true
            log("torso levelling waiting: no BlueprintUpdateAnimation on " .. (cls and name_str(cls:get_fname()) or "no anim instance"))
        end
        return
    end
    fn:hook_ptr(nil, function(_, obj)
        if not fit.level_torso then return end
        local r = obj.ControlRotaton
        if r ~= nil then r.x = 0 end
    end)
    torso_hooked = true
    log("torso levelling on (" .. name_str(cls:get_fname()) .. ".BlueprintUpdateAnimation post-hook)")
end

local clock = 0

local hidden_on = nil  -- the game mesh whose bones we hid, so they can be restored

local function restore_game_body()
    if hidden_on == nil then return end
    for _, bone in ipairs(GAME_BONES_TO_HIDE) do pcall(function() hidden_on:UnHideBoneByName(bone) end) end
    hidden_on = nil
end

local function attach_and_hide(pawn)
    restore_game_body()
    -- Hide the game body first: if anything below throws (a dead arms actor), the camera is still
    -- not left inside the character's head.
    for _, bone in ipairs(GAME_BONES_TO_HIDE) do pawn.Mesh:HideBoneByName(bone, PBO_NONE) end
    hidden_on = pawn.Mesh
    actor.Body:K2_AttachToComponent(pawn.Mesh, "None", SNAP_TO_TARGET, SNAP_TO_TARGET, SNAP_TO_TARGET, false)
    -- Body is a full copy of the character; its head must go too, or the view sits inside it
    -- (camera_forward pulls the eyes back into the head). Hiding a bone hides its children.
    actor.Body:HideBoneByName("neck_01", PBO_NONE)
    hidden_on = pawn.Mesh
end

local function show_arms_at_boat(pawn)
    if not arms_ready() then return end
    -- Keep Body attached to the diver's skeletal mesh: ABP_VRArms uses
    -- FAnimNode_CopyPoseFromMesh.bUseAttachedParent. The game hides the diver actor for first
    -- person helm view, so explicitly clear the inherited hidden-in-game state on our mesh.
    actor.Body:SetHiddenInGame(false, true)
    actor:SetActorHiddenInGame(false)
    log("VR arms body visible in first-person helm; pose source remains the diver mesh")
end

local function hide_arms_in_third_person_boat()
    if actor == nil then return end
    actor:SetActorHiddenInGame(true)
    log("VR body copy hidden in third-person helm; game seated character remains visible")
end

-- Use hand sockets authored into the shipped control meshes. Rebase each tracked target so its
-- rendered hand stays at the wheel/throttle grip while the real controller continues to drive
-- IA_BoatMove from raw SteamVR pose in M3. The socket transforms themselves rotate with the game
-- controls, giving visual feedback without feeding the rebased pose back into gesture input.
local function restore_boat_hand_anchors()
    if not boat_hand_anchor_active and next(boat_hand_anchor_offsets) == nil
        and next(boat_hand_anchor_saved_transforms) == nil and next(boat_solver_hand_targets) == nil then return end
    -- Reset UObjectHook first, then restore the pre-anchor transforms. With a stale controller
    -- hint the hook may not update these targets, so both operations are required.
    for _, side in ipairs({ "L", "R" }) do
        local state = hand_states[side]
        if state ~= nil then
            pcall(function() state:set_location_offset(Vector3f.new(0, 0, fit.grip_back)) end)
        end
    end
    if boat_hand_anchor_direct then
        for _, side in ipairs({ "L", "R" }) do
            local saved = boat_hand_anchor_saved_transforms[side]
            local target = side == "L" and actor and actor.LeftHandTarget or actor and actor.RightHandTarget
            if saved ~= nil and target ~= nil then
                pcall(function()
                    target:K2_SetWorldLocation(saved.location, false, {}, true)
                    target:K2_SetWorldRotation(saved.rotation, false, {}, true)
                end)
            end
        end
    end
    boat_hand_anchor_offsets = {}
    boat_hand_anchor_saved_transforms = {}
    boat_hand_anchor_active = false
    boat_hand_anchor_degraded = false
    boat_hand_anchor_direct = false
    boat_solver_hand_targets = {}
    boat_hand_anchor_last_valid_world = nil
    log("boat hand grip anchors released")
end

local function boat_hand_anchor_components(pawn)
    local wheel_mount = pawn.BP_ShipSteeringWheel
    if wheel_mount == nil then error("BP_ShipSteeringWheel mount is nil") end
    local wheel_actor = wheel_mount.ChildActor
    if wheel_actor == nil then wheel_actor = wheel_mount:GetChildActor() end
    if wheel_actor == nil then error("steering wheel child actor is not spawned") end
    local wheel = wheel_actor.Small_Boat_Steerwheel
    local throttle = pawn.Throttle_lever
    if wheel == nil then error("steering wheel mesh component is nil") end
    if throttle == nil then error("Throttle_lever mesh component is nil") end
    return wheel, throttle
end

local function anchor_finite(v)
    return v ~= nil and type(v.X) == "number" and v.X == v.X and math.abs(v.X) < 100000
        and type(v.Y) == "number" and v.Y == v.Y and math.abs(v.Y) < 100000
        and type(v.Z) == "number" and v.Z == v.Z and math.abs(v.Z) < 100000
end

local function anchor_world_pos_string(obj, getter)
    local ok, p = pcall(function() return obj[getter](obj) end)
    if ok and anchor_finite(p) then return string.format("(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z) end
    return "unavailable"
end

local function boat_anchor_origins(pawn)
    local pawn_pos = anchor_world_pos_string(pawn, "K2_GetActorLocation")
    local camera_pos = "unavailable"
    local ok, p = pcall(function()
        local camera = pawn.CameraComp
        if camera == nil then camera = pawn.FirstPersonSpringArm end
        if camera == nil then error("boat camera component unavailable") end
        return camera:K2_GetComponentLocation()
    end)
    if ok and anchor_finite(p) then camera_pos = string.format("(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z) end
    return " pawn=" .. pawn_pos .. " camera=" .. camera_pos
end

local boat_spatial_last_log = -math.huge
local function log_boat_spatial_alignment(pawn, wheel, throttle, now)
    if now - boat_spatial_last_log < 1.0 or actor == nil or actor.Body == nil then return end
    boat_spatial_last_log = now
    local ok, err = pcall(function()
        local sl = actor.Body:GetSocketLocation("upperarm_l")
        local sr = actor.Body:GetSocketLocation("upperarm_r")
        local head = actor.Body:GetSocketLocation("head")
        local wl = wheel:GetSocketLocation("LHand_Socket")
        local tr = throttle:GetSocketLocation("RHand")
        local body_root = actor.Body:K2_GetComponentLocation()
        local camera = pawn.FirstPersonCamera_GEN_VARIABLE
        if camera == nil then camera = pawn.FirstPersonSpringArm_GEN_VARIABLE end
        if camera == nil then camera = pawn.FirstPersonSpringArm end
        local camera_pos = camera and camera:K2_GetComponentLocation() or nil
        local yaw = math.rad(pawn:K2_GetActorRotation().Yaw)
        local fx, fy = math.cos(yaw), math.sin(yaw)
        local rx, ry = -fy, fx
        local function midpoint(a, b)
            return { X = (a.X + b.X) * 0.5, Y = (a.Y + b.Y) * 0.5, Z = (a.Z + b.Z) * 0.5 }
        end
        local shoulders, grips = midpoint(sl, sr), midpoint(wl, tr)
        local delta = vsub(grips, shoulders)
        local eye_delta = camera_pos and vsub(camera_pos, head) or nil
        log(string.format("boat spatial alignment body_root=%s shoulders=%s grips=%s grip_delta_actor=(%.1f,%.1f,%.1f) head=%s camera=%s camera_minus_head=%s boat_yaw=%.1f",
            f3(body_root), f3(shoulders), f3(grips), delta.X * fx + delta.Y * fy,
            delta.X * rx + delta.Y * ry, delta.Z, f3(head), camera_pos and f3(camera_pos) or "unavailable",
            eye_delta and f3(eye_delta) or "unavailable", math.deg(yaw)))
    end)
    if not ok then log("boat spatial alignment sample FAILED: " .. tostring(err)) end
end

local function calculate_hand_socket_offset(side, target, component, socket)
    if hand_states[side] == nil then error("motion controller state " .. side .. " is nil") end
    local anchor = component:GetSocketLocation(socket)
    local hand = target:K2_GetComponentLocation()
    local forward, right, up = target:GetForwardVector(), target:GetRightVector(), target:GetUpVector()
    if not anchor_finite(anchor) or not anchor_finite(hand) or not anchor_finite(forward)
        or not anchor_finite(right) or not anchor_finite(up) then
        error("non-finite socket, target, or controller basis")
    end
    -- UObjectHook replaces MotionControllerState.location_offset, then reapplies that saved
    -- controller-local vector through this frame's adjusted controller rotation before our Lua
    -- tick. Remove that current-frame displacement to recover the raw tracked target. Using the
    -- previous frame's world displacement here is wrong when the wrist rotates: UEVR has already
    -- rotated the local offset into the new basis, leaving a residual that makes the hand drift.
    local previous = boat_hand_anchor_offsets[side] or { x = 0, y = 0, z = fit.grip_back }
    local applied_world = vadd(vadd(
        { X = right.X * previous.x, Y = right.Y * previous.x, Z = right.Z * previous.x },
        { X = up.X * previous.y, Y = up.Y * previous.y, Z = up.Z * previous.y }),
        { X = -forward.X * previous.z, Y = -forward.Y * previous.z, Z = -forward.Z * previous.z })
    local raw_hand = vsub(hand, applied_world)
    local delta = vsub(anchor, raw_hand)
    local offset = Vector3f.new(vdot(delta, right), vdot(delta, up), -vdot(delta, forward))
    -- These offsets are in the controller's local OpenVR frame, but the socket and hand target
    -- are world-space. The recording showed controller and boat origins separated by tens of
    -- thousands of centimeters. Never write such a correction into UObjectHook; switch to the
    -- authored socket pose and feed that same pose directly to the arm solver.
    if offset.x ~= offset.x or offset.y ~= offset.y or offset.z ~= offset.z
        or math.abs(offset.x) > 150 or math.abs(offset.y) > 150 or math.abs(offset.z) > 150 then
        error(string.format("controller/boat origins disagree; correction exceeds 150 cm (%.1f,%.1f,%.1f); hand=(%.1f,%.1f,%.1f) socket=(%.1f,%.1f,%.1f)",
            offset.x, offset.y, offset.z, hand.X, hand.Y, hand.Z, anchor.X, anchor.Y, anchor.Z))
    end
    return offset
end

local function set_boat_hand_anchor_locations(left_component, right_component)
    local left_socket = left_component:GetSocketLocation("LHand_Socket")
    local right_socket = right_component:GetSocketLocation("RHand")
    local left_rotation = left_component:GetSocketRotation("LHand_Socket")
    local right_rotation = right_component:GetSocketRotation("RHand")
    if anchor_finite(left_socket) and anchor_finite(right_socket)
        and left_rotation ~= nil and right_rotation ~= nil then
        boat_hand_anchor_last_valid_world = {
            left = left_socket, right = right_socket,
            left_rotation = left_rotation, right_rotation = right_rotation,
        }
        if boat_hand_anchor_degraded then
            boat_hand_anchor_degraded = false
            log("boat hand grip anchors recovered")
        end
    elseif boat_hand_anchor_last_valid_world ~= nil then
        -- UObjectHook can move targets again before this callback. For a transient invalid socket
        -- sample, keep both rendered hands on the last valid authored grip pair.
        local saved = boat_hand_anchor_last_valid_world
        left_socket, right_socket = saved.left, saved.right
        left_rotation, right_rotation = saved.left_rotation, saved.right_rotation
        if not boat_hand_anchor_degraded then
            boat_hand_anchor_degraded = true
            log("boat hand grip socket sample invalid; retaining last valid pair")
        end
    else
        error("invalid boat grip socket transform; no cached valid pair")
    end
    -- Steam Frame pose tracking can remain live while UEVR reports controllers inactive, or its
    -- controller targets can use a world origin that differs from the boat even when the hint is
    -- active. In either case the solver sees stale/incompatible target positions. Pin the rendered
    -- targets to authored sockets; M3 reads raw SteamVR poses independently, so this visual-only
    -- correction does not feed back into steering or throttle input.
    actor.LeftHandTarget:K2_SetWorldLocation(left_socket, false, {}, true)
    actor.LeftHandTarget:K2_SetWorldRotation(left_rotation, false, {}, true)
    actor.RightHandTarget:K2_SetWorldLocation(right_socket, false, {}, true)
    actor.RightHandTarget:K2_SetWorldRotation(right_rotation, false, {}, true)
end

pin_boat_hands_after_hook = function()
    if not boat_hand_anchor_direct or not boat_hand_anchor_active or actor == nil then return end
    local pawn = gameapi.local_pawn()
    if pawn == nil then return end
    local ok_camera, first_person = pcall(function() return pawn.bFirstPersonCameraEnabled end)
    if not ok_camera or first_person ~= true then return end
    local ok, wheel, throttle = pcall(boat_hand_anchor_components, pawn)
    if not ok then
        if clock - boat_hand_anchor_last_log >= 2 then
            boat_hand_anchor_last_log = clock
            log("boat hand post-stereo socket lookup FAILED: " .. tostring(wheel))
        end
        return
    end
    local ok_pin, pin_error = pcall(set_boat_hand_anchor_locations, wheel, throttle)
    if not ok_pin and clock - boat_hand_anchor_last_log >= 2 then
        boat_hand_anchor_last_log = clock
        log("boat hand post-stereo socket pin FAILED: " .. tostring(pin_error))
    elseif ok_pin and clock - boat_hand_anchor_last_log >= 2 then
        boat_hand_anchor_last_log = clock
        log("boat hand post-stereo sockets pinned: L=" .. anchor_world_pos_string(actor.LeftHandTarget, "K2_GetComponentLocation")
            .. " R=" .. anchor_world_pos_string(actor.RightHandTarget, "K2_GetComponentLocation"))
    end
end

local function save_boat_hand_anchor_origins()
    local saved = {}
    for _, side in ipairs({ "L", "R" }) do
        local target = side == "L" and actor.LeftHandTarget or actor.RightHandTarget
        local ok_location, location = pcall(function() return target:K2_GetComponentLocation() end)
        local ok_rotation, rotation = pcall(function() return target:K2_GetComponentRotation() end)
        if ok_location and anchor_finite(location) and ok_rotation and rotation ~= nil then
            saved[side] = { location = location, rotation = rotation }
        else
            -- UEVR can expose a finite stale position with no valid rotation. Do not let an
            -- optional restore snapshot block pinning both visual hands to valid boat sockets.
            log("pre-anchor transform unavailable for " .. side .. "; controller hook will restore it on helm exit")
        end
    end
    boat_hand_anchor_saved_transforms = saved
end

local function activate_direct_boat_hand_anchors(wheel, throttle, now, reason)
    -- Validate both authored sockets before changing UEVR offsets. If either socket itself is
    -- invalid, retain the last valid pair and let the existing degraded-path handling report it.
    local ok_sockets, socket_error = pcall(function()
        local left = wheel:GetSocketLocation("LHand_Socket")
        local right = throttle:GetSocketLocation("RHand")
        local left_rotation = wheel:GetSocketRotation("LHand_Socket")
        local right_rotation = throttle:GetSocketRotation("RHand")
        if not anchor_finite(left) or not anchor_finite(right)
            or left_rotation == nil or right_rotation == nil then
            error("invalid boat grip socket transform")
        end
    end)
    if not ok_sockets then return false, socket_error end

    if not boat_hand_anchor_direct then
        local ok_save, save_error = pcall(save_boat_hand_anchor_origins)
        if not ok_save then return false, save_error end
        -- Clear any stale world displacement before pinning the visual targets. Gesture input
        -- reads the native SteamVR poses separately, so this only changes the rendered arms.
        for _, side in ipairs({ "L", "R" }) do
            local state = hand_states[side]
            if state ~= nil then pcall(function()
                state:set_location_offset(Vector3f.new(0, 0, fit.grip_back))
            end) end
        end
        boat_hand_anchor_offsets = {}
    end

    -- Do not write targets here: UObjectHook runs later in the frame and overwrites these
    -- transforms while its controller hint is true. The post-stereo callback pins them instead.
    boat_hand_anchor_direct = true
    boat_hand_anchor_degraded = false
    if not boat_hand_anchor_active then
        boat_hand_anchor_active = true
        log("boat hand grip anchors active: left=Small_Boat_Steerwheel.LHand_Socket right=Throttle_lever.RHand (" .. reason .. ")")
    end
    if now - boat_hand_anchor_last_log >= 2 then
        boat_hand_anchor_last_log = now
        log("boat hand direct socket fallback active: " .. reason)
    end
    return true
end

local function update_boat_hand_anchors(pawn, now)
    local ok_camera, first_person = pcall(function() return pawn.bFirstPersonCameraEnabled end)
    if not ok_camera or first_person ~= true then
        restore_boat_hand_anchors()
        restore_boat_body_alignment()
        return
    end
    if not arms_ready() then return end
    local ok, wheel, throttle = pcall(boat_hand_anchor_components, pawn)
    if not ok then
        restore_boat_hand_anchors()
        if now - boat_hand_anchor_last_log >= 2 then
            boat_hand_anchor_last_log = now
            log("boat hand grip anchor lookup FAILED: " .. tostring(wheel))
        end
        return
    end
    local ok_targets, left_goal, right_goal = pcall(function()
        return wheel:GetSocketLocation("LHand_Socket"), throttle:GetSocketLocation("RHand")
    end)
    if not ok_targets or not anchor_finite(left_goal) or not anchor_finite(right_goal) then
        error("authored boat hand goal unavailable: " .. tostring(left_goal))
    end
    boat_solver_hand_targets = { L = left_goal, R = right_goal }
    local ok_align, align_error = pcall(align_boat_body_to_camera, pawn)
    if not ok_align and now - boat_alignment_error_last_log >= 2 then
        boat_alignment_error_last_log = now
        log("boat body/camera alignment FAILED: " .. tostring(align_error))
    end
    log_boat_spatial_alignment(pawn, wheel, throttle, now)
    -- Once a direct fallback is needed, keep it for the full helm session. Switching back and
    -- forth between controller-local offsets and socket placement can make the hands jump when
    -- the game camera and SteamVR pose use different world origins.
    if boat_hand_anchor_direct then
        return
    end
    local ok_tracking, using_controllers = pcall(uevr.params.vr.is_using_controllers)
    if ok_tracking and using_controllers == false then
        local ok_direct, direct_error = activate_direct_boat_hand_anchors(
            wheel, throttle, now, "UEVR inactive-controller fallback")
        if not ok_direct then
            if now - boat_hand_anchor_last_log >= 2 then
                boat_hand_anchor_last_log = now
                log("boat hand direct socket anchor FAILED: " .. tostring(direct_error))
            end
            return
        end
        return
    end
    -- Calculate the pair before applying either controller offset. A transient bad socket or a
    -- controller target outside the shared world frame must not reset one/both hands to the
    -- walking offset and then retry from scratch on the next frame (the live failure mode).
    local ok_left, left_offset = pcall(calculate_hand_socket_offset, "L", actor.LeftHandTarget, wheel, "LHand_Socket")
    local ok_right, right_offset = pcall(calculate_hand_socket_offset, "R", actor.RightHandTarget, throttle, "RHand")
    if not ok_left or not ok_right then
        -- The last runtime capture had a live controller hint but stale controller world
        -- coordinates tens of kilometers away from the moving boat. Don't let those values hide
        -- both hands: pin them to valid authored sockets, retaining that mode until helm exit.
        local ok_direct, direct_error = activate_direct_boat_hand_anchors(
            wheel, throttle, now, "invalid controller/world offset fallback")
        if ok_direct then return end
        if not boat_hand_anchor_degraded and boat_hand_anchor_last_log < now then
            log("boat hand grip anchors degraded; direct post-stereo fallback " .. tostring(direct_error))
        end
        boat_hand_anchor_degraded = true
        if now - boat_hand_anchor_last_log >= 2 then
            boat_hand_anchor_last_log = now
            log("boat hand grip socket FAILED: L=" .. tostring(left_offset) .. " R=" .. tostring(right_offset)
                .. boat_anchor_origins(pawn))
        end
        return
    end
    hand_states.L:set_location_offset(left_offset)
    hand_states.R:set_location_offset(right_offset)
    boat_hand_anchor_offsets.L = { x = left_offset.x, y = left_offset.y, z = left_offset.z }
    boat_hand_anchor_offsets.R = { x = right_offset.x, y = right_offset.y, z = right_offset.z }
    if not boat_hand_anchor_active then
        boat_hand_anchor_active = true
        log("boat hand grip anchors active: left=Small_Boat_Steerwheel.LHand_Socket right=Throttle_lever.RHand")
    end
    if boat_hand_anchor_degraded then
        boat_hand_anchor_degraded = false
        log("boat hand grip anchors recovered")
    end
    if now - boat_hand_anchor_last_log >= 1 then
        boat_hand_anchor_last_log = now
        local applied_l = boat_hand_anchor_offsets.L or left_offset
        local applied_r = boat_hand_anchor_offsets.R or right_offset
        log(string.format("boat grip offsets cm: L=(%.1f,%.1f,%.1f) R=(%.1f,%.1f,%.1f)",
            applied_l.x, applied_l.y, applied_l.z, applied_r.x, applied_r.y, applied_r.z))
    end
end

local function spawn(pawn)
    local cls = uevr.api:find_uobject("BlueprintGeneratedClass " .. ARMS)
    if cls == nil then log("spawn FAILED: class not in memory after plugin load"); return false end
    local ok, err = pcall(function()
        actor = armsloader.spawn(cls, pawn:GetTransform())
        if actor == nil then error("spawn returned nil") end
        -- These caches belong to the actor, not the Lua session. Reapply even unchanged tuning.
        applied, last_tuning_check, last_tuning_mode = {}, -math.huge, nil
        shift = { L = { X = 0, Y = 0, Z = 0 }, R = { X = 0, Y = 0, Z = 0 } }
        calib, last_calib_logged = ubik.calibration.new(), nil
        boat_hand_anchor_active, boat_hand_anchor_last_log = false, -math.huge
        boat_hand_anchor_degraded, boat_hand_anchor_offsets = false, {}
        boat_hand_anchor_direct = false
        boat_hand_anchor_saved_transforms = {}
        boat_solver_hand_targets = {}
        boat_hand_anchor_last_valid_world = nil
        boat_body_saved_relative_transform = nil
        attach_and_hide(pawn)
        -- UEVR exposes the hook as the global usertype UEVR_UObjectHook (ScriptContext.cpp:990);
        -- activate() (:991) turns the system on, get_or_add_motion_controller_state (:1028).
        UEVR_UObjectHook.activate()
        local l = UEVR_UObjectHook.get_or_add_motion_controller_state(actor.LeftHandTarget)
        local r = UEVR_UObjectHook.get_or_add_motion_controller_state(actor.RightHandTarget)
        if l == nil or r == nil then error("motion controller state unavailable") end
        l:set_hand(HAND_LEFT); l:set_permanent(true)
        r:set_hand(HAND_RIGHT); r:set_permanent(true)
        hand_states.L, hand_states.R = l, r
        fit.grip_back = 0   -- fresh states have no offset; next tuning check re-applies it
        log("spawned BP_VRArms; hand targets bound to controllers; game arms/head hidden")
    end)
    if not ok then
        log("spawn FAILED: " .. tostring(err))
        restore_game_body()
        if actor ~= nil then pcall(function() actor:K2_DestroyActor() end) end
        actor = nil
    end
    return ok
end

uevr.sdk.callbacks.on_lua_event(function(name, data)
    if name == "dreadmoorvr_class_loaded" then
        log("plugin reply: " .. tostring(data))
        flow:on_reply(data)
        return
    end
    if name ~= "dreadmoorvr_finger_curls" or type(data) ~= "string" then return end
    local side, values = data:match("^([LR])|(.+)$")
    if side == nil then return end
    if values == "inactive" then
        finger_curls[side], finger_curl_received_at[side] = nil, nil
        return
    end
    local a, b, c, d, e = values:match("^([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$")
    a, b, c, d, e = tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e)
    if a and b and c and d and e and a >= 0 and a <= 1 and b >= 0 and b <= 1
        and c >= 0 and c <= 1 and d >= 0 and d <= 1 and e >= 0 and e <= 1 then
        finger_curls[side] = { thumb = a, index = b, middle = c, ring = d, pinky = e }
        finger_curl_received_at[side] = clock
    end
end)

-- Stream each capacitive SteamVR finger curl to the matching AnimInstance property. The
-- AnimGraph's three additive ModifyBone nodes per digit use this 0=open, 1=closed value as Alpha.
-- Smooth the 30 Hz device samples to avoid visible stepping at the headset frame rate.
local function update_finger_animation(delta)
    if actor == nil then return end
    local ok, err = pcall(function()
        local body = actor.Body
        if body == nil then error("BP_VRArms.Body is nil") end
        -- Call through the UObject binding directly. `type(body.GetAnimInstance)` can report a
        -- non-function for reflected methods, and silently skipping here prevented all runtime
        -- AnimInstance diagnostics despite valid SteamVR curl events.
        local anim = body:GetAnimInstance()
        if anim == nil then
            if not finger_anim_nil_logged then
                finger_anim_nil_logged = true
                log("finger AnimInstance unavailable: Body:GetAnimInstance returned nil")
            end
            return
        end
        finger_anim_nil_logged = false
        if not finger_anim_probe_logged then
            finger_anim_probe_logged = true
            local cls_name_ok, cls_name = pcall(function()
                local cls = anim:get_class()
                return cls and name_str(cls:get_fname()) or "unknown"
            end)
            if not cls_name_ok then cls_name = "unavailable: " .. tostring(cls_name) end
            finger_anim_class = tostring(cls_name)
            local probe_ok, probe_err = pcall(function()
                local key = "FingerCurlLThumb"
                local before = anim[key]
                anim[key] = 0.37
                local after = anim[key]
                if type(after) ~= "number" or math.abs(after - 0.37) > 0.001 then
                    error(key .. " readback=" .. tostring(after) .. " (before=" .. tostring(before) .. ")")
                end
            end)
            log("finger AnimInstance=" .. tostring(cls_name) .. " property probe "
                .. (probe_ok and "PASS" or "FAILED: " .. tostring(probe_err)))
        end
        local blend = 1.0 - math.exp(-math.max(0, delta or 0) / 0.045)
        for _, side in ipairs({ "L", "R" }) do
            local sample = finger_curls[side]
            local received_at = finger_curl_received_at[side]
            if received_at == nil or clock - received_at > FINGER_CURL_STALE_SECONDS then sample = nil end
            for _, channel in ipairs(finger_channel_names) do
                local field = channel.field
                local current = finger_smoothed[side][field] or 0
                local target = sample and sample[field] or 0
                current = current + (target - current) * blend
                finger_smoothed[side][field] = current
                anim["FingerCurl" .. side .. channel.name] = current
            end
        end
        if clock - last_finger_anim_log >= 1.0 then
            last_finger_anim_log = clock
            log(string.format("finger animation readback: %s Lindex=%s Rindex=%s",
                finger_anim_class, tostring(anim.FingerCurlLIndex), tostring(anim.FingerCurlRIndex)))
        end
    end)
    if ok then
        finger_anim_error_logged = false
    elseif not finger_anim_error_logged then
        finger_anim_error_logged = true
        log("finger animation update FAILED: " .. tostring(err))
    end
end

local controls_err_logged = false
uevr.sdk.callbacks.on_pre_engine_tick(function(_, delta)
    clock = clock + (delta or 0)
    local pawn = gameapi.local_pawn()
    local mode = pawn and modes.classify(gameapi.class_chain(pawn)) or nil
    -- Independent of the arms lifecycle: this also runs when loading directly at the helm.
    local okc, errc = pcall(boatcontrols.update, boatcontrols, mode)
    if not okc and not controls_err_logged then log("boat controls FAILED: " .. tostring(errc)) end
    controls_err_logged = not okc
    local before = flow.status
    -- Identity by object address: tostring() names the Lua wrapper, which UEVR can replace for
    -- the same pawn (seen in game as false "new pawn" reattaches).
    local action = flow:step(clock, mode, pawn and addr(pawn) or nil)
    if action == "request" then
        log("requesting BP_VRArms from DreadmoorVR.dll (attempt " .. flow.load.requests .. ")")
        pcall(function() uevr.api:dispatch_custom_event("dreadmoorvr_request_class", ARMS) end)
    elseif action == "spawn" then
        flow:spawned(spawn(pawn))
    elseif action == "hide" or action == "show" then
        local ok, err = pcall(function() actor:SetActorHiddenInGame(action == "hide") end)
        log(action .. (ok and "" or (" FAILED: " .. tostring(err))))
    elseif action == "reattach" then
        restore_boat_body_alignment()
        local ok, err = pcall(function() attach_and_hide(pawn); actor:SetActorHiddenInGame(false) end)
        if ok then
            log("reattached to new walking pawn")
        else
            -- The arms actor died with the old pawn (seen in game 2026-11-17). Drop it and let the
            -- flow spawn fresh arms on the next tick.
            log("arms lost with the old pawn (" .. tostring(err) .. "); spawning fresh arms")
            restore_items()
            pcall(function() actor:K2_DestroyActor() end)
            actor, hand_states = nil, {}
            solve_err_logged, items_err_logged, sample_err_logged = false, false, false
            boat_solver_active_logged = false
            flow:lost()
        end
    end
    if actor ~= nil and mode == "boat" then
        local ok_fp, first_person = pcall(function() return pawn.bFirstPersonCameraEnabled end)
        local visibility_mode = ok_fp and first_person == true and "boat_first_person" or "boat_third_person"
        if arms_body_visible_mode ~= visibility_mode then
            local okb, errb
            if visibility_mode == "boat_first_person" then
                okb, errb = pcall(show_arms_at_boat, pawn)
            else
                okb, errb = pcall(hide_arms_in_third_person_boat)
            end
            if not okb then log("boat arms visibility FAILED: " .. tostring(errb))
            else arms_body_visible_mode = visibility_mode end
        end
    elseif mode == "walking" then
        if actor ~= nil and arms_body_visible_mode == "boat_third_person" then
            local okv, errv = pcall(function() actor:SetActorHiddenInGame(false) end)
            if not okv then log("walking arms visibility restore FAILED: " .. tostring(errv)) end
        end
        arms_body_visible_mode = "walking"
    end
    if actor ~= nil then update_finger_animation(delta) end
    if flow.status == "active" and actor ~= nil then
        local okt, errt = pcall(apply_tuning, clock, mode)
        if mode == "walking" and fit.level_torso and not torso_hooked and pawn ~= nil then
            local okh, errh = pcall(install_torso_hook, pawn, clock)
            if not okh and not torso_err_logged then torso_err_logged = true; log("torso hook FAILED: " .. tostring(errh)) end
        end
        if not okt and not sample_err_logged then sample_err_logged = true; log("tuning FAILED: " .. tostring(errt)) end
    end
    if mode == "boat" and actor ~= nil then
        local okh, errh = pcall(update_boat_hand_anchors, pawn, clock)
        if not okh and not sample_err_logged then sample_err_logged = true; log("boat hand grip anchors FAILED: " .. tostring(errh)) end
    else
        restore_boat_hand_anchors()
        restore_boat_body_alignment()
    end
    -- Reflected UEVR methods are callable even when Lua's type() does not report "function".
    -- Do not silently skip helm IK based on that reflection detail: the target components can be
    -- pinned to the sockets while the rendered arms remain at their old body pose. Let pcall on
    -- solve_arms expose a genuinely unavailable/throwing method as an explicit solver failure.
    local boat_arm_solver_available = mode == "boat" and pawn ~= nil
    if flow.status == "active" and actor ~= nil and (mode == "walking" or boat_arm_solver_available) then
        local oks, errs = pcall(solve_arms, pawn, mode)
        if mode == "boat" and oks and not boat_solver_active_logged then
            boat_solver_active_logged = true
            log("boat arm solver active; targets drive evaluated elbow/shoulder pose")
        end
        if not oks and not solve_err_logged then solve_err_logged = true; log("solver FAILED: " .. tostring(errs)) end
        -- The game's first-person helm hides the character mesh. The VR arms remain attached to
        -- that character (which is attached to the boat) and solve against the boat's yaw.
        -- Item following and the harness still run on foot only.
        if mode == "walking" then
            local oki, erri = pcall(follow_items, pawn, clock)
            if not oki and not items_err_logged then items_err_logged = true; log("items FAILED: " .. tostring(erri)) end
        end
        local ok, err = pcall(sample_arms, pawn, clock, mode)
        if not ok and not sample_err_logged then sample_err_logged = true; log("harness FAILED: " .. tostring(err)) end
    end
    placing = flow.status == "active" and actor ~= nil and mode == "walking"
    if mode ~= "walking" and next(moved) then restore_items() end   -- fishing, steering: game owns the hands
    if flow.status ~= before and (flow.status == "fail" or flow.status == "no_reply" or flow.status == "spawn_failed") then
        log("stopped: " .. flow.status .. (flow.reason and (" - " .. flow.reason) or ""))
    end
end)

uevr.sdk.callbacks.on_script_reset(function()
    local ok, err = pcall(boatcontrols.update, boatcontrols, nil)
    if not ok then log("boat controls restore FAILED: " .. tostring(err)) end
    restore_boat_hand_anchors()
    restore_boat_body_alignment()
    restore_items()
    restore_game_body()
    if actor ~= nil then pcall(function() actor:K2_DestroyActor() end) end
    actor = nil
end)
