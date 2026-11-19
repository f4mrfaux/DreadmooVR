-- M3 gestures (NOT VALIDATED in headset): left-hand crank reels in the hook gun, a right-hand
-- swing attacks with the sickle or knife. Both press the right trigger (primary use) on UEVR's
-- emulated gamepad, which is what the game's own abilities listen for:
--   - GA_HookGun: while the hook is out, each primary-use press adds DragForcePercentPerClick
--     to the drag force (bp-dumps/GA_HookGun.txt L0060..L00C5).
--   - GA_Sickle_Attack / GA_Knife: primary use starts the attack; the hit sphere follows control
--     rotation, not the blade (docs/research/2026-11-17-remaining-hooks.md).
-- The crank only presses while the hook is out. GA_HookGun hides the gun's Hook mesh when it
-- fires and shows it again after DetachHook (L0488, L0D51), and fire and reel share the button.
-- Engine calls (UE 5.6, validated): AttachChildren SceneComponent.h:116, GetAttachSocketName :687,
-- IsVisible :834, GetOwner ActorComponent.h:490. UEVR: get_pose (ScriptContext.cpp:456),
-- XINPUT_GAMEPAD.bRightTrigger writable (lua-api datatypes/XInput.cpp:11).
local function log(msg)
    pcall(function() uevr.params.functions.log_info("[DreadmoorVR M3] " .. msg) end)
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
-- UEVR's Lua has no working require, so modules get the already-loaded ones (as in m2_arms).
local loaded = {}
local function load_module(name)
    local chunk, err = loadfile(lib_dir() .. name .. ".lua")
    if not chunk then error("cannot load " .. name .. ": " .. tostring(err)) end
    loaded[name] = chunk(loaded)
    return loaded[name]
end

local gameapi = load_module("gameapi")
local modes = load_module("modes")
local gestures = load_module("gestures")
local reticle = load_module("reticle")
local armsloader = load_module("armsloader")
log("loaded")

local TUNING_FILE = (lib_dir():gsub("scripts[/\\]lib[/\\]$", "")) .. "dreadmoorvr_arms_tuning.lua"
-- Defaults; the tuning file's `gestures = { ... }` table overrides any of them live.
local DEFAULTS = {
    enabled = true,
    reticle = true,
    hide_game_dot = true,
    crank_offset = { x = -0.06, y = 0.0, z = 0.04 },   -- m, in the gun hand's frame (OpenVR: x right, y up, z back)
    crank_r_min = 0.04, crank_r_max = 0.25, crank_radius_hysteresis_m = 0.025,
    crank_min_deg_s = 110, crank_step_deg = 90,
    swing_min_m_s = 2.0, swing_frames = 3, swing_cooldown_s = 0.4,
    tap_hold = 0.06, tap_gap = 0.06,
    guard_enabled = true, guard_enter_z = -0.65, guard_exit_z = -0.50,
    guard_front_z = -0.05, guard_min_y = -0.65, guard_max_y = 0.10, guard_max_x = 0.45,
    fishing_fight_deadzone_m = 0.08, fishing_fight_range_m = 0.28,
    fishing_cast_ear_side_m = 0.12, fishing_cast_release_forward_m = 0.22,
    fishing_cast_load_confirm_s = 0.12,
    fishing_hook_set_rise_m = 0.07,
    craft_cursor_span_m = 0.40, boat_steer_range_m = 0.22, boat_steer_deadzone_m = 0.02,
    boat_steer_curve = 1.25, boat_steer_smoothing_s = 0.08, boat_steer_drop_enter_m = 0.025,
    boat_steer_drop_exit_m = 0.008,
    boat_throttle_enter_m = 0.05, boat_throttle_release_m = 0.025, boat_throttle_turnaround_m = 0.06,
    boat_throttle_reverse_enter_m = 0.15,
    boat_throttle_full_m = 0.40,
    aim_method = 2,
}
local cfg = DEFAULTS
local clock, last_cfg = 0, -1
local native_pose_valid = { L = nil, R = nil }
local native_pose_received_at = { L = nil, R = nil }
local native_pose_source_seen = false
uevr.sdk.callbacks.on_lua_event(function(name, data)
    if name ~= "dreadmoorvr_pose_validity" or type(data) ~= "string" then return end
    local side, valid = data:match("^([LR])|([01])$")
    if side == nil then return end
    local was_seen, previous, current = native_pose_source_seen, native_pose_valid[side], valid == "1"
    native_pose_source_seen = true
    native_pose_valid[side] = current
    native_pose_received_at[side] = clock
    if not was_seen then log("native SteamVR pose-validity stream connected") end
    if previous == nil or previous ~= current then
        log("native SteamVR pose " .. side .. "=" .. (current and "valid" or "invalid"))
    end
end)
local function native_poses_valid(required_sides)
    if not native_pose_source_seen then return true end -- plugin unavailable; use UEVR's validated positions
    for _, side in ipairs(required_sides) do
        local received = native_pose_received_at[side]
        if native_pose_valid[side] ~= true or received == nil or clock - received > 0.5 then return false end
    end
    return true
end
local function native_boat_poses_valid() return native_poses_valid({ "L", "R" }) end
local function num(v, lo, hi, d) return (type(v) == "number" and v == v and v >= lo and v <= hi) and v or d end
local function read_cfg()
    local chunk = loadfile(TUNING_FILE, "t", {})
    local ok, u = false, nil
    if chunk then ok, u = pcall(chunk) end
    local g = (ok and type(u) == "table" and type(u.gestures) == "table") and u.gestures or {}
    local off = type(g.crank_offset) == "table" and g.crank_offset or {}
    local d = DEFAULTS
    return {
        enabled = g.enabled ~= false,
        reticle = g.reticle ~= false,
        hide_game_dot = g.hide_game_dot ~= false,
        crank_offset = { x = num(off.x, -0.5, 0.5, d.crank_offset.x), y = num(off.y, -0.5, 0.5, d.crank_offset.y), z = num(off.z, -0.5, 0.5, d.crank_offset.z) },
        crank_r_min = num(g.crank_r_min, 0, 0.5, d.crank_r_min), crank_r_max = num(g.crank_r_max, 0.01, 1, d.crank_r_max),
        crank_radius_hysteresis_m = num(g.crank_radius_hysteresis_m, 0, 0.1, d.crank_radius_hysteresis_m),
        crank_min_deg_s = num(g.crank_min_deg_s, 0, 2000, d.crank_min_deg_s), crank_step_deg = num(g.crank_step_deg, 10, 360, d.crank_step_deg),
        swing_min_m_s = num(g.swing_min_m_s, 0.5, 10, d.swing_min_m_s), swing_frames = num(g.swing_frames, 1, 30, d.swing_frames),
        swing_cooldown_s = num(g.swing_cooldown_s, 0, 5, d.swing_cooldown_s),
        tap_hold = num(g.tap_hold, 0.01, 0.5, d.tap_hold), tap_gap = num(g.tap_gap, 0.01, 0.5, d.tap_gap),
        guard_enabled = g.guard_enabled ~= false,
        guard_enter_z = num(g.guard_enter_z, -1, -0.1, d.guard_enter_z),
        guard_exit_z = num(g.guard_exit_z, -1, -0.1, d.guard_exit_z),
        guard_front_z = num(g.guard_front_z, -0.5, 0.5, d.guard_front_z),
        guard_min_y = num(g.guard_min_y, -1.5, 0, d.guard_min_y),
        guard_max_y = num(g.guard_max_y, -0.5, 0.5, d.guard_max_y),
        guard_max_x = num(g.guard_max_x, 0.1, 1.5, d.guard_max_x),
        fishing_fight_deadzone_m = num(g.fishing_fight_deadzone_m, 0.02, 0.3, d.fishing_fight_deadzone_m),
        fishing_fight_range_m = num(g.fishing_fight_range_m, 0.08, 0.8, d.fishing_fight_range_m),
        fishing_cast_ear_side_m = num(g.fishing_cast_ear_side_m, 0.05, 0.5, d.fishing_cast_ear_side_m),
        fishing_cast_release_forward_m = num(g.fishing_cast_release_forward_m, 0.08, 0.7, d.fishing_cast_release_forward_m),
        fishing_cast_load_confirm_s = num(g.fishing_cast_load_confirm_s, 0.05, 0.5, d.fishing_cast_load_confirm_s),
        fishing_hook_set_rise_m = num(g.fishing_hook_set_rise_m, 0.03, 0.25, d.fishing_hook_set_rise_m),
        craft_cursor_span_m = num(g.craft_cursor_span_m, 0.1, 1.5, d.craft_cursor_span_m),
        boat_steer_range_m = num(g.boat_steer_range_m, 0.05, 0.8, d.boat_steer_range_m),
        boat_steer_deadzone_m = num(g.boat_steer_deadzone_m, 0, 0.1, d.boat_steer_deadzone_m),
        boat_steer_curve = num(g.boat_steer_curve, 0.75, 2.5, d.boat_steer_curve),
        boat_steer_smoothing_s = num(g.boat_steer_smoothing_s, 0, 0.5, d.boat_steer_smoothing_s),
        boat_steer_drop_enter_m = num(g.boat_steer_drop_enter_m, 0, 0.15, d.boat_steer_drop_enter_m),
        boat_steer_drop_exit_m = num(g.boat_steer_drop_exit_m, 0, 0.15, d.boat_steer_drop_exit_m),
        boat_throttle_enter_m = num(g.boat_throttle_enter_m, 0.04, 0.4, d.boat_throttle_enter_m),
        boat_throttle_release_m = num(g.boat_throttle_release_m, 0.01, 0.15, d.boat_throttle_release_m),
        boat_throttle_turnaround_m = num(g.boat_throttle_turnaround_m, 0.02, 0.2, d.boat_throttle_turnaround_m),
        boat_throttle_reverse_enter_m = num(g.boat_throttle_reverse_enter_m, 0.08, 0.4, d.boat_throttle_reverse_enter_m),
        boat_throttle_full_m = num(g.boat_throttle_full_m, 0.15, 0.8, d.boat_throttle_full_m),
        aim_method = num(u.aim_method, 0, 5, d.aim_method),
    }
