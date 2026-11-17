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
log("loaded")

local TUNING_FILE = (lib_dir():gsub("scripts[/\\]lib[/\\]$", "")) .. "dreadmoorvr_arms_tuning.lua"
-- Defaults; the tuning file's `gestures = { ... }` table overrides any of them live.
local DEFAULTS = {
    enabled = true,
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
    tool, tool_comp, hook_out = nil, nil, false
end)
