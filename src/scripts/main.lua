-- DreadmoorVR bridge entry point. UEVR autoloads every scripts\*.lua; the modules sit in
-- scripts\lib so they are only loaded through require from here.

local function script_dir()
    local src = debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*)[/\\][^/\\]*$")
    if dir then return dir end
    local ok, p = pcall(function() return uevr.params.functions.get_persistent_dir() end)
    return ok and p and (p .. "\\scripts") or "."
end

local LIB = script_dir() .. "\\lib\\?.lua"
if not package.path:find(LIB, 1, true) then package.path = LIB .. ";" .. package.path end

local gameapi = require("gameapi")
local modes = require("modes")
local armsloader = require("armsloader")

local function log(msg)
    pcall(function() uevr.params.functions.log_info("[DreadmoorVR] " .. msg) end)
end

log("main.lua loaded; lib path " .. LIB)

-- M1: prove the pak loads. Two seconds after the first walking pawn, spawn the probe
-- cube 150 cm in front of the view. Runs once per script load.
local M1_CLASS = "/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C"
local m1 = { done = false, walking_for = 0 }

local function m1_spawn(pawn)
    local cls, method = armsloader.load_class(M1_CLASS)
    if cls == nil then
        log("M1 load FAILED for " .. M1_CLASS .. " (find_uobject and LoadClassAsset_Blocking both nil)")
        return
    end
    log("M1 class loaded via " .. method)

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