end

local crank, swing, tapper
local function rebuild()
    crank = gestures.crank({ r_min = cfg.crank_r_min, r_max = cfg.crank_r_max,
        radius_hysteresis_m = cfg.crank_radius_hysteresis_m,
        min_deg_s = cfg.crank_min_deg_s, step_deg = cfg.crank_step_deg })
    swing = gestures.swing({ min_m_s = cfg.swing_min_m_s, frames = cfg.swing_frames, cooldown_s = cfg.swing_cooldown_s })
    tapper = gestures.tapper({ hold = cfg.tap_hold, gap = cfg.tap_gap })
end
rebuild()

local function refresh_cfg()
    if clock - last_cfg < 1.0 then return end
    last_cfg = clock
    local ok, c = pcall(read_cfg)
    if not ok then return end
    local changed = false
    for k, v in pairs(c) do if type(v) ~= "table" and cfg[k] ~= v then changed = true end end
    cfg = c
    if changed then rebuild() end
end

-- Raw SteamVR pose (metres, quaternion). Rotate a local vector by the pose's rotation.
local function raw_pose(index)
    local p, q = UEVR_Vector3f.new(), UEVR_Quaternionf.new()
    uevr.params.vr.get_pose(index, p, q)
    return { X = p.x, Y = p.y, Z = p.z }, { x = q.x, y = q.y, z = q.z, w = q.w }
end
local function finite_number(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end
local function validated_pose(index_getter)
    local ok, p, q = pcall(function()
        local index = index_getter()
        local pos, rot = UEVR_Vector3f.new(), UEVR_Quaternionf.new()
        uevr.params.vr.get_pose(index, pos, rot)
        return { X = pos.x, Y = pos.y, Z = pos.z }, { x = rot.x, y = rot.y, z = rot.z, w = rot.w }
    end)
    if not ok or p == nil or q == nil then return nil, nil, "pose read failed" end
    local qn = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
    if not (finite_number(p.X) and finite_number(p.Y) and finite_number(p.Z)
        and finite_number(q.x) and finite_number(q.y) and finite_number(q.z) and finite_number(q.w)
        and finite_number(qn) and qn > 0.5 and qn < 1.5
        and math.abs(p.X) < 10 and math.abs(p.Y) < 10 and math.abs(p.Z) < 10) then
        return nil, nil, "pose values out of range"
    end
    local inv_qn = 1 / math.sqrt(qn)
    q.x, q.y, q.z, q.w = q.x * inv_qn, q.y * inv_qn, q.z * inv_qn, q.w * inv_qn
    return p, q
end
local function validated_hmd_pose()
    local h, q, err = validated_pose(uevr.params.vr.get_hmd_index)
    -- A zero identity pose can follow HMD tracking loss while controller samples remain
    -- frozen-but-finite. Fail closed for every gesture that uses an HMD-relative frame.
    if h ~= nil and math.abs(h.X) < 0.05 and math.abs(h.Y) < 0.05 and math.abs(h.Z) < 0.05 then
        return nil, nil, "HMD pose at tracking origin"
    end
    return h, q, err
end
local function rotate(q, v)   -- v' = q v q*
    local x, y, z, w = q.x, q.y, q.z, q.w
    local tx, ty, tz = 2 * (y * v.Z - z * v.Y), 2 * (z * v.X - x * v.Z), 2 * (x * v.Y - y * v.X)
    return { X = v.X + w * tx + (y * tz - z * ty), Y = v.Y + w * ty + (z * tx - x * tz), Z = v.Z + w * tz + (x * ty - y * tx) }
end

-- Which tool is in hand: the game attaches it to CharacterMesh0 at HookSimple / KnifeSocket; with
-- items_follow_hands it sits one level down, on the VR arms' Body (itself a child of the mesh).
-- Knife and sickle share KnifeSocket; the runtime component class distinguishes them so the
-- block gesture only runs with the sickle, which is the only one with GA_Sickle_Block.
local TOOL_BY_SOCKET = { HookSimple = "hookgun", KnifeSocket = "melee" }
local function name_str(n)
    if type(n) == "string" then return n end
    local ok, s = pcall(function() return n:to_string() end)
    return ok and s or tostring(n)
end
local function find_tool(mesh)
    local function scan(comp, depth)
        for _, c in ipairs(comp.AttachChildren or {}) do
            local ok, socket = pcall(function() return name_str(c:GetAttachSocketName()) end)
            local kind = ok and TOOL_BY_SOCKET[socket]
            if kind then
                if kind == "melee" then
                    local ok_full, full = pcall(function() return c:get_full_name() end)
                    if ok_full and type(full) == "string" and full:find("BP_Sickle_Equipment_C", 1, true) then
                        kind = "sickle"
                    end
                end
                return kind, c
            end
            if depth < 2 then
                local k2, c2 = scan(c, depth + 1)
                if k2 then return k2, c2 end
            end
        end
        return nil
    end
    return scan(mesh, 1)
end

local tool, tool_comp, hook_out = nil, nil, false
local pawn_id, tool_id, input_active, active_mode = nil, nil, false, nil
local guarding, guard_since, guard_release_until = false, nil, -math.huge
local fishing_reeling = false
local fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, true, nil
local fishing_bite_qte_active, fishing_bite_start_y, fishing_bite_start_time = false, nil, nil
local fishing_bite_fired = false
local fishing_hook_set_until = 0
local fishing_fish_id, fishing_neutral_x, fishing_neutral_y = nil, nil, nil
local fishing_reference_pos, fishing_reference_inv = nil, nil
local fishing_qte_tag, fishing_qte_neutral_x, fishing_qte_neutral_y = nil, nil, nil
local fishing_axis_x, fishing_axis_y = 0, 0
local fishing_last_pose_sample
-- Boat controls are driven by hand travel from a neutral pose captured on entering the boat.
-- IA_BoatMove consumes X for wheel steering and Y as three throttle detents (reverse/neutral/fwd).
local boat_axis_x, boat_axis_y = 0, 0
local boat_neutral_lx, boat_neutral_ly, boat_neutral_ry, boat_neutral_rz
-- Throttle uses a room-tracking hand anchor and a forward axis sampled while neutral. This
-- keeps head translation out of the signal and lets the axis follow the player's facing before
-- the lever moves, without rotating an active throttle mid-stroke.
local boat_throttle_neutral_hand, boat_throttle_forward
local boat_reference_inv, boat_reference_pos, boat_camera_state
local boat_throttle = nil
local boat_throttle_last_direction = 0
local boat_calibration_started, boat_stable_since, boat_calibration_sample
local boat_home_pose_notified = false
local boat_throttle_candidate, boat_throttle_candidate_since
local boat_last_motion_sample
local boat_steer_filtered, boat_steer_last_update = 0, nil
local boat_steer_detent = 0
local boat_steer_arc_active = false
local boat_controls_active = false
local boat_pose_error_last_log = -math.huge
local boat_gesture_error_last_log = -math.huge
local boat_calibration_log_last = -math.huge
local boat_cosmetic_error_last_log = -math.huge
local fishing_pose_error_last_log = -math.huge
local fishing_gesture_error_last_log = -math.huge
local boat_anchor_retry_ticks, boat_anchor_attempt = 0, 0
local boat_anchors_logged = false
local boat_pose_sample_ticks = 0
local boat_camera_look_suppressed = false
local last_log = 0
local function identity(obj)
    if obj == nil then return nil end
    local ok, a = pcall(function() return obj:get_address() end)
    return ok and a or tostring(obj)
end

-- BP_HookGunEquipment's dump names the static mesh component Hook_GEN_VARIABLE, but neither its
-- short name nor generated property is reflected on the live actor. Find the named component under
-- the actor root instead of depending on a Blueprint field alias.
local function hook_mesh(gun)
    if gun == nil then return nil end
    -- Some actor instances do expose the generated property; keep it as the cheapest path.
    local direct = gun.Hook
    if direct ~= nil then return direct end
    local root = gun.RootComponent
    local function scan(parent, depth)
        if parent == nil then return nil end
        if depth > 4 then return nil end
        for _, child in ipairs(parent.AttachChildren or {}) do
            local ok, full = pcall(function() return child:get_full_name() end)
            if ok and type(full) == "string" and full:match("%.Hook_GEN_VARIABLE$") then return child end
            local found = scan(child, depth + 1)
            if found ~= nil then return found end
        end
        return nil
    end
    local found = scan(root, 1)
    if found ~= nil then return found end

    -- The Blueprint SCS component can be present on the actor without appearing under the
    -- reflected RootComponent.AttachChildren tree. Actor.h exposes K2_GetComponentsByClass.
    local ok, components = pcall(function()
        local cls = uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent")
        if cls == nil then return nil end
        return gun:K2_GetComponentsByClass(cls)
    end)
    if ok and type(components) == "table" then
        for _, child in ipairs(components) do
            local full_ok, full = pcall(function() return child:get_full_name() end)
            if full_ok and type(full) == "string" and full:match("%.Hook_GEN_VARIABLE$") then return child end
        end
    end
    return nil
end

local function hook_is_out()
    if tool ~= "hookgun" or tool_comp == nil then return false end
    local ok, out = pcall(function()
        local gun = tool_comp:GetOwner()
        local hook = hook_mesh(gun)
        return hook ~= nil and not hook:IsVisible()
    end)
    return ok and out or false
end

-- Hook gun reticle: a small glowing sphere on the point the hook will fly to. Same trace as the
-- game (GA_HookGun.CalculateLaunchTransform): from the camera, along the camera rotation, for
-- GA_HookGun's TraceLength, Visibility channel, ignoring the player. Shown while the gun is in
-- hand and the hook is home. Calls (UE 5.6): PlayerController.PlayerCameraManager
-- PlayerController.h:285, GetCameraLocation/Rotation PlayerCameraManager.h:706/702,
-- LineTraceSingle KismetSystemLibrary.h:1243 (OutHit via StructObject, UEVR ScriptUtility.cpp:720),
-- StaticMeshActor.StaticMeshComponent StaticMeshActor.h:29, SetStaticMesh StaticMeshComponent.h:426,
-- SetMaterial / SetCollisionEnabled / SetCastShadow PrimitiveComponent.h:1516/1942/1881,
-- SetWorldScale3D SceneComponent.h:565, K2_SetActorLocation Actor.h:1575.
local GA_HOOKGUN = "BlueprintGeneratedClass /Game/Dreadmoor/Core/Features/Hook/GAS/GA_HookGun.GA_HookGun_C"
local SPHERE = "StaticMesh /Engine/BasicShapes/Sphere.Sphere"
local GLOW = "Material /Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial"
local FALLBACK_TRACE_LENGTH = 5000
local dot = { actor = nil, comp = nil, shown = false, failed = false, trace_length = nil, hit = nil, ksl = nil }

local function dot_setup(pawn)
    if dot.actor ~= nil or dot.failed then return dot.actor ~= nil end
    local cls = uevr.api:find_uobject("Class /Script/Engine.StaticMeshActor")
    local mesh = uevr.api:find_uobject(SPHERE)
    local mat = uevr.api:find_uobject(GLOW)
    local hit_struct = uevr.api:find_uobject("ScriptStruct /Script/Engine.HitResult")
    local ksl_cls = uevr.api:find_uobject("Class /Script/Engine.KismetSystemLibrary")
    if not (cls and mesh and hit_struct and ksl_cls) then
        dot.failed = true
        log(string.format("reticle off: missing %s%s%s%s", cls and "" or "StaticMeshActor ", mesh and "" or "Sphere ",
            hit_struct and "" or "HitResult ", ksl_cls and "" or "KismetSystemLibrary"))
        return false
    end
    local a = armsloader.spawn(cls, pawn:GetTransform())
    if a == nil then dot.failed = true; log("reticle off: spawn failed"); return false end
    local c = a.StaticMeshComponent
    c:SetStaticMesh(mesh)
    if mat then c:SetMaterial(0, mat) else log("reticle: glow material not loaded, using the sphere's own") end
    c:SetCollisionEnabled(0)    -- ECollisionEnabled::NoCollision
    c:SetCastShadow(false)
    a:SetActorHiddenInGame(true)
    dot.actor, dot.comp, dot.hit, dot.ksl = a, c, StructObject.new(hit_struct), ksl_cls:get_class_default_object()
    local ga = uevr.api:find_uobject(GA_HOOKGUN)
    local cdo = ga and ga:get_class_default_object()
    local len = cdo and cdo.TraceLength
    dot.trace_length = (type(len) == "number" and len > 0) and len or FALLBACK_TRACE_LENGTH
    log(string.format("reticle ready (TraceLength %.0f%s)", dot.trace_length, (type(len) == "number" and len > 0) and "" or ", fallback"))
    return true
end

-- The game's own 2D crosshair (WBP_Cross: a Dot image plus hook-state icons, bp WBP_Cross L0582..
-- L0632) points where the head looks, so it is faded out while our dot is up and restored after.
-- Render opacity is never touched by the game. GetAllWidgetsOfClass WidgetBlueprintLibrary.h:302
-- (array out-param into an empty table, UEVR ScriptUtility.cpp:748), SetRenderOpacity Widget.h.
local WBP_CROSS = "WidgetBlueprintGeneratedClass /Game/Dreadmoor/UI/HUD/WBP_Cross.WBP_Cross_C"
local function set_game_dot(opacity)
    pcall(function()
        local cls = uevr.api:find_uobject(WBP_CROSS)
        local wbl = uevr.api:find_uobject("Class /Script/UMG.WidgetBlueprintLibrary")
        if cls == nil or wbl == nil then return end
        local found = {}
        wbl:get_class_default_object():GetAllWidgetsOfClass(uevr.api:get_local_pawn(0), found, cls, false)
        for _, w in ipairs(found) do w:SetRenderOpacity(opacity) end
    end)
