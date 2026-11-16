-- Loads a Blueprint class from the mod pak and spawns it. Every UEVR call is wrapped so a
-- failure returns nil and a reason instead of throwing into UEVR's tick.
local armsloader = {}

local ESCAPE_COLLISION_ALWAYS_SPAWN = 1 -- ESpawnActorCollisionHandlingMethod::AlwaysSpawn
local SCALE_MULTIPLY_WITH_ROOT = 1      -- ESpawnActorScaleMethod::MultiplyWithRoot

local function static(class_path)
    local cls = uevr.api:find_uobject("Class " .. class_path)
    return cls and cls:get_class_default_object() or nil
end

-- Returns class, method. method is "find_uobject", "LoadClassAsset_Blocking" or "none".
-- path is the full object path, e.g. "/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C".
function armsloader.load_class(path)
    local ok, cls = pcall(function()
        return uevr.api:find_uobject("BlueprintGeneratedClass " .. path)
    end)
    if ok and cls then return cls, "find_uobject" end

    ok, cls = pcall(function()
        local ksl = static("/Script/Engine.KismetSystemLibrary")
        local soft_path = ksl:MakeSoftClassPath(path)
        local soft_ref = ksl:Conv_SoftClassPathToSoftClassRef(soft_path)
        return ksl:LoadClassAsset_Blocking(soft_ref)
    end)
    if ok and cls then return cls, "LoadClassAsset_Blocking" end

    return nil, "none"
end

local function current_world()
    local engine = uevr.api:get_engine()
    return engine.GameViewport.World
end

-- Spawns class at transform (an FTransform struct from the game). Returns the actor or nil.
function armsloader.spawn(class, transform)
    if class == nil then return nil end
    local ok, actor = pcall(function()
        local gs = static("/Script/Engine.GameplayStatics")
        local world = current_world()
        local a = gs:BeginDeferredActorSpawnFromClass(world, class, transform,
            ESCAPE_COLLISION_ALWAYS_SPAWN, nil, SCALE_MULTIPLY_WITH_ROOT)
        if a == nil then return nil end
        return gs:FinishSpawningActor(a, transform, SCALE_MULTIPLY_WITH_ROOT)
    end)
    return ok and actor or nil
end

-- Point dist cm ahead of loc along yaw (degrees, Unreal: 0 = +X, 90 = +Y). Pure.
function armsloader.ahead(loc, yaw_deg, dist)
    local r = math.rad(yaw_deg)
    return { X = loc.X + math.cos(r) * dist, Y = loc.Y + math.sin(r) * dist, Z = loc.Z }
end

return armsloader
