-- Arms lifecycle (pure): load the class via the plugin (same request/retry rules as m1flow),
-- spawn once on foot, then hide off foot, show on return, reattach when the walking pawn changes.
-- step() returns "request", "spawn", "hide", "show", "reattach" or nil.
local armsflow = {}
armsflow.__index = armsflow

local function m1flow_new()
    local loaded = package and package.loaded and package.loaded.m1flow
    if loaded then return loaded.new() end
    return require("m1flow").new()
end

function armsflow.new(deps)
    local m1 = type(deps) == "table" and deps.m1flow or nil
    return setmetatable({ load = m1 and m1.new() or m1flow_new(), status = "loading",
        visible = true, pawn = nil, reason = nil }, armsflow)
end

-- now: seconds; mode: "walking" or another mode name or nil; pawn: an identity for the pawn.
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

    local walking = mode == "walking"
    if walking and pawn ~= self.pawn then
        self.pawn = pawn
        self.visible = true
        return "reattach"
    end
    if walking and not self.visible then self.visible = true; return "show" end
    if not walking and self.visible then self.visible = false; return "hide" end
    return nil
end

function armsflow:on_reply(data)
    self.load:on_reply(data)
    if self.load.status == "fail" then self.status, self.reason = "fail", self.load.reason end
end

function armsflow:spawned(ok)
    self.load:spawned(ok)
    self.status = ok and "active" or "spawn_failed"
end

return armsflow
