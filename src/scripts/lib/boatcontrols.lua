-- Boat axes are throttle/rudder, not a direction relative to the head or gun hand.
-- Snapshot UEVR's settings on entry and restore them on exit (including script reset).
local boatcontrols = {}
boatcontrols.__index = boatcontrols
local OVERRIDES = {
    VR_MovementOrientation = "0",
    VR_AimMethod = "0",
    VR_RoomscaleMovement = "false",
}

function boatcontrols.new(get, set, on_error)
    return setmetatable({ get = get, set = set, on_error = on_error,
        saved = {}, applied = {}, errors = {} }, boatcontrols)
end

local function report(self, key, message)
    if self.errors[key] == message then return end
    self.errors[key] = message
    if self.on_error then pcall(self.on_error, key, message) end
end

function boatcontrols:update(mode)
    for key, value in pairs(OVERRIDES) do
        if mode == "boat" then
            local can_apply = true
            if self.saved[key] == nil then
                local ok, before = pcall(self.get, key)
                if not ok then
                    report(self, key, "read failed: " .. tostring(before))
                    can_apply = false
                elseif type(before) ~= "string" or before == "" then
                    report(self, key, "read returned " .. type(before) .. " (expected a non-empty string)")
                    can_apply = false
                else
                    self.saved[key] = before
                end
            end
            if can_apply and self.saved[key] ~= nil and not self.applied[key] then
                local ok, err = pcall(self.set, key, value)
                if ok then
                    self.applied[key] = true
                    self.errors[key] = nil
                else
                    report(self, key, "set failed: " .. tostring(err))
                end
            end
        elseif self.saved[key] ~= nil then
            local ok, err = pcall(self.set, key, self.saved[key])
            if ok then
                self.saved[key], self.applied[key], self.errors[key] = nil, nil, nil
            else
                report(self, key, "restore failed: " .. tostring(err))
            end
        end
    end
end

return boatcontrols
