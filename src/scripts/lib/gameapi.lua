-- The only place game names appear. Everything returns nil (or an empty table) when something
-- is missing, so a game update degrades the mod instead of crashing it.
local gameapi = {}

-- Base classes that identify each mode. The first match walking down the class chain wins.
gameapi.MODE_CLASSES = {
    { "DrdFishingControllerBase", "fishing" },
    { "BP_CraftController_C", "crafting" },
    { "DrdShipBase", "boat" },
    { "BP_DiverCharacter_C", "diving" },
    { "DrdPlayerCharacter", "walking" },
}

local function name_of(cls)
    local ok, n = pcall(function() return cls:get_fname():to_string() end)
    if ok and n then return n end
    ok, n = pcall(function() return cls:get_short_name() end)
    return ok and n or "?"
end

local function super_of(cls)
    for _, m in ipairs({ "get_super_struct", "get_super" }) do
        local f = cls[m]
        if f then
            local ok, s = pcall(f, cls)
            if ok then return s end
        end
    end
    return nil
end

-- Short class names of obj, most-derived first.
function gameapi.class_chain(obj)
    local out = {}
    if obj == nil then return out end
    local ok, cls = pcall(function() return obj:get_class() end)
    if not ok then return out end
    while cls ~= nil and #out < 32 do
        out[#out + 1] = name_of(cls)
        cls = super_of(cls)
    end
    return out
end

function gameapi.local_pawn()
    if not uevr then return nil end
    local ok, p = pcall(function() return uevr.api:get_local_pawn(0) end)
    return ok and p or nil
end

function gameapi.world()
    if not uevr then return nil end
    local ok, w = pcall(function()
        local engine = uevr.api:get_engine()
        return engine.GameViewport.World
    end)
    return ok and w or nil
end

return gameapi