end

local game_dot_hidden = false
local function dot_show(on)
    if dot.actor ~= nil and on ~= dot.shown then
        dot.actor:SetActorHiddenInGame(not on)
        dot.shown = on
    end
    local hide = on and dot.shown and cfg.hide_game_dot
    if hide ~= game_dot_hidden then
        set_game_dot(hide and 0 or 1)
        game_dot_hidden = hide
    end
end

local function deactivate()
    input_active = false
    fishing_reeling = false
    fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, true, nil
    fishing_bite_qte_active, fishing_bite_start_y, fishing_bite_start_time = false, nil, nil
    fishing_bite_fired = false
    fishing_hook_set_until = 0
    fishing_fish_id, fishing_neutral_x, fishing_neutral_y = nil, nil, nil
    fishing_reference_pos, fishing_reference_inv = nil, nil
    fishing_qte_tag, fishing_qte_neutral_x, fishing_qte_neutral_y = nil, nil, nil
    fishing_axis_x, fishing_axis_y = 0, 0
    fishing_last_pose_sample = nil
    boat_axis_x, boat_axis_y = 0, 0
    boat_controls_active = false
    boat_neutral_lx, boat_neutral_ly, boat_neutral_ry, boat_neutral_rz, boat_throttle = nil, nil, nil, nil, nil
    boat_throttle_neutral_hand, boat_throttle_forward = nil, nil
    boat_throttle_last_direction = 0
    boat_reference_inv, boat_reference_pos, boat_camera_state = nil, nil, nil
    boat_calibration_started, boat_stable_since, boat_calibration_sample = nil, nil, nil
    boat_home_pose_notified = false
    boat_throttle_candidate, boat_throttle_candidate_since = nil, nil
    boat_last_motion_sample = nil
    boat_steer_filtered, boat_steer_last_update = 0, nil
    boat_steer_detent, boat_steer_arc_active = 0, false
    if guarding then
        guard_release_until = clock + 0.1
        pcall(function() uevr.params.vr.set_mod_value("VR_AimMethod", string.format("%d", math.floor(cfg.aim_method))) end)
    end
    guarding, guard_since = false, nil
    rebuild()
    tool, tool_comp, tool_id, hook_out = nil, nil, nil, false
    dot_show(false)
end

-- BP_CraftController traces from DeprojectMousePositionToWorld and already maps face buttons
-- to IA_Crafting_Click. Move only the cursor so its native hover/click path stays authoritative.
local function step_crafting()
    local pc = uevr.api:get_player_controller(0)
    local wbl = uevr.api:find_uobject("Class /Script/UMG.WidgetLayoutLibrary")
    if pc == nil or wbl == nil then return end
    local size = wbl:get_class_default_object():GetViewportSize(pc)
    if size == nil then return end
    local width, height = size.X or size.x, size.Y or size.y
    if not width or not height or width < 1 or height < 1 then return end
    local vr = uevr.params.vr
    local l = raw_pose(vr.get_left_controller_index())
    local h, hq = raw_pose(vr.get_hmd_index())
    local rel = rotate({ x = -hq.x, y = -hq.y, z = -hq.z, w = hq.w },
        { X = l.X - h.X, Y = l.Y - h.Y, Z = l.Z - h.Z })
    -- A 40 cm hand workspace spans the viewport. Keeping this absolute to the head makes the
    -- cursor predictable when entering a bench; stock game input still performs hover and click.
    local x = math.floor(width * 0.5 + rel.X / cfg.craft_cursor_span_m * width)
    local y = math.floor(height * 0.5 - rel.Y / cfg.craft_cursor_span_m * height)
    x, y = math.max(0, math.min(width - 1, x)), math.max(0, math.min(height - 1, y))
    pc:SetMouseLocation(x, y)
end

local function boat_wheel_actor(pawn)
    local component = pawn.BP_ShipSteeringWheel
    if component == nil then return nil end
    local child = component.ChildActor
    if child == nil then child = component:GetChildActor() end
    return child
end

local function log_boat_anchors(pawn)
    if boat_anchors_logged then return end
    boat_anchor_retry_ticks = boat_anchor_retry_ticks + 1
    if boat_anchor_attempt > 0 and boat_anchor_retry_ticks < 120 then return end
    boat_anchor_retry_ticks = 0
    boat_anchor_attempt = boat_anchor_attempt + 1
    local ok, wheel, lever = pcall(function()
        local child = boat_wheel_actor(pawn)
        if child == nil then error("BP_ShipSteeringWheel child actor is not spawned yet") end
        local wheel_component = child.Small_Boat_Steerwheel
        if wheel_component == nil then error("wheel mesh component is nil") end
        local lever_component = pawn.Throttle_lever
        if lever_component == nil then error("Throttle_lever component is nil") end
        return wheel_component:K2_GetComponentLocation(), lever_component:K2_GetComponentLocation()
    end)
    local err
    if not ok then err, wheel, lever = wheel, nil, nil end
    if ok and wheel ~= nil and lever ~= nil then
        -- FVector members exposed by UEVR use uppercase names; tolerate Vector3f lowercase too.
        local wx, wy, wz = wheel.X or wheel.x, wheel.Y or wheel.y, wheel.Z or wheel.z
        local lx, ly, lz = lever.X or lever.x, lever.Y or lever.y, lever.Z or lever.z
        if wx ~= nil and wy ~= nil and wz ~= nil and lx ~= nil and ly ~= nil and lz ~= nil then
            log(string.format("boat mesh anchors: wheel=(%.1f,%.1f,%.1f) throttle=(%.1f,%.1f,%.1f)",
                wx, wy, wz, lx, ly, lz))
            boat_anchors_logged = true
            return
        end
        err = "component location returned an unreadable vector"
    end
    log("boat mesh anchor lookup attempt " .. boat_anchor_attempt .. " failed: " .. tostring(err or "component location unavailable"))
end

