-- DreadmoorVR bridge settings. UEVR autoloads the gameplay scripts in scripts\; shared modules
-- live in scripts\lib and are loaded by the scripts that use them.

local function log(msg)
    pcall(function() uevr.params.functions.log_info("[DreadmoorVR] " .. msg) end)
end

log("bridge settings loaded")

-- UEVR writes its in-memory settings back to config.txt on exit, so edits made to that file
-- while the game runs are lost. The bridge applies the settings it depends on at every load.
local UEVR_SETTINGS = {
    UI_FollowView = "true", -- HUD follows the head
    VR_DPadShifting = "false", -- Bob: left X acted as D-pad (M1 run)
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
