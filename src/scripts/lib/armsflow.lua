-- Arms lifecycle (pure): load the class via the plugin (same request/retry rules as m1flow),
-- spawn once on foot, then hide off foot, show on return, reattach when the walking pawn changes.
-- step() returns "request", "spawn", "hide", "show", "reattach" or nil.
-- lost(): the arms actor is gone (it can die with a replaced pawn); the flow reloads the class and
-- spawns fresh arms on foot, up to MAX_RESPAWNS times, then stops instead of looping.
local armsflow = {}
armsflow.__index = armsflow
armsflow.MAX_RESPAWNS = 5

local function m1flow_new()
    local loaded = package and package.loaded and package.loaded.m1flow
    if loaded then return loaded.new() end
    return require("m1flow").new()
end

local function new_load(deps)
    local m1 = type(deps) == "table" and deps.m1flow or nil
    return m1 and m1.new() or m1flow_new()
end

function armsflow.new(deps)
    return setmetatable({ deps = deps, load = new_load(deps), status = "loading",
        visible = true, pawn = nil, reason = nil }, armsflow)
end

-- now: seconds; mode: "walking", "boat", or another mode name or nil; pawn: identity.
function armsflow:step(now, mode, pawn)
    if self.status == "loading" then
        local action = self.load:step(now, mode == "walking")
        if self.load.status == "fail" or self.load.status == "no_reply" then
            self.status, self.reason = self.load.status, self.load.reason
        end
        if action == "spawn" then self.pawn = pawn end
        return action
    end
    if self.status ~= "active" then return nil end

    local visible_mode = mode == "walking" or mode == "boat"
    if mode == "walking" and pawn ~= self.pawn then
        self.pawn = pawn
        self.visible = true
        return "reattach"
    end
    if visible_mode and not self.visible then self.visible = true; return "show" end
    if not visible_mode and self.visible then self.visible = false; return "hide" end
    return nil
end

function armsflow:on_reply(data)
    self.load:on_reply(data)
    if self.load.status == "fail" then self.status, self.reason = "fail", self.load.reason end
end

function armsflow:lost()
    self.respawns = (self.respawns or 0) + 1
    if self.respawns > armsflow.MAX_RESPAWNS then
        self.status, self.reason = "fail", "arms lost " .. self.respawns .. " times"
    else
        -- The engine can unload BP_VRArms with the old pawn (in game 2026-11-17 16:42), so go
        -- through the whole load again: plugin request, reply, spawn.
        self.load, self.status, self.visible = new_load(self.deps), "loading", true
    end
end

function armsflow:spawned(ok)
    self.load:spawned(ok)
    self.status = ok and "active" or "spawn_failed"
end

return armsflow
