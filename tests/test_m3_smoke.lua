-- Smoke test: the real m3_gestures.lua and its lib modules against a fake UEVR (no require, like
-- the real one) and a fake game. Real names: tools sit at HookSimple / KnifeSocket, and the hook
-- gun's Hook mesh is hidden while the hook is out (docs/research/2026-11-17-remaining-hooks.md).
local STAGE = "build/smoke3/"
local LIBS = { "gameapi", "modes", "gestures", "reticle", "armsloader" }
local DT = 1 / 60

local function copy(src, dst)
    local i = assert(io.open(src, "rb")); local s = i:read("a"); i:close()
    local o = assert(io.open(dst, "wb")); o:write(s); o:close()
end

local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function fname(s) return { to_string = function() return s end } end

local function world(tool_socket, on_body)
    local W = { logs = {}, callbacks = {}, hook_visible = true, t = 0 }
    os.execute('mkdir "build\\smoke3\\scripts\\lib" 2>nul')
    copy("src/scripts/m3_gestures.lua", STAGE .. "scripts/m3_gestures.lua")
    for _, m in ipairs(LIBS) do copy("src/scripts/lib/" .. m .. ".lua", STAGE .. "scripts/lib/" .. m .. ".lua") end
    local o = assert(io.open(STAGE .. "dreadmoorvr_arms_tuning.lua", "wb")); o:write("return { gestures = { enabled = true } }\n"); o:close()

    local hook = { IsVisible = function() return W.hook_visible end }
    local gun = { Hook = hook }
    local tool = { GetAttachSocketName = function() return fname(tool_socket) end, GetOwner = function() return gun end }
    local body = { GetAttachSocketName = function() return fname("None") end, AttachChildren = on_body and { tool } or nil }
    local mesh = { AttachChildren = on_body and { body } or { tool } }
    W.mesh, W.tool = mesh, tool
    local chain = { "BP_PlayerCharacter_C", "DrdPlayerCharacter", "Character", "Pawn" }
    local function class_at(i)
        if i > #chain then return nil end
        return { get_fname = function() return fname(chain[i]) end, get_super_struct = function() return class_at(i + 1) end }
    end
    -- Camera at (0,0,170) looking along +X; a wall 800 cm ahead.
    W.trace_calls = {}
    local pcm = { GetCameraLocation = function() return { x = 0, y = 0, z = 170 } end,
                  GetCameraRotation = function() return { x = 0, y = 0, z = 0 } end }
    W.pawn = { Mesh = mesh, get_class = function() return class_at(1) end,
        Controller = { PlayerCameraManager = pcm }, GetTransform = function() return {} end }
    W.dot = { hidden = true, StaticMeshComponent = { SetStaticMesh = function() end, SetMaterial = function() end,
        SetCollisionEnabled = function() end, SetCastShadow = function() end,
        SetWorldScale3D = function(self, sc) W.dot_scale = sc.X end } }
    W.dot.SetActorHiddenInGame = function(self, h) self.hidden = h end
    W.dot.K2_SetActorLocation = function(self, p) self.loc = p end
    W.dot.K2_DestroyActor = function(self) self.destroyed = true end
    local ksl = { LineTraceSingle = function(_, ctx, start, finish, chan, complex, ignore, dbg, hit)
        W.trace_calls[#W.trace_calls + 1] = { start = start, finish = finish, chan = chan, ignore = ignore }
        if finish.X < 800 then return false end
        -- FHitResult.ImpactPoint is FVector_NetQuantize: UEVR hands it back as a struct with X/Y/Z
        -- (only the exact FVector type becomes x/y/z). In game the reticle crashed on this (17:51).
        hit.ImpactPoint = { X = 800, Y = 0, Z = 170 }
        return true
    end }
    local objs = {
        ["Class /Script/Engine.StaticMeshActor"] = { get_class_default_object = function() return {} end },
        ["StaticMesh /Engine/BasicShapes/Sphere.Sphere"] = {},
        ["Material /Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial"] = {},
        ["ScriptStruct /Script/Engine.HitResult"] = {},
        ["Class /Script/Engine.KismetSystemLibrary"] = { get_class_default_object = function() return ksl end },
        ["BlueprintGeneratedClass /Game/Dreadmoor/Core/Features/Hook/GAS/GA_HookGun.GA_HookGun_C"] =
            { get_class_default_object = function() return { TraceLength = 3000 } end },
        ["Class /Script/Engine.GameplayStatics"] = { get_class_default_object = function() return {
            BeginDeferredActorSpawnFromClass = function() return W.dot end,
            FinishSpawningActor = function(_, a) return a end } end },
    }
    -- The game's 2D crosshair widget (WBP_Cross), found through WidgetBlueprintLibrary.
    W.cross = { opacity = 1, SetRenderOpacity = function(self, o) self.opacity = o end }
    objs["WidgetBlueprintGeneratedClass /Game/Dreadmoor/UI/HUD/WBP_Cross.WBP_Cross_C"] = {}
    objs["Class /Script/UMG.WidgetBlueprintLibrary"] = { get_class_default_object = function() return {
        GetAllWidgetsOfClass = function(_, ctx, out, cls, top) out[1] = W.cross end } end }
    _G.StructObject = { new = function() return {} end }
    -- Poses: W.left / W.right are functions of time returning a position (m); right faces -Z.
    W.left = function() return v(0, 1.2, -0.3) end
    W.right = function() return v(0.2, 1.2, -0.3) end
    _G.UEVR_Vector3f = { new = function() return { x = 0, y = 0, z = 0 } end }
    _G.UEVR_Quaternionf = { new = function() return { x = 0, y = 0, z = 0, w = 1 } end }
    local function reg(n) return function(fn) W.callbacks[n] = fn end end
    _G.uevr = {
        params = {
            functions = { log_info = function(s) W.logs[#W.logs + 1] = s end },
            vr = {
                get_left_controller_index = function() return 1 end, get_right_controller_index = function() return 2 end,
                get_pose = function(i, p, q)
                    local pos = (i == 1) and W.left(W.t) or W.right(W.t)
                    p.x, p.y, p.z = pos.X, pos.Y, pos.Z
                    q.x, q.y, q.z, q.w = 0, 0, 0, 1
                end,
            },
        },
        sdk = { callbacks = { on_pre_engine_tick = reg("tick"), on_xinput_get_state = reg("xinput"), on_script_reset = reg("reset") } },
        api = { get_local_pawn = function() return W.pawn end,
                find_uobject = function(_, n) return objs[n] end,
                get_engine = function() return { GameViewport = { World = {} } } end },
    }
    local saved_path, saved_require = package.path, require
    package.path = STAGE .. "scripts/?.lua;" .. saved_path
    _G.require = function(name) error("UEVR has no working require (asked for " .. tostring(name) .. ")") end
    local ok, err = pcall(function() assert(loadfile(STAGE .. "scripts/m3_gestures.lua"))() end)
    _G.require, package.path = saved_require, saved_path
    assert(ok, "script failed to load: " .. tostring(err))
    return W
end

-- Runs `seconds` of frames and counts right-trigger presses (rising edges) the game would see.
local function run(W, seconds)
    local presses, was = 0, false
    for _ = 1, math.floor(seconds / DT) do
        W.t = W.t + DT
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 0 } }
        W.callbacks.xinput(nil, 0, state)
        local down = state.Gamepad.bRightTrigger > 128
        if down and not was then presses = presses + 1 end
        was = down
    end
    return presses
end

-- Left hand circling the crank point: right hand at the origin facing -Z, crank axis = X,
-- crank point offset (-0.06, 0, 0.04); circle of 10 cm in the Y/Z plane at 360 deg/s.
local function cranking(W)
    W.right = function() return v(0, 1.2, -0.3) end
    W.left = function(t)
        local a = math.rad(360 * t)
        return v(-0.06, 1.2 + 0.10 * math.cos(a), -0.3 + 0.04 + 0.10 * math.sin(a))
    end
end

local function has(W, pat) for _, l in ipairs(W.logs) do if l:find(pat) then return true end end return false end
local function no_failures(W)
    for _, l in ipairs(W.logs) do assert(not l:find("FAILED"), l) end
end

local function config(text)
    local f = assert(io.open(STAGE .. "dreadmoorvr_arms_tuning.lua", "wb"))
    f:write(text); f:close()
end

-- Queue real crank events without polling XInput, so the transition has work to cancel.
local function queued_crank()
    local W = world("HookSimple", false)
    W.hook_visible = false
    cranking(W)
    for _ = 1, 45 do W.t = W.t + DT; W.callbacks.tick(nil, DT) end
    assert(has(W, "crank click"), "fixture must actually queue input")
    return W
end

return {
    test_loads_without_require = function()
        local W = world("HookSimple", false)
        run(W, 1)
        no_failures(W)
        assert(has(W, "tool in hand: hookgun"))
    end,

    test_crank_does_nothing_while_the_hook_is_home = function()
        local W = world("HookSimple", false)
        cranking(W)
        assert(run(W, 2) == 0, "pressing now would FIRE the gun")
        no_failures(W)
    end,

    test_crank_reels_while_the_hook_is_out = function()
        local W = world("HookSimple", true)   -- gun moved onto the VR hand (items_follow_hands)
        run(W, 0.6)
        W.hook_visible = false
        cranking(W)
        local presses = run(W, 2)
        assert(presses >= 6 and presses <= 8, "two turns = about 8 clicks, got " .. presses)
        assert(has(W, "hook out: crank live"))
        W.hook_visible = true
        local after = run(W, 1)
        assert(after == 0, "no reel tap may fire the gun after the hook returns, got " .. after)
        no_failures(W)
    end,

    test_sickle_swing_attacks_once = function()
        local W = world("KnifeSocket", false)
        run(W, 0.6)
        local x = 0
        W.right = function() x = x + 3.0 * DT; return v(x, 1.2, -0.3) end
        local presses = run(W, 0.3)
        W.right = function() return v(x, 1.2, -0.3) end
        presses = presses + run(W, 0.5)
        assert(presses == 1, "one swing, one attack; got " .. presses)
        assert(has(W, "swing %-> attack"))
        no_failures(W)
    end,

    test_reticle_sits_where_the_hook_will_go = function()
        local W = world("HookSimple", false)
        run(W, 1)
        no_failures(W)
        assert(has(W, "reticle ready %(TraceLength 3000%)"), "uses the game's TraceLength")
        assert(not W.dot.hidden, "shown while aiming")
        assert(W.dot.loc and W.dot.loc.X == 800 and W.dot.loc.Z == 170, "on the hit point")
        local c = W.trace_calls[#W.trace_calls]
        assert(c.start.Z == 170 and c.finish.X == 3000, "from the camera, TraceLength along the view")
        assert(c.chan == 0 and c.ignore[1] == W.pawn, "Visibility channel, ignoring the player (as GA_HookGun)")
        assert(W.dot_scale > 0.04 and W.dot_scale < 0.08, "about 0.4 degrees at 8 m: " .. W.dot_scale)
        assert(W.cross.opacity == 0, "game's 2D dot hidden while ours is up")
        W.hook_visible = false
        run(W, 0.6)
        assert(W.dot.hidden, "hidden while the hook is out")
        assert(W.cross.opacity == 1, "game's 2D dot back when ours is down")
    end,

    test_no_reticle_without_the_gun = function()
        local W = world("KnifeSocket", false)
        run(W, 1)
        assert(#W.trace_calls == 0 and W.dot.hidden, "no trace, no dot")
    end,

    test_real_trigger_passes_through_when_idle = function()
        local W = world("KnifeSocket", false)
        run(W, 0.6)
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 200 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 200, "player's own trigger untouched")
    end,

    test_hook_return_cancels_all_queued_presses = function()
        local W = queued_crank()
        W.hook_visible = true
        assert(run(W, 1) == 0, "queued reel must not FIRE the gun")
        no_failures(W)
    end,

    test_leaving_walking_cancels_queued_and_active_presses = function()
        local W = queued_crank()
        local state = { Gamepad = { bRightTrigger = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 255, "a pulse was active")
        local walking = W.pawn
        W.pawn = nil
        assert(run(W, 1) == 0, "no pulses after leaving walking")
        state.Gamepad.bRightTrigger = 200
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 200, "physical trigger passes through")
        W.pawn = walking
        W.hook_visible = true
        assert(run(W, 1) == 0, "no old input on return")
    end,

    test_tool_replacement_cancels_old_queue_even_for_same_kind = function()
        local W = queued_crank()
        W.left = function() return v(0, 0, 0) end
        W.mesh.AttachChildren = { { GetAttachSocketName = W.tool.GetAttachSocketName, GetOwner = W.tool.GetOwner } }
        assert(run(W, 0.2) == 0, "old gun's queue cannot transfer to new gun")
    end,

    test_new_walking_pawn_cancels_old_queue = function()
        local W = queued_crank()
        W.left = function() return v(0, 0, 0) end
        W.pawn = setmetatable({}, { __index = W.pawn })
        assert(run(W, 0.2) == 0, "new pawn must not inherit taps")
    end,

    test_disable_restores_crosshair_and_hides_reticle = function()
        local W = world("HookSimple", false)
        run(W, 1)
        assert(not W.dot.hidden and W.cross.opacity == 0)
        config("return { gestures = { enabled = false } }")
        run(W, 2)
        assert(W.dot.hidden and W.cross.opacity == 1, "disable cleans both visuals")
    end,

    test_hide_game_dot_can_change_while_reticle_stays_visible = function()
        local W = world("HookSimple", false)
        run(W, 1)
        config("return { gestures = { hide_game_dot = false } }")
        run(W, 2)
        assert(not W.dot.hidden and W.cross.opacity == 1, "live option restores crosshair")
        config("return { gestures = { hide_game_dot = true } }")
        run(W, 2)
        assert(W.cross.opacity == 0)
        W.callbacks.reset()
        assert(W.cross.opacity == 1 and W.dot.destroyed, "reset cleans up")
    end,

    test_other_xinput_slots_do_not_consume_or_receive_taps = function()
        local W = queued_crank()
        local state = { Gamepad = { bRightTrigger = 17 } }
        W.callbacks.xinput(nil, 1, state)
        assert(state.Gamepad.bRightTrigger == 17)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 255)
    end,
}