local function sync_cosmetic_wheel(pawn)
    local ok, err = pcall(function()
        local child = boat_wheel_actor(pawn)
        if child == nil then return end
        local cosmetic_module = child.CurrentActiveWheelCosmetic
        if cosmetic_module == nil then return end
        -- The Blueprint property is a modular-object wrapper; its Actor member is the spawned
        -- cosmetic actor that actually receives SetActorRotation (BP_ShipSteeringWheel L0D9E).
        -- Some game versions may expose the actor directly, so retain that safe fallback.
        local cosmetic = cosmetic_module.Actor
        if cosmetic == nil then cosmetic = cosmetic_module end
        -- Match BP_ShipSteeringWheel.ReceiveTick: it copies the steering-wheel ACTOR's
        -- world rotation to the cosmetic module. The mesh component may have its own
        -- relative rotation, so using its world rotation adds that offset a second time.
        local wheel_rotation = child:K2_GetActorRotation()
        cosmetic:K2_SetActorRotation(wheel_rotation, false)
    end)
    if not ok and clock - boat_cosmetic_error_last_log >= 2 then
        boat_cosmetic_error_last_log = clock
        log("boat cosmetic wheel sync FAILED: " .. tostring(err))
    end
end

local function supports_wheel_boat(pawn)
    for _, class_name in ipairs(gameapi.class_chain(pawn)) do
        if class_name == "BP_SmallBoat_V2_C" then return true end
    end
    return false
end

local function boat_rotation_string(object, getter)
    local ok, rotation = pcall(function() return object[getter](object) end)
    if not ok or rotation == nil then return "unavailable" end
    local pitch, yaw, roll = rotation.Pitch, rotation.Yaw, rotation.Roll
    if type(pitch) ~= "number" or type(yaw) ~= "number" or type(roll) ~= "number" then
        return "unavailable"
    end
    return string.format("(%.1f,%.1f,%.1f)", pitch, yaw, roll)
end

