-- Pairs SteamVR action states with the gamepad UEVR hands the game, so normal play builds the
-- physical-button -> action -> Xbox-button table without a scripted button test.
-- Pure: the probe feeds it; no UEVR calls here.
local inputmap = {}
inputmap.__index = inputmap

function inputmap.new()
    return setmetatable({ last = nil, seen = {}, order = {} }, inputmap)
end

-- actives: list of "Action@L|R" strings that are down. buttons: XInput wButtons the game got.
-- hmd/ctl: UEVR's is_hmd_active / is_using_controllers. Returns a log line when anything
-- changed, else nil.
function inputmap:observe(actives, buttons, hmd, ctl)
    local acts = {}
    for i, a in ipairs(actives) do acts[i] = a end
    table.sort(acts)
    local line = string.format("act=%s pad=0x%04X hmd=%d ctl=%d",
        #acts > 0 and table.concat(acts, ",") or "-", buttons, hmd and 1 or 0, ctl and 1 or 0)
    if line == self.last then return nil end
    self.last = line

    if #acts == 1 then
        local key = acts[1] .. "->" .. (ctl and string.format("0x%04X", buttons) or "gated")
        if not self.seen[key] then
            self.seen[key] = 0
            self.order[#self.order + 1] = key
        end
        self.seen[key] = self.seen[key] + 1
    end
    return line
end

-- "Action@R->0x1000 x2; ..." in first-seen order.
function inputmap:summary()
    local parts = {}
    for _, key in ipairs(self.order) do parts[#parts + 1] = key .. " x" .. self.seen[key] end
    return table.concat(parts, "; ")
end

return inputmap
