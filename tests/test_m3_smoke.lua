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
    local W = { logs = {}, callbacks = {}, hook_visible = true, t = 0, mods = { VR_AimMethod = "2" } }
    os.execute('mkdir "build\\smoke3\\scripts\\lib" 2>nul')
    copy("src/scripts/m3_gestures.lua", STAGE .. "scripts/m3_gestures.lua")
    for _, m in ipairs(LIBS) do copy("src/scripts/lib/" .. m .. ".lua", STAGE .. "scripts/lib/" .. m .. ".lua") end
    local o = assert(io.open(STAGE .. "dreadmoorvr_arms_tuning.lua", "wb")); o:write("return { gestures = { enabled = true } }\n"); o:close()

    local hook = { IsVisible = function() return W.hook_visible end }
    local gun = { Hook = hook }
    local tool = { GetAttachSocketName = function() return fname(tool_socket) end, GetOwner = function() return gun end,
        get_full_name = function() return W.tool_full_name or "StaticMeshComponent /Test/Knife" end }
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
    local wheel = { rotation = { Pitch = 0, Yaw = 0, Roll = 0 },
        K2_GetComponentLocation = function() return { x = 100, y = 20, z = 30 } end,
        K2_GetComponentRotation = function(self) return self.rotation end }
    local cosmetic = { K2_SetActorRotation = function(_, rotation)
        W.cosmetic_rotation = { Pitch = rotation.Pitch, Yaw = rotation.Yaw, Roll = rotation.Roll }
        W.cosmetic_updates = (W.cosmetic_updates or 0) + 1
    end }
    local wheel_child = { Small_Boat_Steerwheel = wheel, CurrentActiveWheelCosmetic = cosmetic,
        actor_rotation = { Pitch = 0, Yaw = 0, Roll = 0 },
        K2_GetActorRotation = function(self) return self.actor_rotation end }
    W.pawn = { Mesh = mesh, get_class = function() return class_at(1) end,
        Controller = { PlayerCameraManager = pcm }, GetTransform = function() return {} end,
        BP_ShipSteeringWheel = { GetChildActor = function() return wheel_child end },
        Throttle_lever = { K2_GetComponentLocation = function() return { x = 90, y = 10, z = 20 } end } }
    W.wheel, W.wheel_cosmetic, W.wheel_child = wheel, cosmetic, wheel_child
    W.mouse = nil
    W.set_mode = function(mode, first_person)
        if mode == "fishing" then
            chain = { "BP_FishingController_C", "DrdFishingControllerBase", "Pawn" }
            W.pawn.StrugglingFish = { get_full_name = function() return "DrdStrugglingFish /Test/Fish" end,
                get_address = function() return 123 end }
            W.pawn.CurrentQTE = "None"
        elseif mode == "boat" then
            chain = { "BP_SmallBoat_V2_C", "DrdShipBase", "Pawn" }
            W.pawn.bFirstPersonCameraEnabled = first_person ~= false
        elseif mode == "paddle" then
            chain = { "BP_PaddleBoat_C", "DrdShipBase", "Pawn" }
        elseif mode == "crafting" then
            chain = { "BP_CraftController_C", "PlayerController", "Pawn" }
        else
            chain = { "BP_PlayerCharacter_C", "DrdPlayerCharacter", "Character", "Pawn" }
            W.pawn.StrugglingFish, W.pawn.CurrentQTE = nil, nil
        end
    end
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
        GetAllWidgetsOfClass = function(_, ctx, out, cls, top) out[1] = W.cross end,
        GetViewportSize = function() return { X = 1000, Y = 800 } end } end }
    objs["Class /Script/UMG.WidgetLayoutLibrary"] = { get_class_default_object = function() return {
        GetViewportSize = function() return { X = 1000, Y = 800 } end } end }
    _G.StructObject = { new = function() return {} end }
    -- Poses: W.left / W.right are functions of time returning a position (m); right faces -Z.
    W.left = function() return v(0, 1.2, -0.3) end
    W.right = function() return v(0.2, 1.2, -0.3) end
    W.right_q = { x = 0, y = 0, z = 0, w = 1 }
    _G.UEVR_Vector3f = { new = function() return { x = 0, y = 0, z = 0 } end }
    _G.UEVR_Quaternionf = { new = function() return { x = 0, y = 0, z = 0, w = 1 } end }
    local function reg(n) return function(fn) W.callbacks[n] = fn end end
    _G.uevr = {
        params = {
            functions = { log_info = function(s) W.logs[#W.logs + 1] = s end },
            vr = {
                set_mod_value = function(key, value) W.mods[key] = value end,
                get_left_controller_index = function() return 1 end, get_right_controller_index = function() return 2 end,
                get_hmd_index = function() return 0 end,
                get_right_joystick_source = function() return 2 end,
                trigger_haptic_vibration = function(delay, duration, frequency, amplitude, source)
                    W.haptic = { delay, duration, frequency, amplitude, source }
                    W.haptics = (W.haptics or 0) + 1
                end,
                get_pose = function(i, p, q)
                    local pos = i == 0 and v(0, 1.65, 0) or ((i == 1) and W.left(W.t) or W.right(W.t))
                    p.x, p.y, p.z = pos.X, pos.Y, pos.Z
                    if i == 2 then
                        q.x, q.y, q.z, q.w = W.right_q.x, W.right_q.y, W.right_q.z, W.right_q.w
                    else
                        q.x, q.y, q.z, q.w = 0, 0, 0, 1
                    end
                end,
            },
        },
        sdk = { callbacks = { on_pre_engine_tick = reg("tick"), on_xinput_get_state = reg("xinput"),
            on_script_reset = reg("reset"), on_post_calculate_stereo_view_offset = reg("post_view") } },
        api = { get_local_pawn = function() return W.pawn end,
                get_player_controller = function() return { SetMouseLocation = function(_, x, y) W.mouse = { x = x, y = y } end } end,
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
    test_boat_hands_drive_existing_axes_and_throttle_detents_haptically = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 0.1) -- captures neutral hand positions on entering helm
        W.left = function() return v(0.11, 1.2, -0.3) end
        W.right = function() return v(0.2, 1.38, -0.3) end
        run(W, 0.1)
        local state = { Gamepad = { sThumbLX = 0, sThumbLY = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 15000 and state.Gamepad.sThumbLX < 18000,
            "left-hand travel steers through IA_BoatMove X")
        assert(state.Gamepad.sThumbLY == 32767, "right-hand lift selects forward detent")
        assert(W.haptic and W.haptic[2] == 0.025 and W.haptic[3] == 150 and W.haptic[4] == 0.45,
            "right controller gets a short haptic click on throttle transition")
        assert(has(W, "boat throttle detent: forward"))
        W.right = function() return v(0.2, 1.2, -0.3) end
        run(W, 0.1)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY == 0, "returning the hand to its calibrated height selects neutral")
        W.right = function() return v(0.2, 1.0, -0.3) end
        run(W, 0.1)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY == -32767, "lowering the right hand selects full reverse")
        assert(W.haptics == 3, "forward, neutral, and reverse each give one click")
        config("return { gestures = { enabled = true, boat_steer_range_m = 0.11 } }")
        run(W, 1.2)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 32767, "boat steering range reloads live")
        no_failures(W)
    end,

    test_boat_gestures_only_override_axes_in_first_person = function()
        local W = world("None", false)
        W.set_mode("boat", false)
        run(W, 0.1)
        local state = { Gamepad = { sThumbLX = 12345, sThumbLY = -23456 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 12345 and state.Gamepad.sThumbLY == -23456,
            "third-person native steering and throttle pass through unchanged")
        assert(has(W, "boat third"), table.concat(W.logs, " | "))

        W.pawn.bFirstPersonCameraEnabled = true
        run(W, 0.1) -- entering first-person captures a fresh hand neutral pose
        W.left = function() return v(0.11, 1.2, -0.3) end
        run(W, 0.1)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 15000 and state.Gamepad.sThumbLX < 18000,
            "first-person left-hand steering takes over the existing X axis")

        W.pawn.bFirstPersonCameraEnabled = false
        run(W, 0.1)
        state.Gamepad.sThumbLX, state.Gamepad.sThumbLY = 12345, -23456
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 12345 and state.Gamepad.sThumbLY == -23456,
            "returning to third-person immediately restores native stick input")
        assert(has(W, "boat gestures paused; native axes restored"))
        no_failures(W)
    end,

    test_boat_harness_checks_both_rudder_directions_and_center_deadzone = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 0.1) -- calibrate the neutral hand positions
        local state = { Gamepad = { sThumbLX = 0, sThumbLY = 0 } }
        W.left = function() return v(0.22, 1.2, -0.3) end
        run(W, 0.1); W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 32767, "22 cm right hand travel reaches full right rudder")
        W.left = function() return v(-0.22, 1.2, -0.3) end
        run(W, 0.1); W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == -32767, "22 cm left hand travel reaches full left rudder")
        W.left = function() return v(0.01, 1.2, -0.3) end
        run(W, 0.1); W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0, "small hand drift stays in the steering center deadzone")
        no_failures(W)
    end,

    test_boat_harness_copies_cosmetic_wheel_after_game_tick = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 0.1)
        assert(has(W, "boat mesh anchors: wheel="), "fixture exposes the same wheel and throttle anchors as the game")
        W.cosmetic_rotation, W.cosmetic_updates = nil, 0
        -- The mesh has a local offset; game Blueprint copies its parent actor rotation.
        W.wheel.rotation = { Pitch = 12, Yaw = 65, Roll = -11 }
        W.wheel_child.actor_rotation = { Pitch = 2, Yaw = 65, Roll = -1 }
        W.callbacks.post_view(nil, 1)
        assert(W.cosmetic_rotation == nil, "skip the second eye callback")
        W.callbacks.post_view(nil, 0)
        assert(W.cosmetic_rotation and W.cosmetic_rotation.Yaw == 65
            and W.cosmetic_rotation.Pitch == 2 and W.cosmetic_rotation.Roll == -1,
            "cosmetic overlay copies the steering-wheel actor rotation, excluding mesh offset")
        W.wheel.rotation = { Pitch = 7, Yaw = -65, Roll = 14 }
        W.wheel_child.actor_rotation = { Pitch = -3, Yaw = -65, Roll = 4 }
        W.callbacks.post_view(nil, 0)
        assert(W.cosmetic_rotation.Yaw == -65 and W.cosmetic_rotation.Pitch == -3
            and W.cosmetic_rotation.Roll == 4, "cosmetic follows the base wheel in the opposite direction too")
        local updates = W.cosmetic_updates
        W.set_mode("walking"); run(W, 0.1)
        W.wheel.rotation = { Pitch = 0, Yaw = 0, Roll = 0 }
        W.callbacks.post_view(nil, 0)
        assert(W.cosmetic_updates == updates, "boat-only cosmetic sync stops after leaving the helm")
        no_failures(W)
    end,

    test_other_boat_types_keep_their_native_axes = function()
        local W = world("None", false)
        W.set_mode("paddle")
        run(W, 0.1)
        local state = { Gamepad = { sThumbLX = 2345, sThumbLY = -6789 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 2345 and state.Gamepad.sThumbLY == -6789,
            "wheel/throttle bridge is scoped to BP_SmallBoat_V2")
        no_failures(W)
    end,

    test_crafting_hand_moves_cursor_through_native_hover_and_click_path = function()
        local W = world("None", false)
        W.set_mode("crafting")
        W.left = function() return v(0.1, 1.65, 0) end
        run(W, 0.1)
        assert(W.mouse and W.mouse.x == 750 and W.mouse.y == 400,
            "left-hand position moves the screen cursor; CraftController retains hover/click: " .. table.concat(W.logs, " | "))
        config("return { gestures = { enabled = true, craft_cursor_span_m = 0.2 } }")
        run(W, 1.2)
        assert(W.mouse.x == 999, "craft cursor span reloads live and clamps at the viewport edge")
        no_failures(W)
    end,

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
        W.tool_full_name = "StaticMeshComponent /Test/BP_Sickle_Equipment_C_1.StaticMesh"
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

    test_fishing_crank_holds_reel_only_while_turning = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.6) -- establish the idle fish phase before beginning the crank
        cranking(W)
        local held = 0
        for _ = 1, 90 do
            W.t = W.t + DT
            W.callbacks.tick(nil, DT)
            local state = { Gamepad = { bRightTrigger = 0 } }
            W.callbacks.xinput(nil, 0, state)
            if state.Gamepad.bRightTrigger == 255 then held = held + 1 end
        end
        assert(held > 50, "crank should hold the game's fishing reel action")
        W.left = function() return v(0, 0, 0) end
        W.t = W.t + DT
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 0, "reel trigger releases after crank stops")
        no_failures(W)
    end,

    test_fishing_rod_lean_writes_fight_axis = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.6) -- calibrate neutral
        local x = 0.2
        W.right = function() return v(x, 1.2, -0.3) end
        run(W, DT)
        x = x + 0.2
        W.t = W.t + DT
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 0, sThumbLX = 0, sThumbLY = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 15000, "rod lean should write signed fishing fight X")
        assert(state.Gamepad.sThumbLY == 0, "normal fight leaves physical Y untouched")
        no_failures(W)
    end,

    test_directional_drag_writes_two_stick_axes = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.6)
        W.pawn.CurrentQTE = "QTE.Type.DirectionalDrag"
        W.t = W.t + DT
        W.callbacks.tick(nil, DT) -- calibrate QTE neutral
        local x, y = 0.4, 1.4
        W.right = function() return v(x, y, -0.3) end
        W.t = W.t + DT
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 0, sThumbLX = 0, sThumbLY = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 15000 and state.Gamepad.sThumbLY > 15000,
            "directional drag should write right-hand X/Y movement to left stick")
        assert(state.Gamepad.bRightTrigger == 0, "fishing crank is suppressed during QTE")
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

    test_thumb_down_in_front_holds_melee_guard = function()
        local W = world("KnifeSocket", false)
        W.tool_full_name = "StaticMeshComponent /Test/BP_Sickle_Equipment_C_1.StaticMesh"
        run(W, 0.6)
        -- Rotate controller forward (-Z) down toward world -Y; keep the hand low and in front.
        W.right_q = { x = -math.sqrt(0.5), y = 0, z = 0, w = math.sqrt(0.5) }
        local held = 0
        for _ = 1, 24 do
            W.t = W.t + DT
            W.callbacks.tick(nil, DT)
            local state = { Gamepad = { bRightTrigger = 41, bLeftTrigger = 0 } }
            W.callbacks.xinput(nil, 0, state)
            if state.Gamepad.bLeftTrigger == 255 then held = held + 1 end
            assert(state.Gamepad.bRightTrigger == 41, "guard must not press PrimaryUse/attack")
        end
        assert(held >= 5, "thumb-down guard should hold SecondaryUse after its 100 ms dwell; frames=" .. held)
        assert(has(W, "guard held"), "guard transition should be logged")
        assert(W.mods.VR_AimMethod == "1", "guard switches aim away from the right controller to prevent body yaw twisting")
        no_failures(W)
    end,

    test_guard_releases_when_hand_leaves_the_front_guard_zone = function()
        local W = world("KnifeSocket", false)
        W.tool_full_name = "StaticMeshComponent /Test/BP_Sickle_Equipment_C_1.StaticMesh"
        run(W, 0.6)
        W.right_q = { x = -math.sqrt(0.5), y = 0, z = 0, w = math.sqrt(0.5) }
        run(W, 0.2)
        assert(has(W, "guard held"), "fixture should enter guard before testing release")
        W.right = function() return v(0.2, 1.2, 0.2) end -- behind the HMD/body plane
        run(W, 0.3)
        assert(has(W, "guard released"), "moving behind the body should release guard")
        assert(W.mods.VR_AimMethod == "2", "walking right-hand aim is restored after guard release")
        no_failures(W)
    end,

    test_guard_can_be_disabled_live = function()
        local W = world("KnifeSocket", false)
        W.tool_full_name = "StaticMeshComponent /Test/BP_Sickle_Equipment_C_1.StaticMesh"
        W.right_q = { x = -math.sqrt(0.5), y = 0, z = 0, w = math.sqrt(0.5) }
        config("return { gestures = { enabled = true, guard_enabled = false } }")
        run(W, 0.5)
        assert(not has(W, "guard held"), "disabled guard must not claim the trigger")
        local state = { Gamepad = { bRightTrigger = 173, bLeftTrigger = 91 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 173, "disabled guard leaves the physical trigger untouched")
        assert(state.Gamepad.bLeftTrigger == 91, "disabled guard leaves SecondaryUse untouched")
        no_failures(W)
    end,

    test_thumb_down_does_not_guard_with_knife = function()
        local W = world("KnifeSocket", false)
        run(W, 0.6) -- default fake full name is a knife, not BP_Sickle_Equipment
        W.right_q = { x = -math.sqrt(0.5), y = 0, z = 0, w = math.sqrt(0.5) }
        run(W, 0.3)
        assert(not has(W, "guard held"), "block ability is only present on the sickle")
        local state = { Gamepad = { bRightTrigger = 0, bLeftTrigger = 77 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bLeftTrigger == 77, "knife does not claim SecondaryUse as block")
        no_failures(W)
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