local function step_boat(pawn)
    -- BP_SmallBoat_V2 sets this flag when it switches to its helm camera. Preserve the game's
    -- physical/gamepad steering in third-person; only claim IA_BoatMove axes in first-person.
    local ok_camera, first_person = pcall(function() return pawn.bFirstPersonCameraEnabled end)
    local camera_state = ok_camera and (first_person == true and "first_person" or "third_person")
        or (boat_camera_state == "first_person" and "first_person" or "unknown")
    if camera_state ~= boat_camera_state then
        boat_camera_state = camera_state
        log(camera_state == "first_person" and "boat first-person gesture steering active"
            or camera_state == "third_person" and "boat third-person native axes active"
            or "boat camera flag unavailable; native axes active")
    end
    if camera_state ~= "first_person" then
        boat_controls_active = false
        boat_camera_look_suppressed = false
        if boat_neutral_lx ~= nil then log("boat gestures paused; native axes restored") end
        boat_axis_x, boat_axis_y = 0, 0
        boat_neutral_lx, boat_neutral_ly, boat_neutral_ry, boat_neutral_rz, boat_throttle = nil, nil, nil, nil, nil
        boat_throttle_neutral_hand, boat_throttle_forward = nil, nil
        boat_throttle_last_direction = 0
        boat_reference_inv = nil
        boat_reference_pos = nil
        boat_calibration_started, boat_stable_since, boat_calibration_sample = nil, nil, nil
        boat_home_pose_notified = false
        boat_throttle_candidate, boat_throttle_candidate_since = nil, nil
        boat_last_motion_sample = nil
        boat_steer_filtered, boat_steer_last_update = 0, nil
        boat_steer_detent, boat_steer_arc_active = 0, false
        boat_anchor_retry_ticks, boat_anchor_attempt, boat_anchors_logged = 0, 0, false
        boat_pose_sample_ticks = 0
        return
    end

    -- Claim the axes for the whole first-person helm session, including calibration and
    -- tracking-error frames. Those paths must hold neutral, not leak physical stick input through.
    boat_controls_active = true
    local vr = uevr.params.vr
    -- Some runtimes (including Steam Frame hand tracking through UEVR) report
    -- is_using_controllers=false while get_pose still returns live hand poses.
    -- Treat validated pose reads as the authority; the boolean is only a runtime
    -- hint and must not disable the controls by itself.
    local ok_tracking, tracking = pcall(vr.is_using_controllers)
    local l, _, left_error = validated_pose(vr.get_left_controller_index)
    local r, _, right_error = validated_pose(vr.get_right_controller_index)
    local h, hq, head_error = validated_hmd_pose()
    local native_valid = native_boat_poses_valid()
    if l == nil or r == nil or h == nil or not native_valid then
        boat_axis_x, boat_axis_y, boat_throttle = 0, 0, 0
        boat_neutral_lx, boat_neutral_ly, boat_neutral_ry, boat_neutral_rz = nil, nil, nil, nil
        boat_throttle_neutral_hand, boat_throttle_forward = nil, nil
        boat_throttle_last_direction = 0
        boat_reference_inv, boat_reference_pos = nil, nil
        boat_calibration_started, boat_stable_since, boat_calibration_sample = nil, nil, nil
        boat_home_pose_notified = false
        boat_throttle_candidate, boat_throttle_candidate_since = nil, nil
        boat_last_motion_sample = nil
        boat_steer_filtered, boat_steer_last_update = 0, nil
        boat_steer_detent, boat_steer_arc_active = 0, false
        if clock - boat_pose_error_last_log >= 1 then
            boat_pose_error_last_log = clock
            log("boat controls fail-safe: controller tracking=" .. tostring(ok_tracking and tracking)
                .. " L=" .. tostring(left_error) .. " R=" .. tostring(right_error) .. " HMD=" .. tostring(head_error)
                .. " native_pose_valid=" .. tostring(native_valid))
        end
        return
    end
    -- Before a recognized driving home pose, inspect controller positions relative to the live
    -- head so the detector works even if the player's room-scale origin differs at helm entry.
    -- Once home is held stable, calibration locks that exact head origin/yaw; active controls then
    -- use the fixed frame so leaning or looking cannot move the throttle reference.
    local live_yaw = math.atan(2 * (hq.w * hq.y + hq.x * hq.z), 1 - 2 * (hq.y * hq.y + hq.z * hq.z))
    local live_reference_inv = { x = 0, y = -math.sin(live_yaw * 0.5), z = 0, w = math.cos(live_yaw * 0.5) }
    local frame_inv = boat_reference_inv or live_reference_inv
    local frame_pos = boat_reference_pos or h
    local offset_l = { X = l.X - frame_pos.X, Y = l.Y - frame_pos.Y, Z = l.Z - frame_pos.Z }
    local offset_r = { X = r.X - frame_pos.X, Y = r.Y - frame_pos.Y, Z = r.Z - frame_pos.Z }
    local lp = rotate(frame_inv, offset_l)
    local rp = rotate(frame_inv, offset_r)
    local motion = boat_reference_inv ~= nil and boat_last_motion_sample or nil
    if motion ~= nil then
        local dt = clock - motion.time
        if dt > 0 then
            local dl = math.sqrt((lp.X - motion.lx) ^ 2 + (lp.Y - motion.ly) ^ 2 + (lp.Z - motion.lz) ^ 2) / dt
            local dr = math.sqrt((rp.X - motion.rx) ^ 2 + (rp.Y - motion.ry) ^ 2 + (rp.Z - motion.rz) ^ 2) / dt
            if dl > 8 or dr > 8 then
                boat_axis_x, boat_axis_y, boat_throttle = 0, 0, 0
                boat_neutral_lx, boat_neutral_ly, boat_neutral_ry, boat_neutral_rz = nil, nil, nil, nil
                boat_throttle_neutral_hand, boat_throttle_forward = nil, nil
                boat_throttle_last_direction = 0
                boat_reference_inv, boat_reference_pos = nil, nil
                boat_calibration_started, boat_stable_since, boat_calibration_sample = nil, nil, nil
                boat_home_pose_notified = false
                boat_throttle_candidate, boat_throttle_candidate_since = nil, nil
                boat_last_motion_sample = nil
                boat_steer_filtered, boat_steer_last_update = 0, nil
                boat_steer_detent, boat_steer_arc_active = 0, false
                if clock - boat_pose_error_last_log >= 1 then
                    boat_pose_error_last_log = clock
                    log(string.format("boat controls fail-safe: implausible pose jump (left %.1f m/s, right %.1f m/s)", dl, dr))
                end
                return
            end
        end
    end
    if boat_reference_inv ~= nil then
        boat_last_motion_sample = { time = clock, lx = lp.X, ly = lp.Y, lz = lp.Z, rx = rp.X, ry = rp.Y, rz = rp.Z }
    else
        boat_last_motion_sample = nil
    end
    local lx, ly, ry = lp.X, lp.Y, rp.Y
    if boat_neutral_lx == nil then
        boat_axis_x, boat_axis_y, boat_throttle = 0, 0, 0
        -- Do not bless whatever pose the player happens to have when the helm activates.
        -- Require a recognizable driving home: left hand on the upper-left wheel arc (about
        -- 120 o'clock), and right hand at the hip-fire neutral reach. Bounds are broad in the
        -- fixed, head-yaw-aligned tracking frame; the stability check below filters noise.
        -- Video telemetry showed the intended wheel home around ly=-0.77 m; the old -0.75
        -- cutoff made calibration flicker on only 2 cm of natural pose variation.
        local left_home = lx >= -0.70 and lx <= 0.12 and ly >= -0.90 and ly <= -0.05
            and lp.Z >= -0.80 and lp.Z <= 0.12
        local right_home = rp.X >= 0.02 and rp.X <= 0.70 and ry >= -0.95 and ry <= -0.10
            and rp.Z >= -0.75 and rp.Z <= 0.15
        if not (left_home and right_home) then
            boat_calibration_started, boat_stable_since, boat_calibration_sample = nil, nil, nil
            boat_home_pose_notified = false
            if clock - boat_calibration_log_last >= 1 then
                boat_calibration_log_last = clock
                log(string.format("boat home pose not recognized; place left hand at wheel 120 o'clock and right hand in hip-fire neutral; L=(%.2f,%.2f,%.2f) R=(%.2f,%.2f,%.2f)",
                    lx, ly, lp.Z, rp.X, ry, rp.Z))
            end
            return
        end
        if not boat_home_pose_notified then
            boat_home_pose_notified = true
            log("boat home pose recognized; hold both hands still to calibrate neutral")
            pcall(function()
                local source = vr.get_right_joystick_source()
                vr.trigger_haptic_vibration(0, 0.025, 170, 0.35, source)
            end)
        end
        boat_calibration_started = boat_calibration_started or clock
        local prior = boat_calibration_sample
        local stable = prior ~= nil and math.abs(lx - prior.lx) < 0.025 and math.abs(ly - prior.ly) < 0.025
            and math.abs(ry - prior.ry) < 0.025
            and math.abs(rp.Z - prior.rz) < 0.025
        boat_calibration_sample = { lx = lx, ly = ly, ry = ry, rz = rp.Z }
        if stable then boat_stable_since = boat_stable_since or clock else boat_stable_since = nil end
        -- The home pose itself defines neutral. Require a brief stable hold after recognition.
        if clock - boat_calibration_started >= 0.20 and boat_stable_since ~= nil and clock - boat_stable_since >= 0.25 then
            boat_reference_inv = live_reference_inv
            boat_reference_pos = { X = h.X, Y = h.Y, Z = h.Z }
            boat_neutral_lx, boat_neutral_ly, boat_neutral_ry, boat_neutral_rz = lx, ly, ry, rp.Z
            boat_throttle_neutral_hand = { X = r.X, Y = r.Y, Z = r.Z }
            boat_throttle_forward = rotate(hq, { X = 0, Y = 0, Z = -1 })
            boat_throttle_last_direction = 0
            boat_calibration_started, boat_stable_since, boat_calibration_sample = nil, nil, nil
            boat_throttle_candidate, boat_throttle_candidate_since = 0, clock
            boat_last_motion_sample = nil
            log(string.format("boat control frame locked from home pose: head_origin=(%.3f,%.3f,%.3f)m yaw=%.1f",
                h.X, h.Y, h.Z, math.deg(live_yaw)))
            log("boat gestures calibrated from recognized home; left hand at 120 o'clock=straight, arc left/right slightly down to steer; right hand hip-fire=neutral, pull fully back to reverse, extend forward for increasing throttle")
            log_boat_anchors(pawn)
        elseif clock - boat_calibration_log_last >= 1 then
            boat_calibration_log_last = clock
            log("boat home pose accepted; hold still while neutral calibration settles")
        end
        return
    end
    sync_cosmetic_wheel(pawn)
    log_boat_anchors(pawn)
    -- Model the wheel as a top-center neutral point with a shallow lower arc: the left hand
    -- must drop slightly before horizontal travel steers, so lateral noise at the top stays straight.
    local steer = lx - boat_neutral_lx
    local left_drop = boat_neutral_ly - ly
    local steer_magnitude = math.abs(steer)
    local steer_span = math.max(0.001, cfg.boat_steer_range_m - cfg.boat_steer_deadzone_m)
    local steer_amount = 0
    if not boat_steer_arc_active and left_drop >= cfg.boat_steer_drop_enter_m then
        boat_steer_arc_active = true
    elseif boat_steer_arc_active and left_drop <= cfg.boat_steer_drop_exit_m then
        boat_steer_arc_active = false
    end
    if boat_steer_arc_active and steer_magnitude > cfg.boat_steer_deadzone_m then
        steer_amount = math.min(1, (steer_magnitude - cfg.boat_steer_deadzone_m) / steer_span)
    end
    local steer_target = (steer < 0 and -1 or 1) * (steer_amount ^ cfg.boat_steer_curve)
    local dt = boat_steer_last_update and math.max(0, clock - boat_steer_last_update) or 0
    boat_steer_last_update = clock
    if steer_amount == 0 then
        boat_steer_filtered = 0
    elseif cfg.boat_steer_smoothing_s > 0 and dt > 0 then
        local alpha = 1 - math.exp(-dt / cfg.boat_steer_smoothing_s)
        boat_steer_filtered = boat_steer_filtered + (steer_target - boat_steer_filtered) * alpha
    else
        boat_steer_filtered = steer_target
    end
    boat_axis_x = boat_steer_filtered
    -- Four small steering steps on each side make the physical wheel gesture tactile. Hysteresis
    -- keeps hand-tracking noise from buzzing around a boundary; clicks go to the left controller.
    local detent = boat_steer_detent
    while detent < 4 and boat_axis_x >= (detent + 0.5) / 4 + 0.06 do detent = detent + 1 end
    while detent > -4 and boat_axis_x <= (detent - 0.5) / 4 - 0.06 do detent = detent - 1 end
    if detent ~= boat_steer_detent then
        boat_steer_detent = detent
        pcall(function()
            local source = vr.get_left_joystick_source()
            vr.trigger_haptic_vibration(0, 0.012, 110, 0.20, source)
        end)
    end
    -- Project room-tracking hand travel from its calibrated neutral position onto the player's
    -- forward axis. The previous path used head-relative Z in the yaw frozen at helm entry; if
    -- the player's heading changed, a forward reach could land on the reverse side. Refresh the
    -- axis while neutral, then hold it through an active detent so looking around cannot reverse
    -- a held throttle. Keep the neutral hand anchor fixed so slow arm motion accumulates instead
    -- of being absorbed as tracking drift. Blueprint inspection confirms +Y is forward.
    if boat_throttle == 0 and (boat_throttle_candidate == nil or boat_throttle_candidate == 0) then
        boat_throttle_forward = rotate(hq, { X = 0, Y = 0, Z = -1 })
    end
    local throttle_delta = boat_throttle_neutral_hand and vsub(r, boat_throttle_neutral_hand)
        or { X = 0, Y = 0, Z = 0 }
    local forward_axis = boat_throttle_forward or rotate(hq, { X = 0, Y = 0, Z = -1 })
    local throttle_travel = vdot(throttle_delta, forward_axis)
    local previous = boat_throttle or 0
    local candidate = previous
    if previous == 0 then
        if boat_throttle_last_direction == 1 and throttle_travel <= -cfg.boat_throttle_reverse_enter_m then candidate = -1
        elseif boat_throttle_last_direction == -1 and throttle_travel >= cfg.boat_throttle_turnaround_m then candidate = 1
        elseif throttle_travel >= cfg.boat_throttle_enter_m then candidate = 1
        elseif throttle_travel <= -cfg.boat_throttle_reverse_enter_m then candidate = -1 end
    elseif previous == 1 and throttle_travel < cfg.boat_throttle_release_m then
        candidate = 0
    elseif previous == -1 and throttle_travel > -cfg.boat_throttle_release_m then
        candidate = 0
    end
    if candidate ~= previous then
        if boat_throttle_candidate ~= candidate then
            boat_throttle_candidate, boat_throttle_candidate_since = candidate, clock
        -- The hand can briefly cross a detent during tracking jitter or a quick elbow movement.
        -- Require a steady candidate before changing the boat input; reverse has an additional
        -- larger travel threshold so an accidental pull cannot kick the boat backward.
        elseif clock - (boat_throttle_candidate_since or clock) >= 0.25 then
            boat_throttle = candidate
            if candidate ~= 0 then boat_throttle_last_direction = candidate
            elseif previous ~= 0 then boat_throttle_last_direction = previous end
            boat_throttle_candidate, boat_throttle_candidate_since = candidate, clock
            log("boat throttle detent: " .. (candidate == 1 and "forward" or candidate == -1 and "reverse" or "neutral"))
            -- UEVR 2.39 exposes this wrapper; guard it for runtimes that omit haptics.
            pcall(function()
                local source = vr.get_right_joystick_source()
                vr.trigger_haptic_vibration(0, 0.025, 150, 0.45, source)
            end)
        else
        end
    else
        boat_throttle_candidate, boat_throttle_candidate_since = previous, clock
    end
    if boat_throttle == 1 then
        boat_axis_y = math.max(0.10, math.min(1, throttle_travel / cfg.boat_throttle_full_m))
    elseif boat_throttle == -1 then
        boat_axis_y = -1
    else
        boat_axis_y = 0
    end
    -- Low-rate live telemetry makes helm alignment and room-scale drift diagnosable from an
    -- ordinary playtest log without recording every VR frame.
    boat_pose_sample_ticks = boat_pose_sample_ticks + 1
    if boat_pose_sample_ticks >= 90 then
        boat_pose_sample_ticks = 0
        log(string.format("boat pose: L=(%.3f,%.3f,%.3f) R=(%.3f,%.3f,%.3f) head=(%.3f,%.3f,%.3f) steer=%.2f throttle=%d input=%.2f reach=%.2f",
            lp.X, lp.Y, lp.Z, rp.X, rp.Y, rp.Z, h.X, h.Y, h.Z, boat_axis_x, boat_throttle or 0, boat_axis_y, throttle_travel))
        -- Keep view and gesture diagnostics together. The earlier pose line only recorded HMD
        -- translation, which cannot distinguish a physical head turn from game camera rotation.
        -- The blueprint's `CameraComp` property resolves to its default object in some UEVR
        -- builds; prefer the live first-person components (the spring arm is what applies the
        -- boat's view rotation) and use the camera property only as a last fallback.
        local ok_camera_component, camera_component = pcall(function() return pawn.FirstPersonCamera_GEN_VARIABLE end)
        if not ok_camera_component or camera_component == nil then
            ok_camera_component, camera_component = pcall(function() return pawn.FirstPersonSpringArm_GEN_VARIABLE end)
        end
        if not ok_camera_component or camera_component == nil then
            ok_camera_component, camera_component = pcall(function() return pawn.FirstPersonSpringArm end)
        end
        if not ok_camera_component or camera_component == nil then
            ok_camera_component, camera_component = pcall(function() return pawn.CameraComp end)
        end
        local camera_rotation = ok_camera_component and boat_rotation_string(camera_component, "K2_GetComponentRotation")
            or "unavailable"
        local boat_rotation = boat_rotation_string(pawn, "K2_GetActorRotation")
        log(string.format("boat view: uevr_controllers=%s poses_valid=L%s,R%s,H%s native_valid=%s hmd_q=(%.3f,%.3f,%.3f,%.3f) camera_rot=%s boat_rot=%s",
            tostring(ok_tracking and tracking), tostring(l ~= nil), tostring(r ~= nil), tostring(h ~= nil),
            tostring(native_valid), hq.x, hq.y, hq.z, hq.w, camera_rotation, boat_rotation))
        log(string.format("boat gesture deltas: steer_x=%.3f wheel_drop=%.3f neutral_x=%.3f neutral_y=%.3f neutral_reach=%.3f",
            steer, left_drop, boat_neutral_lx, boat_neutral_ly, throttle_travel))
    end
end

local function value_name(v)
    if v == nil then return "None" end
    local ok, s = pcall(function() return v:to_string() end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end

local function fishing_fish(pawn)
    local ok, fish = pcall(function() return pawn.StrugglingFish end)
    if not ok or fish == nil or fish == false or value_name(fish) == "None" then return nil end
    local ok_name, full = pcall(function() return fish:get_full_name() end)
    return ok_name and type(full) == "string" and full ~= "" and full ~= "None" and fish or nil
end

local function fishing_qte(pawn)
    local ok, qte = pcall(function() return pawn.CurrentQTE end)
    if not ok or qte == nil then return "Unknown" end
    -- UEVR exposes FGameplayTag as a temporary StructObject. tostring() on that wrapper gives
    -- its allocation address, which changes each frame and makes every QTE look active forever.
    -- FGameplayTag.TagName is a reflected FName (GameplayTagContainer.h); stringify that value.
    if type(qte) == "string" then return qte end -- supports test/fallback sources
    local ok_name, name = pcall(function() return qte.TagName:to_string() end)
    if ok_name and type(name) == "string" and name ~= "" then return name end
    return "Unknown" -- fail closed: never reel while the tag cannot be read
end

local function lean_axis(delta)
    local amount = math.abs(delta)
    if amount <= cfg.fishing_fight_deadzone_m then return 0 end
    local span = math.max(0.001, cfg.fishing_fight_range_m - cfg.fishing_fight_deadzone_m)
    local value = math.min(1, (amount - cfg.fishing_fight_deadzone_m) / span)
    return delta < 0 and -value or value
end

local function clear_fishing_gestures(reason)
    if fishing_reeling then log("fishing crank: released (" .. reason .. ")") end
    fishing_reeling = false
    fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, false, nil
    input_active = false
    fishing_fish_id, fishing_neutral_x, fishing_neutral_y = nil, nil, nil
    fishing_reference_pos, fishing_reference_inv = nil, nil
    fishing_qte_tag, fishing_qte_neutral_x, fishing_qte_neutral_y = nil, nil, nil
    fishing_axis_x, fishing_axis_y = 0, 0
    fishing_last_pose_sample = nil
    fishing_hook_set_until = 0
    crank:reset()
end

-- Cast is the game's charge/release action: load the right hand by the ear, hold IA_Fishing_Cast,
-- then release it on a forward extension. The gesture intentionally never writes look axes.
local function step_fishing_cast(pawn)
    if fishing_qte(pawn) ~= "None" then
        fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, false, nil
        return
    end
    local vr = uevr.params.vr
    local ok_tracking, tracking = pcall(vr.is_using_controllers)
    local hand, _, hand_error = validated_pose(vr.get_right_controller_index)
    local head, head_q, head_error = validated_hmd_pose()
    local native_valid = native_poses_valid({ "R" })
    if hand == nil or head == nil or not native_valid then
        if fishing_cast_held then log("fishing cast gesture: released (tracking unavailable)") end
        fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, false, nil
        if clock - fishing_pose_error_last_log >= 1 then
            fishing_pose_error_last_log = clock
            log("fishing cast fail-safe: tracking=" .. tostring(ok_tracking and tracking)
                .. " R=" .. tostring(hand_error) .. " HMD=" .. tostring(head_error)
                .. " native_pose_valid=" .. tostring(native_valid))
        end
        return
    end
    local d = { X = hand.X - head.X, Y = hand.Y - head.Y, Z = hand.Z - head.Z }
    local right, up, forward_axis = rotate(head_q, { X = 1, Y = 0, Z = 0 }),
        rotate(head_q, { X = 0, Y = 1, Z = 0 }), rotate(head_q, { X = 0, Y = 0, Z = -1 })
    local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
    local side = dot(d, right)
    local height = dot(d, up)
    local forward = dot(d, forward_axis)
    local at_ear = side >= cfg.fishing_cast_ear_side_m and height >= -0.30 and height <= 0.25 and forward <= 0.08
    local extended = side >= cfg.fishing_cast_ear_side_m * 0.5 and forward >= cfg.fishing_cast_release_forward_m
    if fishing_cast_held then
        if extended then
            fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, false, nil
            log(string.format("fishing cast gesture: released at forward reach %.2fm", forward))
        end
    elseif not fishing_cast_armed then
        if not at_ear then fishing_cast_armed = true end
    elseif at_ear then
        fishing_cast_load_since = fishing_cast_load_since or clock
        if clock - fishing_cast_load_since >= cfg.fishing_cast_load_confirm_s then
            fishing_cast_held, fishing_cast_armed = true, false
            log("fishing cast gesture: charging from right-ear load")
        end
    else
        fishing_cast_load_since = nil
    end
end

-- The FishingBite widget listens to IA_Fishing_Cast and succeeds on a press. Detect a quick
-- upward right-hand twitch during that QTE and send one short trigger pulse to set the hook.
local function step_fishing_hook_set(pawn, qte)
    if qte ~= "QTE.Type.FishingBite" then
        fishing_bite_qte_active, fishing_bite_start_y, fishing_bite_start_time = false, nil, nil
        fishing_bite_fired = false
        return
    end
    local vr = uevr.params.vr
    local ok_tracking, tracking = pcall(vr.is_using_controllers)
    local hand, _, hand_error = validated_pose(vr.get_right_controller_index)
    local head, head_q, head_error = validated_hmd_pose()
    local native_valid = native_poses_valid({ "R" })
    if hand == nil or head == nil or not native_valid then
        fishing_bite_qte_active, fishing_bite_start_y, fishing_bite_start_time = true, nil, nil
        -- Keep the one-hook-set-per-QTE latch through brief tracking loss. It is reset only
        -- when the bite QTE tag exits above, so reacquisition cannot submit a second hook set.
        fishing_hook_set_until = 0
        if clock - fishing_pose_error_last_log >= 1 then
            fishing_pose_error_last_log = clock
            log("fishing hook-set fail-safe: tracking=" .. tostring(ok_tracking and tracking)
                .. " R=" .. tostring(hand_error) .. " HMD=" .. tostring(head_error)
                .. " native_pose_valid=" .. tostring(native_valid))
        end
        return
    end
    local d = { X = hand.X - head.X, Y = hand.Y - head.Y, Z = hand.Z - head.Z }
    local up = rotate(head_q, { X = 0, Y = 1, Z = 0 })
    local height = d.X * up.X + d.Y * up.Y + d.Z * up.Z
    if not fishing_bite_qte_active then
        fishing_bite_qte_active, fishing_bite_start_y, fishing_bite_start_time = true, height, clock
        fishing_bite_fired = false
        log("fishing hook-set gesture: ready; quick right-hand twitch up")
        return
    end
    if fishing_bite_fired then return end
    if fishing_bite_start_y == nil then
        fishing_bite_start_y, fishing_bite_start_time = height, clock
        return
    end
    local elapsed = clock - fishing_bite_start_time
    local rise = height - fishing_bite_start_y
    if elapsed > 0 and elapsed <= 0.24 and rise >= cfg.fishing_hook_set_rise_m and rise / elapsed >= 0.45 then
        fishing_bite_fired, fishing_bite_start_y, fishing_bite_start_time = true, nil, nil
        fishing_hook_set_until = clock + 0.08
        log(string.format("fishing hook-set gesture: upward twitch %.2fm in %.2fs", rise, elapsed))
        return
    end
    if elapsed > 0.24 or rise < -0.04 then
        fishing_bite_start_y, fishing_bite_start_time = height, clock
    end
end

local function step_fishing(pawn)
    if clock - last_cfg >= 1.0 then
        last_cfg = clock
        local ok, c = pcall(read_cfg)
        if ok then
            local changed = false
            for k, v in pairs(c) do if type(v) ~= "table" and cfg[k] ~= v then changed = true end end
            cfg = c
            if changed then rebuild() end
        end
    end
    if not cfg.enabled then
        if fishing_reeling then log("fishing crank: released (no fish or QTE active)") end
        fishing_reeling = false
        fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, true, nil
        input_active = false
        fishing_fish_id, fishing_neutral_x, fishing_neutral_y = nil, nil, nil
        fishing_reference_pos, fishing_reference_inv = nil, nil
        fishing_qte_tag, fishing_qte_neutral_x, fishing_qte_neutral_y = nil, nil, nil
        fishing_axis_x, fishing_axis_y = 0, 0
        fishing_last_pose_sample = nil
        crank:reset()
        return
    end

    local qte = fishing_qte(pawn)
    step_fishing_hook_set(pawn, qte)
    if qte == "QTE.Type.FishingBite" then
        fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, false, nil
        fishing_reeling, input_active = false, false
        fishing_axis_x, fishing_axis_y = 0, 0
        return
    end
    local fish = fishing_fish(pawn)
    if fish == nil then
        step_fishing_cast(pawn)
        if fishing_reeling then log("fishing crank: released (no fish)") end
        fishing_reeling = false
        input_active = false
        fishing_fish_id, fishing_neutral_x, fishing_neutral_y = nil, nil, nil
        fishing_reference_pos, fishing_reference_inv = nil, nil
        fishing_qte_tag, fishing_qte_neutral_x, fishing_qte_neutral_y = nil, nil, nil
        fishing_axis_x, fishing_axis_y = 0, 0
        fishing_last_pose_sample = nil
        crank:reset()
        return
    end

    if fishing_cast_held then
        fishing_cast_held, fishing_cast_armed, fishing_cast_load_since = false, false, nil
        log("fishing cast gesture: released (fish fight started)")
    end

    local vr = uevr.params.vr
    local ok_tracking, tracking = pcall(vr.is_using_controllers)
    local lpos, _, left_error = validated_pose(vr.get_left_controller_index)
    local rpos, rq, right_error = validated_pose(vr.get_right_controller_index)
    local hmd, hmd_q, head_error = validated_hmd_pose()
    local native_valid = native_poses_valid({ "L", "R" })
    if lpos == nil or rpos == nil or hmd == nil or not native_valid then
        local errors = "controller tracking=" .. tostring(ok_tracking and tracking)
            .. " L=" .. tostring(left_error) .. " R=" .. tostring(right_error) .. " HMD=" .. tostring(head_error)
            .. " native_pose_valid=" .. tostring(native_valid)
        clear_fishing_gestures("pose unavailable")
        if clock - fishing_pose_error_last_log >= 1 then
            fishing_pose_error_last_log = clock
            log("fishing controls fail-safe: " .. errors .. "; gesture input released and neutral reference cleared")
        end
        return
    end
    local prior_pose = fishing_last_pose_sample
    if prior_pose ~= nil then
        local dt = clock - prior_pose.time
        if dt > 0 then
            local function speed(pos, x, y, z)
                return math.sqrt((pos.X - x) ^ 2 + (pos.Y - y) ^ 2 + (pos.Z - z) ^ 2) / dt
            end
            local left_speed = speed(lpos, prior_pose.lx, prior_pose.ly, prior_pose.lz)
            local right_speed = speed(rpos, prior_pose.rx, prior_pose.ry, prior_pose.rz)
            local head_speed = speed(hmd, prior_pose.hx, prior_pose.hy, prior_pose.hz)
            if left_speed > 8 or right_speed > 8 or head_speed > 8 then
                clear_fishing_gestures("tracking discontinuity")
                if clock - fishing_pose_error_last_log >= 1 then
                    fishing_pose_error_last_log = clock
                    log(string.format("fishing controls fail-safe: implausible pose jump (L %.1f, R %.1f, HMD %.1f m/s); recalibrating",
                        left_speed, right_speed, head_speed))
                end
                return
            end
        end
    end
    fishing_last_pose_sample = {
        time = clock,
        lx = lpos.X, ly = lpos.Y, lz = lpos.Z,
        rx = rpos.X, ry = rpos.Y, rz = rpos.Z,
        hx = hmd.X, hy = hmd.Y, hz = hmd.Z,
    }
    local id = identity(fish)
    if id ~= fishing_fish_id then
        fishing_fish_id = id
        -- Lock a gesture frame for this fish. The HMD continues to own the view during fishing,
        -- but head turns and the game's moving fishing camera must not rotate hand-control axes
        -- underneath the player's rod motion.
        fishing_reference_pos = { X = hmd.X, Y = hmd.Y, Z = hmd.Z }
        fishing_reference_inv = { x = -hmd_q.x, y = -hmd_q.y, z = -hmd_q.z, w = hmd_q.w }
        fishing_last_pose_sample = {
            time = clock,
            lx = lpos.X, ly = lpos.Y, lz = lpos.Z,
            rx = rpos.X, ry = rpos.Y, rz = rpos.Z,
            hx = hmd.X, hy = hmd.Y, hz = hmd.Z,
        }
        fishing_neutral_x, fishing_neutral_y = nil, nil
        fishing_qte_tag, fishing_qte_neutral_x, fishing_qte_neutral_y = nil, nil, nil
        log("fishing fight gesture: calibrated")
    end

    local hand_from_reference = vsub(rpos, fishing_reference_pos or hmd)
    local fish_local = rotate(fishing_reference_inv or { x = -hmd_q.x, y = -hmd_q.y, z = -hmd_q.z, w = hmd_q.w }, hand_from_reference)
    local relative_x, relative_y = fish_local.X, fish_local.Y
    if fishing_neutral_x == nil then fishing_neutral_x, fishing_neutral_y = relative_x, relative_y end

    local qte = fishing_qte(pawn)
    local directional_drag = qte == "QTE.Type.DirectionalDrag"
    if qte ~= fishing_qte_tag then
        fishing_qte_tag = qte
        if directional_drag then
            fishing_qte_neutral_x, fishing_qte_neutral_y = relative_x, relative_y
            log("fishing QTE: directional drag")
        elseif qte ~= "None" then
            log("fishing QTE: physical input " .. qte)
        end
    end

    fishing_axis_x, fishing_axis_y = 0, 0
    if qte == "None" then
        fishing_axis_x = lean_axis(relative_x - fishing_neutral_x)
    elseif directional_drag then
        fishing_axis_x = lean_axis(relative_x - fishing_qte_neutral_x)
        fishing_axis_y = lean_axis(relative_y - fishing_qte_neutral_y)
    end

    if qte ~= "None" then
        if fishing_reeling then log("fishing crank: released (QTE active)") end
        fishing_reeling = false
        crank:reset()
        input_active = false
        return
    end

    local o = cfg.crank_offset
    local off = rotate(rq, { X = o.x, Y = o.y, Z = o.z })
    local pivot = { X = rpos.X + off.X, Y = rpos.Y + off.Y, Z = rpos.Z + off.Z }
    local _, active = crank:update(clock, lpos, pivot,
        rotate(rq, { X = 1, Y = 0, Z = 0 }), rotate(rq, { X = 0, Y = 1, Z = 0 }))
    if active ~= fishing_reeling then
        fishing_reeling = active
        log(active and "fishing crank: reel held" or "fishing crank: reel released")
    end
    input_active = active
end

-- Thumb-down proxy: controller forward points toward the floor while the hand is low and
-- in front of the torso. UEVR exposes controller orientation, not individual finger curls.
local function step_guard(pawn)
    if not cfg.guard_enabled or tool ~= "sickle" then
        guard_since = nil
        return false
    end
    local vr = uevr.params.vr
    local hand, hand_q = raw_pose(vr.get_right_controller_index())
    local head = raw_pose(vr.get_hmd_index())
    local forward = rotate(hand_q, { X = 0, Y = 0, Z = -1 })
    local dx, dy, dz = hand.X - head.X, hand.Y - head.Y, hand.Z - head.Z
    local positioned = dz < cfg.guard_front_z and dy >= cfg.guard_min_y and dy <= cfg.guard_max_y
        and math.abs(dx) <= cfg.guard_max_x
    local threshold = guarding and cfg.guard_exit_z or cfg.guard_enter_z
    local candidate = positioned and forward.Y <= threshold
    if candidate then
        guard_since = guard_since or clock
    else
        guard_since = nil
    end
    return candidate and clock - guard_since >= 0.10
end

local function dot_update(pawn)
    if not dot_setup(pawn) then return end
    local pcm = pawn.Controller.PlayerCameraManager
    local loc, rot = pcm:GetCameraLocation(), pcm:GetCameraRotation()
    local start = { X = loc.x, Y = loc.y, Z = loc.z }
    local finish = reticle.trace_end(start, rot.x, rot.y, dot.trace_length)
    local clear = { R = 0, G = 0, B = 0, A = 0 }
    local blocked = dot.ksl:LineTraceSingle(pawn, start, finish, 0, false, { pawn }, 0, dot.hit, true, clear, clear, 0)
    dot.last_launch_target = finish
    if blocked then
        local impact = dot.hit.ImpactPoint
        dot.last_launch_target = { X = impact.X or impact.x, Y = impact.Y or impact.y, Z = impact.Z or impact.z }
    end
    if not blocked then dot_show(false); return end   -- nothing to hook onto
    -- ImpactPoint is FVector_NetQuantize: UEVR returns it as a struct with X/Y/Z, not the
    -- x/y/z of a plain FVector (in game 17:51 this crashed the reticle). Accept either.
    local p = dot.hit.ImpactPoint
    local point = { X = p.X or p.x, Y = p.Y or p.y, Z = p.Z or p.z }
    local d = math.sqrt((point.X - start.X) ^ 2 + (point.Y - start.Y) ^ 2 + (point.Z - start.Z) ^ 2)
    dot.actor:K2_SetActorLocation(point, false, {}, true)
    local sc = reticle.dot_scale(d)
    dot.comp:SetWorldScale3D({ X = sc, Y = sc, Z = sc })
    dot_show(true)
end

-- Hook shots trace from PlayerController.GetPlayerViewPoint but launch at BP_HookGunEquipment's
-- Hook component. Compare the camera ray with the expected muzzle-to-trace-point launch vector.
-- GetControlRotation Controller.h:159; GetCameraRotation PlayerCameraManager.h:702;
-- K2_GetComponentLocation/Rotation SceneComponent.h:644/648; K2_GetComponentsByClass Actor.h:3762.
local last_aim_log = -1
local aim_err_logged = false
local function log_gun_aim(pawn)
    if clock - last_aim_log < 1.0 or tool_comp == nil then return end
    last_aim_log = clock
    local ok_rot, cr, vr = pcall(function()
        return pawn.Controller:GetControlRotation(), pawn.Controller.PlayerCameraManager:GetCameraRotation()
    end)
    if not ok_rot or cr == nil or vr == nil then return end -- mocks/actors without the player view
    local hook = hook_mesh(tool_comp:GetOwner())
    local ok_muzzle, muzzle = pcall(function() return hook and hook:K2_GetComponentLocation() end)
    if not ok_muzzle then muzzle = nil end
    local ctrl_yaw, ctrl_pitch = cr.Yaw or cr.y, cr.Pitch or cr.x
    local view_yaw, view_pitch = vr.Yaw or vr.y, vr.Pitch or vr.x
    if ctrl_yaw == nil or ctrl_pitch == nil or view_yaw == nil or view_pitch == nil then
        error("control or view rotation has no yaw/pitch fields")
    end
    local function wrap(a) a = (a + 180) % 360; return a - 180 end
    if muzzle ~= nil and dot.last_launch_target ~= nil then
        local mx, my, mz = muzzle.X or muzzle.x, muzzle.Y or muzzle.y, muzzle.Z or muzzle.z
        local target = dot.last_launch_target
        local dx, dy, dz = target.X - mx, target.Y - my, target.Z - mz
        local launch_yaw = math.deg(math.atan(dy, dx))
        local launch_pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
        log(string.format("hook aim: ctrl=%.0f/%.0f view=%.0f/%.0f view_minus_ctrl=%.0f/%.0f launch_minus_view=%.0f/%.0f",
            wrap(ctrl_yaw), wrap(ctrl_pitch), wrap(view_yaw), wrap(view_pitch),
            wrap(view_yaw - ctrl_yaw), wrap(view_pitch - ctrl_pitch),
            wrap(launch_yaw - view_yaw), wrap(launch_pitch - view_pitch)))
    else
        log(string.format("hook aim: ctrl=%.0f/%.0f view=%.0f/%.0f view_minus_ctrl=%.0f/%.0f muzzle=%s target=%s",
            wrap(ctrl_yaw), wrap(ctrl_pitch), wrap(view_yaw), wrap(view_pitch),
            wrap(view_yaw - ctrl_yaw), wrap(view_pitch - ctrl_pitch), tostring(muzzle ~= nil),
            tostring(dot.last_launch_target ~= nil)))
    end
end

local function step(pawn)
    if clock - last_cfg >= 1.0 then
        last_cfg = clock
        local ok, c = pcall(read_cfg)
        if ok then
            local changed = false
            for k, v in pairs(c) do if type(v) ~= "table" and cfg[k] ~= v then changed = true end end
            cfg = c
            if changed then rebuild() end
        end
    end
    if not cfg.enabled then deactivate(); return end
    -- Scan each engine tick: a queued press must not transfer to a newly equipped tool.
    local kind, comp = find_tool(pawn.Mesh)
    local id = identity(comp)
    if kind ~= tool or id ~= tool_id then
        log("tool in hand: " .. tostring(kind))
        rebuild()
    end
    tool, tool_comp, tool_id = kind, comp, id
    local out = hook_is_out()
    if out ~= hook_out then hook_out = out; log(out and "hook out: crank live" or "hook home: crank off"); rebuild() end
    input_active = tool == "melee" or tool == "sickle" or (tool == "hookgun" and hook_out)

    if tool == "hookgun" then
        local oka, erra = pcall(log_gun_aim, pawn)
        if not oka and not aim_err_logged then
            aim_err_logged = true
            log("gun aim diagnostic FAILED: " .. tostring(erra))
        end
    end
    if tool == "hookgun" and not hook_out and cfg.reticle then
        local okd, errd = pcall(dot_update, pawn)
        if not okd then dot_show(false); if not dot.err_logged then dot.err_logged = true; log("reticle FAILED: " .. tostring(errd)) end end
    else
        dot_show(false)
    end

    local vr = uevr.params.vr
    if tool == "hookgun" and hook_out then
        local lpos = raw_pose(vr.get_left_controller_index())
        local rpos, rq = raw_pose(vr.get_right_controller_index())
        local o = cfg.crank_offset
        local off = rotate(rq, { X = o.x, Y = o.y, Z = o.z })
        local pivot = { X = rpos.X + off.X, Y = rpos.Y + off.Y, Z = rpos.Z + off.Z }
        local clicks = crank:update(clock, lpos, pivot, rotate(rq, { X = 1, Y = 0, Z = 0 }), rotate(rq, { X = 0, Y = 1, Z = 0 }))
        if clicks > 0 then tapper:add(clicks); log("crank click x" .. clicks) end
        if clock - last_log >= 1.0 then
            last_log = clock
            local d = { X = lpos.X - pivot.X, Y = lpos.Y - pivot.Y, Z = lpos.Z - pivot.Z }
            log(string.format("crank hand_from_point=%.3fm", math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)))
        end
    elseif tool == "melee" or tool == "sickle" then
        local rpos = raw_pose(vr.get_right_controller_index())
        if swing:update(clock, rpos) then tapper:add(1); log("swing -> attack") end
    end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(_, delta)
    clock = clock + (delta or 0)
    local pawn = gameapi.local_pawn()
    local mode = pawn and modes.classify(gameapi.class_chain(pawn)) or nil
    local id = identity(pawn)
    if id ~= pawn_id then deactivate(); pawn_id = id end
    if mode ~= active_mode then deactivate(); active_mode = mode end
    refresh_cfg()
    if not cfg.enabled then deactivate(); return end
    if mode == "fishing" then
        local ok, err = pcall(step_fishing, pawn)
        if not ok then
            deactivate()
            if clock - fishing_gesture_error_last_log >= 1 then
                fishing_gesture_error_last_log = clock
                log("fishing gesture FAILED: " .. tostring(err) .. "; gesture input released")
            end
        end
        return
    end
    if mode == "boat" then
        if not supports_wheel_boat(pawn) then
            boat_controls_active = false
            if boat_neutral_lx ~= nil or boat_camera_state ~= nil then deactivate() end
            return
        end
        local ok, err = pcall(step_boat, pawn)
        if not ok then
            boat_axis_x, boat_axis_y, boat_throttle = 0, 0, 0
            boat_neutral_lx, boat_neutral_ly, boat_neutral_ry, boat_neutral_rz = nil, nil, nil, nil
            boat_throttle_neutral_hand, boat_throttle_forward = nil, nil
            boat_steer_filtered, boat_steer_last_update = 0, nil
            boat_steer_detent, boat_steer_arc_active = 0, false
            boat_controls_active = boat_camera_state == "first_person"
            if clock - boat_gesture_error_last_log >= 1 then
                boat_gesture_error_last_log = clock
                log("boat gesture FAILED: " .. tostring(err) .. "; first-person axes held neutral")
            end
        end
        return
    end
    if mode == "crafting" then
        local ok, err = pcall(step_crafting)
        if not ok then log("craft cursor FAILED: " .. tostring(err)) end
        return
    end
    if mode ~= "walking" then
        if tool ~= nil then log("tool in hand: nil (left walking mode)") end
        deactivate()
        return
    end
    local ok, err = pcall(step, pawn)
    if not ok then deactivate(); log("FAILED: " .. tostring(err)) end
    if ok then
        local okg, blocked = pcall(step_guard, pawn)
        if okg then
            local was_guarding = guarding
            if blocked ~= was_guarding then
                log(blocked and "guard held" or "guard released")
                pcall(function()
                    local aim = blocked and 1 or math.floor(cfg.aim_method)
                    uevr.params.vr.set_mod_value("VR_AimMethod", string.format("%d", aim))
                    log("guard aim method: " .. (blocked and "head" or tostring(aim)))
                end)
                rebuild()
                if was_guarding then guard_release_until = clock + 0.1 end
            end
            guarding = blocked
            input_active = input_active or blocked
        else
            guarding = false
            log("guard gesture FAILED: " .. tostring(blocked))
        end
    end
end)

-- Copy the steering-wheel actor's post-game rotation to its separately spawned cosmetic,
-- matching BP_ShipSteeringWheel.ReceiveTick.
-- Run after the boat Blueprint tick so its cosmetic tick cannot leave the overlay behind.
uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function(_, view_index)
    if view_index ~= 0 or active_mode ~= "boat" then return end
    local pawn = gameapi.local_pawn()
    if pawn ~= nil and supports_wheel_boat(pawn) then sync_cosmetic_wheel(pawn) end
end)

