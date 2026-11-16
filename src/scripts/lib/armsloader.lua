-- Loads a Blueprint class from the mod pak and spawns it. Every UEVR call is wrapped so a
-- failure returns nil and a reason instead of throwing into UEVR's tick.
local armsloader = {}

local ESCAPE_COLLISION_ALWAYS_SPAWN = 1 -- ESpawnActorCollisionHandlingMethod::AlwaysSpawn
local SCALE_MULTIPLY_WITH_ROOT = 1      -- ESpawnActorScaleMethod::MultiplyWithRoot

local function static(class_path)
    local cls = uevr.api:find_uobject("Class " .. class_path)
    return cls and cls:get_class_default_object() or nil
end

-- Returns class, method, notes. method is "find_uobject", "LoadClassAsset_Blocking",
-- "LoadAsset_Blocking" or "none". notes says why each method that ran came up empty.
-- path is the full object path, e.g. "/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C".
function armsloader.load_class(path)
    local notes = {}
    local function try(name, fn)
        local ok, res = pcall(fn)
        if ok and res then return res end
        notes[#notes + 1] = name .. ": " .. (ok and "nil" or tostring(res))
        return nil
    end

    local cls = try("find_uobject", function()
        return uevr.api:find_uobject("BlueprintGeneratedClass " .. path)
    end)
    if cls then return cls, "find_uobject", "" end

    cls = try("LoadClassAsset_Blocking", function()
        local ksl = static("/Script/Engine.KismetSystemLibrary")
        local soft_path = ksl:MakeSoftClassPath(path)
        local soft_ref = ksl:Conv_SoftClassPathToSoftClassRef(soft_path)
        notes[#notes + 1] = "class steps: ksl=" .. tostring(ksl) .. " path=" .. tostring(soft_path)
            .. " ref=" .. tostring(soft_ref)
        return ksl:LoadClassAsset_Blocking(soft_ref)
    end)
    if cls then return cls, "LoadClassAsset_Blocking", table.concat(notes, "; ") end

    cls = try("LoadAsset_Blocking", function()
        local ksl = static("/Script/Engine.KismetSystemLibrary")
        local soft_path = ksl:MakeSoftObjectPath(path)
        local soft_ref = ksl:Conv_SoftObjPathToSoftObjRef(soft_path)
        local obj = ksl:LoadAsset_Blocking(soft_ref)
        notes[#notes + 1] = "asset steps: path=" .. tostring(soft_path) .. " ref=" .. tostring(soft_ref)
            .. " obj=" .. tostring(obj)
        -- Loading the package puts the class in memory; look it up again.
        return uevr.api:find_uobject("BlueprintGeneratedClass " .. path)
    end)
    if cls then return cls, "LoadAsset_Blocking", table.concat(notes, "; ") end

    return nil, "none", table.concat(notes, "; ")
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
