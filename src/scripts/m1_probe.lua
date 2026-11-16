-- M1 probe: proves a custom asset from the mod pak loads and spawns in Dreadmoor.
-- DreadmoorVR.dll loads the class (UEVR Lua cannot marshal soft references); this script asks for
-- it, then spawns BP_PakProbe 150 cm ahead of the walking pawn. Nothing else; no gameplay changes.
local PATH = "/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C"

local function log(msg)
    pcall(function() uevr.params.functions.log_info("[DreadmoorVR M1] " .. msg) end)
end

local function lib_dir()
    if package and package.path then
        for entry in package.path:gmatch("[^;]+") do
            local base = entry:match("^(.-[/\\]scripts)[/\\]%?%.lua$")
            if base then return base .. "\\lib\\" end
        end
    end
    return nil
end

local loaded = {}
local function load_module(name)
    local chunk, err = loadfile((lib_dir() or ".\\scripts\\lib\\") .. name .. ".lua")
    if not chunk then error("cannot load " .. name .. ": " .. tostring(err)) end
    loaded[name] = chunk(loaded)
    return loaded[name]
end

local gameapi = load_module("gameapi")
local modes = load_module("modes")
local armsloader = load_module("armsloader")
local flow = load_module("m1flow").new()
log("loaded")

local clock = 0

local function spawn(pawn)
    local cls = uevr.api:find_uobject("BlueprintGeneratedClass " .. PATH)
    if cls == nil then log("spawn FAILED: class not in memory after plugin load"); return false end
    local ok, err = pcall(function()
        local actor = armsloader.spawn(cls, pawn:K2_GetActorTransform())
        if actor == nil then error("spawn returned nil") end
        local yaw = pawn.Controller:GetControlRotation().Yaw
        local loc = pawn:K2_GetActorLocation()
        local p = armsloader.ahead(loc, yaw, 150)
        loc.X, loc.Y, loc.Z = p.X, p.Y, p.Z
        actor:K2_TeleportTo(loc, pawn:K2_GetActorRotation())
        log(string.format("spawned BP_PakProbe at %.0f %.0f %.0f", p.X, p.Y, p.Z))
    end)
    if not ok then log("spawn FAILED: " .. tostring(err)) end
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
    local walking = pawn ~= nil and modes.classify(gameapi.class_chain(pawn)) == "walking"
    local before = flow.status
    local action = flow:step(clock, walking)
    if action == "request" then
        log("requesting class from DreadmoorVR.dll (attempt " .. flow.requests .. ")")
        pcall(function() uevr.api:dispatch_custom_event("dreadmoorvr_request_class", PATH) end)
    elseif action == "spawn" then
        flow:spawned(spawn(pawn))
    end
    if flow.status ~= before and (flow.status == "fail" or flow.status == "no_reply") then
        log("stopped: " .. flow.status .. (flow.reason and (" - " .. flow.reason) or ""))
    end
end)
