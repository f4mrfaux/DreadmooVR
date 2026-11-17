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
    crank_r_min = 0.04, crank_r_max = 0.25, crank_min_deg_s = 180, crank_step_deg = 90,
    swing_min_m_s = 2.0, swing_frames = 3, swing_cooldown_s = 0.4,
    tap_hold = 0.06, tap_gap = 0.06,
}
local cfg = DEFAULTS
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
        crank_min_deg_s = num(g.crank_min_deg_s, 0, 2000, d.crank_min_deg_s), crank_step_deg = num(g.crank_step_deg, 10, 360, d.crank_step_deg),
        swing_min_m_s = num(g.swing_min_m_s, 0.5, 10, d.swing_min_m_s), swing_frames = num(g.swing_frames, 1, 30, d.swing_frames),
        swing_cooldown_s = num(g.swing_cooldown_s, 0, 5, d.swing_cooldown_s),
        tap_hold = num(g.tap_hold, 0.01, 0.5, d.tap_hold), tap_gap = num(g.tap_gap, 0.01, 0.5, d.tap_gap),
    }
end

local crank, swing, tapper
local function rebuild()
    crank = gestures.crank({ r_min = cfg.crank_r_min, r_max = cfg.crank_r_max, min_deg_s = cfg.crank_min_deg_s, step_deg = cfg.crank_step_deg })
    swing = gestures.swing({ min_m_s = cfg.swing_min_m_s, frames = cfg.swing_frames, cooldown_s = cfg.swing_cooldown_s })
    tapper = gestures.tapper({ hold = cfg.tap_hold, gap = cfg.tap_gap })
end
rebuild()

-- Raw SteamVR pose (metres, quaternion). Rotate a local vector by the pose's rotation.
local function raw_pose(index)
    local p, q = UEVR_Vector3f.new(), UEVR_Quaternionf.new()
    uevr.params.vr.get_pose(index, p, q)
    return { X = p.x, Y = p.y, Z = p.z }, { x = q.x, y = q.y, z = q.z, w = q.w }
end
local function rotate(q, v)   -- v' = q v q*
    local x, y, z, w = q.x, q.y, q.z, q.w
    local tx, ty, tz = 2 * (y * v.Z - z * v.Y), 2 * (z * v.X - x * v.Z), 2 * (x * v.Y - y * v.X)
    return { X = v.X + w * tx + (y * tz - z * ty), Y = v.Y + w * ty + (z * tx - x * tz), Z = v.Z + w * tz + (x * ty - y * tx) }
end

-- Which tool is in hand: the game attaches it to CharacterMesh0 at HookSimple / KnifeSocket; with
-- items_follow_hands it sits one level down, on the VR arms' Body (itself a child of the mesh).
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
            if kind then return kind, c end
            if depth < 2 then
                local k2, c2 = scan(c, depth + 1)
                if k2 then return k2, c2 end
            end
        end
        return nil
    end
    return scan(mesh, 1)
end

local clock, last_scan, last_cfg = 0, -1, -1
local tool, tool_comp, hook_out = nil, nil, false
local last_log = 0

local function hook_is_out()
    if tool ~= "hookgun" or tool_comp == nil then return false end
    local ok, out = pcall(function()
        local gun = tool_comp:GetOwner()
        return gun ~= nil and gun.Hook ~= nil and not gun.Hook:IsVisible()
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

local function dot_show(on)
    if dot.actor ~= nil and on ~= dot.shown then
        dot.shown = on
        dot.actor:SetActorHiddenInGame(not on)
        if cfg.hide_game_dot then set_game_dot(on and 0 or 1) end
    end
end

local function dot_update(pawn)
    if not dot_setup(pawn) then return end
    local pcm = pawn.Controller.PlayerCameraManager
    local loc, rot = pcm:GetCameraLocation(), pcm:GetCameraRotation()
    local start = { X = loc.x, Y = loc.y, Z = loc.z }
    local finish = reticle.trace_end(start, rot.x, rot.y, dot.trace_length)
    local clear = { R = 0, G = 0, B = 0, A = 0 }
    local blocked = dot.ksl:LineTraceSingle(pawn, start, finish, 0, false, { pawn }, 0, dot.hit, true, clear, clear, 0)
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
    if not cfg.enabled then return end
    if clock - last_scan >= 0.5 then
        last_scan = clock
        local kind, comp = find_tool(pawn.Mesh)
        if kind ~= tool then log("tool in hand: " .. tostring(kind)); crank:reset() end
        tool, tool_comp = kind, comp
    end
    local out = hook_is_out()
    if out ~= hook_out then hook_out = out; log(out and "hook out: crank live" or "hook home: crank off"); crank:reset() end

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
    elseif tool == "melee" then
        local rpos = raw_pose(vr.get_right_controller_index())
        if swing:update(clock, rpos) then tapper:add(1); log("swing -> attack") end
    end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(_, delta)
    clock = clock + (delta or 0)
    local pawn = gameapi.local_pawn()
    local mode = pawn and modes.classify(gameapi.class_chain(pawn)) or nil
    if mode ~= "walking" then
        dot_show(false)
        if tool ~= nil then log("tool in hand: nil (left walking mode)") end
        tool, tool_comp, hook_out = nil, nil, false
        return
    end
    local ok, err = pcall(step, pawn)
    if not ok then log("FAILED: " .. tostring(err)) end
end)

-- The virtual press: while a tap is down the right trigger reads fully pressed; during the gap
-- between taps it reads released, so taps stay distinct even over a held trigger. Otherwise the
-- player's own trigger passes through untouched.
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    if tapper == nil then return end
    local down = tapper:pressed(clock)
    if down then state.Gamepad.bRightTrigger = 255
    elseif tapper.phase == "gap" then state.Gamepad.bRightTrigger = 0 end
end)

uevr.sdk.callbacks.on_script_reset(function()
    if dot.shown then set_game_dot(1) end
    if dot.actor ~= nil then pcall(function() dot.actor:K2_DestroyActor() end) end
    tool, tool_comp, hook_out = nil, nil, false
end)
