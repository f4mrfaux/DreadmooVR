-- Boat axes are throttle/rudder, not a direction relative to the head or gun hand.
-- Snapshot UEVR's settings on entry and restore them on exit (including script reset).
local boatcontrols = {}
boatcontrols.__index = boatcontrols
local OVERRIDES = {
    VR_MovementOrientation = "0",
    VR_AimMethod = "0",
    VR_RoomscaleMovement = "false",
}

function boatcontrols.new(get, set)
    return setmetatable({ get = get, set = set, saved = {}, applied = {} }, boatcontrols)
end

function boatcontrols:update(mode)
    for key, value in pairs(OVERRIDES) do
        if mode == "boat" then
            if self.saved[key] == nil then
                local before = self.get(key)
                assert(type(before) == "string" and before ~= "", "cannot read " .. key)
                self.saved[key] = before
            end
            if not self.applied[key] then
                self.set(key, value)
                self.applied[key] = true
            end
        elseif self.saved[key] ~= nil then
            self.set(key, self.saved[key])
            self.saved[key], self.applied[key] = nil, nil
        end
    end
end

return boatcontrols