-- The virtual press: while a tap is down the right trigger reads fully pressed; during the gap
-- between taps it reads released, so taps stay distinct even over a held trigger. Otherwise the
-- player's own trigger passes through untouched.
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    if user_index ~= 0 or state == nil then return end
    -- BP_SmallBoat_V2 routes IA_BoatLook straight into AddControllerYawInput/PitchInput.
    -- In the tracked first-person helm, right-stick camera rotation turns the boat-relative
    -- controller frame underneath the hands. Keep HMD look active and suppress only this
    -- gamepad look axis until the player returns to third-person.
    if active_mode == "boat" and boat_camera_state == "first_person" then
        state.Gamepad.sThumbRX, state.Gamepad.sThumbRY = 0, 0
        if not boat_camera_look_suppressed then
            boat_camera_look_suppressed = true
            log("boat first-person right-stick look suppressed; use head tracking to look")
        end
    else
        boat_camera_look_suppressed = false
    end
    if fishing_fish_id ~= nil then
        local gamepad = state.Gamepad
        if fishing_axis_x ~= 0 then gamepad.sThumbLX = math.floor(fishing_axis_x * 32767) end
        if fishing_qte_tag == "QTE.Type.DirectionalDrag" and (fishing_axis_x ~= 0 or fishing_axis_y ~= 0) then
            gamepad.sThumbLX = math.floor(fishing_axis_x * 32767)
            gamepad.sThumbLY = math.floor(fishing_axis_y * 32767)
        end
    end
    if boat_controls_active then
        state.Gamepad.sThumbLX = math.floor(boat_axis_x * 32767)
        state.Gamepad.sThumbLY = math.floor(boat_axis_y * 32767)
        return
    end
    if guarding then
        -- IMC_CharacterMapping: SecondaryUse is the left trigger. The sickle block ability
        -- waits for input release; do not send PrimaryUse here or this gesture attacks instead.
        state.Gamepad.bLeftTrigger = 255
        return
    end
    if fishing_reeling then
        state.Gamepad.bRightTrigger = 255
        return
    end
    if fishing_cast_held then
        state.Gamepad.bRightTrigger = 255
        return
    end
    if clock < fishing_hook_set_until then
        state.Gamepad.bRightTrigger = 255
        return
    end
    if clock < guard_release_until then state.Gamepad.bLeftTrigger = 0; return end
    if not input_active then return end
    local down = tapper:pressed(clock)
    if down then state.Gamepad.bRightTrigger = 255
    elseif tapper.phase == "gap" then state.Gamepad.bRightTrigger = 0 end
end)

uevr.sdk.callbacks.on_script_reset(function()
    deactivate()
    if dot.actor ~= nil then pcall(function() dot.actor:K2_DestroyActor() end) end
    tool, tool_comp, hook_out = nil, nil, false
end)
