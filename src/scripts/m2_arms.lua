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
local stats = armstats.new()
log("loaded")

local actor = nil
local sample_err_logged = false
local solve_err_logged = false
local items_err_logged = false
local torso_err_logged = false

-- Live tuning: <profile>\dreadmoorvr_arms_tuning.lua, reloaded every second, pushed into BP_VRArms
-- float variables (names from tuning.flatten). Bad values fall back to defaults (tuning.merge).
local TUNING_FILE = (lib_dir():gsub("scripts[/\\]lib[/\\]$", "")) .. "dreadmoorvr_arms_tuning.lua"
local last_tuning_check, applied = -1, {}
local fit = { shoulder_widen = 0, grip_back = 0, items_follow_hands = false, level_torso = false }   -- live body-fit values (tuning.merge)
local hand_states = {}                               -- UEVR MotionControllerStates, set at spawn
local function apply_tuning(now)
    if now - last_tuning_check < 1.0 then return end
    last_tuning_check = now
    local chunk = loadfile(TUNING_FILE, "t", {})
    local ok, user = false, nil
    if chunk then ok, user = pcall(chunk) end
    local merged = tuning.merge(ok and user or nil)
    fit.shoulder_widen = merged.shoulder_widen
    fit.items_follow_hands = merged.items_follow_hands
    fit.level_torso = merged.level_torso
    if merged.grip_back ~= fit.grip_back and hand_states.L ~= nil then
        -- MotionControllerState offset is in the controller's OpenVR frame (UObjectHook.cpp:925,
        -- cm); OpenVR grip forward is -Z, so +Z moves the target back toward the wrist.
        local ok2, err = pcall(function()
            hand_states.L:set_location_offset(Vector3f.new(0, 0, merged.grip_back))
            hand_states.R:set_location_offset(Vector3f.new(0, 0, merged.grip_back))
        end)
        if ok2 then fit.grip_back = merged.grip_back; log("grip_back=" .. merged.grip_back)
        else log("grip_back FAILED: " .. tostring(err)) end
    end
    -- Eye position relative to the character's shoulders: UEVR's own camera offsets, set live
    -- through the plugin API's set_mod_value (uevr/API.h; Lua binding ScriptContext.cpp:481).
    for key, mod in pairs({ camera_forward = "VR_CameraForwardOffset", camera_up = "VR_CameraUpOffset",
                             aim_method = "VR_AimMethod", movement_orientation = "VR_MovementOrientation" }) do
        local v = merged[key]
        if v ~= nil and v ~= fit[key] then
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
-- summary. Read-only. GetSocketLocation/GetSocketRotation: SceneComponent.h:791/799.
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

local function solve_arms(pawn)
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
        hands[side] = target:K2_GetComponentLocation()
    end
    calib:add(hands.L, hands.R, vlen(vsub(rest.L, rest.R)))
    local upper = vlen(vsub(body:GetSocketLocation("upperarm_l"), body:GetSocketLocation("lowerarm_l")))
    local lower = vlen(vsub(body:GetSocketLocation("lowerarm_l"), body:GetSocketLocation("hand_l")))
    local arm_len = math.max(calib:arm_length() or 0, upper + lower)  -- calibration only lengthens
    for _, side in ipairs({ "L", "R" }) do
        local outward = side == "L" and { X = -Rv.X, Y = -Rv.Y, Z = 0 } or Rv
        local rel = vsub(hands[side], rest[side])
        local cyaw, croll = ubik.clavicle_angles(vdot(rel, F), vdot(rel, UP), arm_len)
        shift[side] = vadd(ubik.shoulder_shift({ clavicle = clav[side], rest = rest[side], yaw = cyaw, roll = croll, forward = F, up = UP }),
            { X = outward.X * fit.shoulder_widen, Y = outward.Y * fit.shoulder_widen, Z = 0 })
        local shoulder = vadd(rest[side], shift[side])
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
local eye = { X = 0, Y = 0, Z = 0, n = 0 }
uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function(_, view_index, _, position)
    if view_index == 0 then eye.X, eye.Y, eye.Z, eye.n = position.x, position.y, position.z, 1
    elseif eye.n == 1 then eye.X, eye.Y, eye.Z = (eye.X + position.x) / 2, (eye.Y + position.y) / 2, (eye.Z + position.z) / 2; eye.n = 2 end
