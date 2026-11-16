-- M1 decision logic (pure): when to ask DreadmoorVR.dll for the probe class, when to spawn.
-- Asks after 2 s of walking, retries every 3 s until the plugin replies (max 10 requests),
-- spawns once on an "ok" reply.
local m1flow = {}
m1flow.__index = m1flow

local WALK_DELAY, RETRY, MAX_REQUESTS = 2.0, 3.0, 10

function m1flow.new()
    return setmetatable({ walk_start = nil, last_request = nil, requests = 0,
        status = "waiting", reason = nil }, m1flow)
end

-- now: seconds; walking: boolean. Returns "request", "spawn" or nil.
function m1flow:step(now, walking)
    if self.status == "ok" then self.status = "spawning"; return "spawn" end
    if self.status ~= "waiting" and self.status ~= "requested" then return nil end
    if not walking then self.walk_start = nil; return nil end
    if self.walk_start == nil then self.walk_start = now end
    if now - self.walk_start < WALK_DELAY then return nil end
    if self.last_request ~= nil and now - self.last_request < RETRY then return nil end
    if self.requests >= MAX_REQUESTS then self.status = "no_reply"; return nil end
    self.requests = self.requests + 1
    self.last_request = now
    self.status = "requested"
    return "request"
end

-- data: "ok|<path>" or "fail|<reason>" from the plugin's dreadmoorvr_class_loaded event.
function m1flow:on_reply(data)
    local kind, rest = tostring(data):match("^(%a+)|(.*)$")
    if kind == "ok" then self.status = "ok"; self.path = rest
    else self.status = "fail"; self.reason = rest or tostring(data) end
end

function m1flow:spawned(ok)
    self.status = ok and "done" or "spawn_failed"
end

return m1flow
