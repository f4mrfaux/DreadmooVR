-- DreadmoorVR bridge entry point. UEVR autoloads every scripts\*.lua; the modules sit in
-- scripts\lib so they are only loaded through require from here.

-- UEVR's Lua has no `debug` library, so the profile folder comes from UEVR itself.
local function log(msg)
    pcall(function() uevr.params.functions.log_info("[DreadmoorVR] " .. msg) end)
end

-- UEVR puts "<profile>\scripts/?.lua" on package.path (seen in M1 logs); get_persistent_dir()
-- failed there. Derive scripts\lib from that entry, then fall back to get_persistent_dir.
local function find_lib_dir()
    if package and package.path then
        for entry in package.path:gmatch("[^;]+") do
            local base = entry:match("^(.-[/\\]scripts)[/\\]%?%.lua$")
            if base then return base .. "\\lib\\" end
        end
    end
    local ok, p = pcall(function() return uevr.params.functions.get_persistent_dir() end)
    if ok and type(p) == "string" then return p .. "\\scripts\\lib\\" end
    return ".\\scripts\\lib\\"
end
local LIB_DIR = find_lib_dir()

-- require when the package library is there; loadfile otherwise. Logs which one worked.
local load_method
local loaded = {}
local function load_module(name)
    if package and package.path and require then
        local pat = LIB_DIR .. "?.lua"
        if not package.path:find(pat, 1, true) then package.path = pat .. ";" .. package.path end
        local ok, mod = pcall(require, name)
        if ok then load_method = "require"; loaded[name] = mod; return mod end
        log("require(" .. name .. ") failed: " .. tostring(mod))
    end
    local chunk, err = loadfile(LIB_DIR .. name .. ".lua")
    if not chunk then error("cannot load " .. name .. ": " .. tostring(err)) end
    load_method = "loadfile"
    loaded[name] = chunk(loaded)
    return loaded[name]
end

local gameapi = load_module("gameapi")
local modes = load_module("modes")
local armsloader = load_module("armsloader")

log("main.lua loaded; modules via " .. tostring(load_method) .. " from " .. LIB_DIR)

-- UEVR writes its in-memory settings back to config.txt on exit, so edits made to that file
-- while the game runs are lost. The bridge applies the settings it depends on at every load.
local UEVR_SETTINGS = {
    UI_FollowView = "true", -- HUD follows the head
}
local AIM_HEAD = 1 -- VR_AimMethod: 0 game, 1 head, 2 right hand, 3 left hand

for key, value in pairs(UEVR_SETTINGS) do
    local ok, err = pcall(function() uevr.params.vr.set_mod_value(key, value) end)
    log("setting " .. key .. "=" .. value .. (ok and "" or (" FAILED: " .. tostring(err))))
end
do
    local ok, err = pcall(function() uevr.params.vr.set_aim_method(AIM_HEAD) end)
    log("aim method head" .. (ok and "" or (" FAILED: " .. tostring(err))))
end

-- M1: prove the pak loads. Two seconds after the first walking pawn, spawn the probe
-- cube 150 cm in front of the view. Runs once per script load.
local M1_CLASS = "/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C"
local m1 = { done = false, walking_for = 0 }

local function m1_spawn(pawn)
    local cls, method, notes = armsloader.load_class(M1_CLASS)
    if cls == nil then
        log("M1 load FAILED for " .. M1_CLASS .. " :: " .. tostring(notes))
        return
    end
    log("M1 class loaded via " .. method .. " (" .. tostring(notes) .. ")")

    local ok, err = pcall(function()
        local xf = pawn:K2_GetActorTransform()
        local actor = armsloader.spawn(cls, xf)
        if actor == nil then error("spawn returned nil") end
        local yaw = pawn.Controller:GetControlRotation().Yaw
        local loc = pawn:K2_GetActorLocation()
        local p = armsloader.ahead(loc, yaw, 150)
        loc.X, loc.Y, loc.Z = p.X, p.Y, p.Z
        actor:K2_TeleportTo(loc, pawn:K2_GetActorRotation())
        log(string.format("M1 spawned probe at %.0f %.0f %.0f", p.X, p.Y, p.Z))
    end)
    if not ok then log("M1 spawn FAILED: " .. tostring(err)) end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(_, delta)
    if m1.done then return end
    local pawn = gameapi.local_pawn()
    if pawn == nil or modes.classify(gameapi.class_chain(pawn)) ~= "walking" then
        m1.walking_for = 0
        return
    end
    m1.walking_for = m1.walking_for + delta
    if m1.walking_for >= 2 then
        m1.done = true
        m1_spawn(pawn)
    end
end)