end)

-- Raw SteamVR device position in metres (tracking space), uevr.params.vr.get_pose
-- (ScriptContext.cpp:456, PluginLoader get_pose = VR::get_transform).
local function raw_pos(index)
    local p, q = UEVR_Vector3f.new(), UEVR_Quaternionf.new()
    uevr.params.vr.get_pose(index, p, q)
    return { X = p.x, Y = p.y, Z = p.z }
end

local function sample_arms(pawn, now)
    if not arms_ready() then return end
    if now - last_sample < SAMPLE_S then return end
    last_sample = now
    local head = pawn.Mesh:GetSocketLocation("head")
    for _, h in ipairs({ { "L", actor.LeftHandTarget, "_l" }, { "R", actor.RightHandTarget, "_r" } }) do
        local side, target, sfx = h[1], h[2], h[3]
        local s = {
            target = target:K2_GetComponentLocation(), target_rot = target:K2_GetComponentRotation(),
            hand = actor.Body:GetSocketLocation("hand" .. sfx), hand_rot = actor.Body:GetSocketRotation("hand" .. sfx),
            elbow = actor.Body:GetSocketLocation("lowerarm" .. sfx), shoulder = actor.Body:GetSocketLocation("upperarm" .. sfx),
        }
        local m = armstats.sample(s)
        stats:add(side, m)
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
        -- Pawn.Controller Pawn.h:198, GetControlRotation Controller.h:159, GetSocketRotation SceneComponent.h:799.
        log(string.format("torso ctrl_pitch=%.0f spine_pitch=%.0f level_torso=%s",
            pawn.Controller:GetControlRotation().Pitch, pawn.Mesh:GetSocketRotation("spine_05").Pitch, tostring(fit.level_torso)))
    end)
    if now - last_summary >= SUMMARY_S then
        last_summary = now
        log("arms summary " .. stats:summary("L") .. " | " .. stats:summary("R"))
    end
end

-- Held items (game chain verified: docs/research/2026-11-17-held-items.md): the game attaches tools
-- to CharacterMesh0 at hand_r sockets with KeepRelative. Components it attached at a hand socket are
-- re-attached to the VR arms' Body at the same socket, KeepRelative so the game's grip offset
-- holds. Both meshes share the game skeleton, so the sockets match. Calls (validated, UE 5.6):
-- AttachChildren SceneComponent.h:116, GetAttachSocketName :687, GetAttachParent :683,
-- GetSocketBoneName SkinnedMeshComponent.h:1094, GetParentBone :1181, DoesSocketExist
-- SceneComponent.h:814, K2_AttachToComponent :747. Arrays reach Lua as tables (ScriptUtility.cpp:206).
local KEEP_RELATIVE = 0
local moved = {}          -- component address -> { comp, socket, from }
local seen_children = {}  -- component address -> true (one discovery log line each)
local take_count = {}     -- component address -> { n = quick take-backs in a row, t = last move time }
local MAX_TAKES, QUICK_S = 3, 2.0   -- the game snatching it back within 2 s, 3 times running = a fight
local last_item_scan = -1
local function name_str(n)
    if type(n) == "string" then return n end
    local ok, v = pcall(function() return n:to_string() end)
    return ok and v or tostring(n)
end
local function addr(o) local ok, a = pcall(function() return o:get_address() end); return ok and a or tostring(o) end
local function full_name(o) local ok, v = pcall(function() return o:get_full_name() end); return ok and v or tostring(o) end

local function restore_items()
    for _, m in pairs(moved) do
        pcall(function() m.comp:K2_AttachToComponent(m.from, m.socket, KEEP_RELATIVE, KEEP_RELATIVE, KEEP_RELATIVE, false) end)
    end
    if next(moved) then log("held items returned to the game mesh") end
    moved = {}
    take_count = {}   -- a fresh equip or a re-enable gets fresh attempts
end

