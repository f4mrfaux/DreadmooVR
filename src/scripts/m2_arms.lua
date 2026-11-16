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
local stats = armstats.new()
log("loaded")

local actor = nil
local sample_err_logged = false

-- Live tuning: <profile>\dreadmoorvr_arms_tuning.lua, reloaded every second, pushed into BP_VRArms
-- float variables (names from tuning.flatten). Bad values fall back to defaults (tuning.merge).
local TUNING_FILE = (lib_dir():gsub("scripts[/\\]lib[/\\]$", "")) .. "dreadmoorvr_arms_tuning.lua"
local last_tuning_check, applied = -1, {}
local function apply_tuning(now)
    if now - last_tuning_check < 1.0 then return end
    last_tuning_check = now
    local chunk = loadfile(TUNING_FILE, "t", {})
    local ok, user = false, nil
    if chunk then ok, user = pcall(chunk) end
    local flat = tuning.flatten(tuning.merge(ok and user or nil))
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

local function sample_arms(pawn, now)
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
    if now - last_summary >= SUMMARY_S then
        last_summary = now
        log("arms summary " .. stats:summary("L") .. " | " .. stats:summary("R"))
    end
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
    actor.Body:K2_AttachToComponent(pawn.Mesh, "None", SNAP_TO_TARGET, SNAP_TO_TARGET, SNAP_TO_TARGET, false)
    for _, bone in ipairs(GAME_BONES_TO_HIDE) do pawn.Mesh:HideBoneByName(bone, PBO_NONE) end
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
    local action = flow:step(clock, mode, pawn and tostring(pawn) or nil)
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
        log("reattached to new walking pawn" .. (ok and "" or (" FAILED: " .. tostring(err))))
    end
    if flow.status == "active" and actor ~= nil then
        local okt, errt = pcall(apply_tuning, clock)
        if not okt and not sample_err_logged then sample_err_logged = true; log("tuning FAILED: " .. tostring(errt)) end
    end
    if flow.status == "active" and actor ~= nil and mode == "walking" then
        local ok, err = pcall(sample_arms, pawn, clock)
        if not ok and not sample_err_logged then sample_err_logged = true; log("harness FAILED: " .. tostring(err)) end
    end
    if flow.status ~= before and (flow.status == "fail" or flow.status == "no_reply" or flow.status == "spawn_failed") then
        log("stopped: " .. flow.status .. (flow.reason and (" - " .. flow.reason) or ""))
    end
end)

uevr.sdk.callbacks.on_script_reset(function()
    restore_game_body()
    if actor ~= nil then pcall(function() actor:K2_DestroyActor() end) end
    actor = nil
end)
