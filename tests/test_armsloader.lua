-- Desk tests for armsloader with a fake `uevr` global. They pin the order of the load
-- methods and the spawn calls; whether UEVR marshals them the same way is what M1 proves.

local function fresh()
    package.loaded["armsloader"] = nil
    return require("armsloader")
end

local PATH = "/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C"

-- Builds a fake uevr. `found` = what find_uobject returns for the BP class,
-- `loaded` = what LoadClassAsset_Blocking returns. Records calls in `log`.
local function fake_uevr(found, loaded)
    local log = {}
    local ksl = {
        MakeSoftClassPath = function(_, s) log[#log + 1] = "MakeSoftClassPath " .. s; return { path = s } end,
        Conv_SoftClassPathToSoftClassRef = function(_, p) return { ref = p.path } end,
        LoadClassAsset_Blocking = function(_, r) log[#log + 1] = "Load " .. r.ref; return loaded end,
    }
    local gs = {
        BeginDeferredActorSpawnFromClass = function(_, world, cls, xf, coll, owner, scale)
            log[#log + 1] = "Begin " .. tostring(cls.name) .. " coll=" .. coll
            return { name = "actor" }
        end,
        FinishSpawningActor = function(_, actor, xf, scale)
            log[#log + 1] = "Finish " .. actor.name
            return actor
        end,
    }
    local statics = {
        ["Class /Script/Engine.KismetSystemLibrary"] = ksl,
        ["Class /Script/Engine.GameplayStatics"] = gs,
    }
    _G.uevr = {
        api = {
            find_uobject = function(_, name)
                if name == "BlueprintGeneratedClass " .. PATH then return found end
                local s = statics[name]
                if s then return { get_class_default_object = function() return s end } end
                return nil
            end,
            get_engine = function() return { GameViewport = { World = { name = "world" } } } end,
        },
    }
    return log
end

return {
    test_load_class_prefers_find_uobject = function()
        local log = fake_uevr({ name = "BP" }, nil)
        local cls, method = fresh().load_class(PATH)
        assert(cls and cls.name == "BP")
        assert(method == "find_uobject", tostring(method))
        assert(#log == 0, "no blocking load when already in memory")
    end,

    test_load_class_falls_back_to_blocking_load = function()
        local log = fake_uevr(nil, { name = "BP" })
        local cls, method = fresh().load_class(PATH)
        assert(cls and cls.name == "BP")
        assert(method == "LoadClassAsset_Blocking", tostring(method))
        assert(log[1] == "MakeSoftClassPath " .. PATH, log[1])
    end,

    test_load_class_nil_when_both_fail = function()
        fake_uevr(nil, nil)
        local cls, method = fresh().load_class(PATH)
        assert(cls == nil)
        assert(method == "none", tostring(method))
    end,

    test_load_class_survives_throwing_api = function()
        fake_uevr(nil, nil)
        uevr.api.find_uobject = function() error("boom") end
        local cls, method = fresh().load_class(PATH)
        assert(cls == nil and method == "none")
    end,

    test_spawn_uses_deferred_spawn = function()
        local log = fake_uevr(nil, nil)
        local actor = fresh().spawn({ name = "BP" }, { tag = "xf" })
        assert(actor and actor.name == "actor")
        assert(log[1] == "Begin BP coll=1", log[1])
        assert(log[2] == "Finish actor", log[2])
    end,

    test_spawn_nil_without_class = function()
        fake_uevr(nil, nil)
        assert(fresh().spawn(nil, {}) == nil)
    end,

    test_ahead_offsets_along_yaw = function()
        local a = fresh()
        local p = a.ahead({ X = 0, Y = 0, Z = 10 }, 90, 150)
        assert(math.abs(p.X) < 1e-6 and math.abs(p.Y - 150) < 1e-6 and p.Z == 10,
            string.format("%f %f %f", p.X, p.Y, p.Z))
        p = a.ahead({ X = 5, Y = 0, Z = 0 }, 0, 150)
        assert(math.abs(p.X - 155) < 1e-6 and math.abs(p.Y) < 1e-6)
    end,
}