local function follow_items(pawn, now)
    if now - last_item_scan < 0.25 then return end
    last_item_scan = now
    local mesh, body = pawn.Mesh, actor.Body
    local body_addr = addr(body)
    for a, m in pairs(moved) do   -- the game re-attached it elsewhere (unequip, swap): let it go
        local ok, parent = pcall(function() return m.comp:GetAttachParent() end)
        if not ok or parent == nil or addr(parent) ~= body_addr then moved[a] = nil end
    end
    local children, comps = {}, {}
    for _, comp in ipairs(mesh.AttachChildren or {}) do
        local a = addr(comp)
        if comp ~= nil and a ~= body_addr then
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
    if not fit.items_follow_hands then
        if next(moved) then restore_items() end
        return
    end
    local plan = itemfollow.plan(children, function(b) return name_str(mesh:GetParentBone(b)) end)
    for _, m in ipairs(plan) do
        local comp = comps[m.id]
        local a = addr(comp)
        local tc = take_count[a] or { n = 0, t = -math.huge }
        if moved[a] == nil and tc.n < MAX_TAKES then
            tc.n = (now - tc.t < QUICK_S) and tc.n + 1 or 1   -- an ordinary re-equip starts the count over
            tc.t = now
            take_count[a] = tc
            local ok, err = pcall(function()
                if not body:DoesSocketExist(m.socket) then error("Body has no socket " .. m.socket) end
                comp:K2_AttachToComponent(body, m.socket, KEEP_RELATIVE, KEEP_RELATIVE, KEEP_RELATIVE, false)
            end)
            if ok then
                moved[a] = { comp = comp, socket = m.socket, from = mesh }
                log(string.format("held item -> VR hand %s: %s socket=%s", m.side, full_name(comp), m.socket))
            else
                log("held item FAILED: " .. full_name(comp) .. ": " .. tostring(err))
            end
            if tc.n == MAX_TAKES then
                log("held item " .. full_name(comp) .. " keeps re-attaching to the game mesh; leaving it to the game")
            end
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

local function spawn(pawn)
    local cls = uevr.api:find_uobject("BlueprintGeneratedClass " .. ARMS)
    if cls == nil then log("spawn FAILED: class not in memory after plugin load"); return false end
    local ok, err = pcall(function()
        actor = armsloader.spawn(cls, pawn:GetTransform())
        if actor == nil then error("spawn returned nil") end
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
    if name ~= "dreadmoorvr_class_loaded" then return end
    log("plugin reply: " .. tostring(data))
    flow:on_reply(data)
end)

uevr.sdk.callbacks.on_pre_engine_tick(function(_, delta)
    clock = clock + (delta or 0)
    local pawn = gameapi.local_pawn()
    local mode = pawn and modes.classify(gameapi.class_chain(pawn)) or nil
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
            flow:lost()
        end
    end
    if flow.status == "active" and actor ~= nil then
        local okt, errt = pcall(apply_tuning, clock)
        if fit.level_torso and not torso_hooked and pawn ~= nil then
            local okh, errh = pcall(install_torso_hook, pawn, clock)
            if not okh and not torso_err_logged then torso_err_logged = true; log("torso hook FAILED: " .. tostring(errh)) end
        end
        if not okt and not sample_err_logged then sample_err_logged = true; log("tuning FAILED: " .. tostring(errt)) end
    end
    if flow.status == "active" and actor ~= nil and mode == "walking" then
        local oks, errs = pcall(solve_arms, pawn)
        if not oks and not solve_err_logged then solve_err_logged = true; log("solver FAILED: " .. tostring(errs)) end
        local oki, erri = pcall(follow_items, pawn, clock)
        if not oki and not items_err_logged then items_err_logged = true; log("items FAILED: " .. tostring(erri)) end
        local ok, err = pcall(sample_arms, pawn, clock)
        if not ok and not sample_err_logged then sample_err_logged = true; log("harness FAILED: " .. tostring(err)) end
    end
    if mode ~= "walking" and next(moved) then restore_items() end   -- fishing, steering: game owns the hands
    if flow.status ~= before and (flow.status == "fail" or flow.status == "no_reply" or flow.status == "spawn_failed") then
        log("stopped: " .. flow.status .. (flow.reason and (" - " .. flow.reason) or ""))
    end
end)

uevr.sdk.callbacks.on_script_reset(function()
    restore_items()
    restore_game_body()
    if actor ~= nil then pcall(function() actor:K2_DestroyActor() end) end
    actor = nil
end)
