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
local function gameplay_tag(s) return { TagName = fname(s) } end

local function world(tool_socket, on_body)
    local W = { logs = {}, callbacks = {}, hook_visible = true, t = 0, controllers_active = true,
        pose_read_fails = false,
        native_pose_enabled = false, native_pose_valid = { L = true, R = true },
        native_pose_paused = false, native_pose_last = {}, native_pose_order = { "L", "R" },
        mods = { VR_AimMethod = "2" } }
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
    local cosmetic_actor = { K2_SetActorRotation = function(_, rotation)
        W.cosmetic_rotation = { Pitch = rotation.Pitch, Yaw = rotation.Yaw, Roll = rotation.Roll }
        W.cosmetic_updates = (W.cosmetic_updates or 0) + 1
    end }
    local cosmetic = { Actor = cosmetic_actor }
    local wheel_child = { Small_Boat_Steerwheel = wheel, CurrentActiveWheelCosmetic = cosmetic,
        actor_rotation = { Pitch = 0, Yaw = 0, Roll = 0 },
        K2_GetActorRotation = function(self) return self.actor_rotation end }
    W.camera_rotation = { Pitch = 1, Yaw = 12, Roll = 3 }
    W.boat_rotation = { Pitch = 0, Yaw = 30, Roll = 0 }
    W.pawn = { Mesh = mesh, get_class = function() return class_at(1) end,
        Controller = { PlayerCameraManager = pcm }, GetTransform = function() return {} end,
        FirstPersonSpringArm_GEN_VARIABLE = { K2_GetComponentRotation = function() return W.camera_rotation end },
        CameraComp = { K2_GetComponentRotation = function() return W.camera_rotation end },
        K2_GetActorRotation = function() return W.boat_rotation end,
        BP_ShipSteeringWheel = { GetChildActor = function() return wheel_child end },
        Throttle_lever = { K2_GetComponentLocation = function() return { x = 90, y = 10, z = 20 } end } }
    W.wheel, W.wheel_cosmetic, W.wheel_cosmetic_actor, W.wheel_child = wheel, cosmetic, cosmetic_actor, wheel_child
    W.mouse = nil
    W.set_mode = function(mode, first_person)
        if mode == "fishing" then
            chain = { "BP_FishingController_C", "DrdFishingControllerBase", "Pawn" }
            W.pawn.StrugglingFish = { get_full_name = function() return "DrdStrugglingFish /Test/Fish" end,
                get_address = function() return 123 end }
            W.pawn.CurrentQTE = gameplay_tag("None")
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
    W.head_q = { x = 0, y = 0, z = 0, w = 1 }
    W.right_q = { x = 0, y = 0, z = 0, w = 1 }
    _G.UEVR_Vector3f = { new = function() return { x = 0, y = 0, z = 0 } end }
    _G.UEVR_Quaternionf = { new = function() return { x = 0, y = 0, z = 0, w = 1 } end }
    local function reg(n) return function(fn) W.callbacks[n] = fn end end
    _G.uevr = {
        params = {
            functions = { log_info = function(s) W.logs[#W.logs + 1] = s end },
            vr = {
                is_using_controllers = function() return W.controllers_active end,
                set_mod_value = function(key, value) W.mods[key] = value end,
                get_left_controller_index = function() return 1 end, get_right_controller_index = function() return 2 end,
                get_hmd_index = function() return 0 end,
                get_left_joystick_source = function() return 1 end,
                get_right_joystick_source = function() return 2 end,
                trigger_haptic_vibration = function(delay, duration, frequency, amplitude, source)
                    W.haptic = { delay, duration, frequency, amplitude, source }
                    W.haptics = (W.haptics or 0) + 1
                end,
                get_pose = function(i, p, q)
                    if W.pose_read_fails then error("simulated invalid pose read") end
                    local pos = i == 0 and (W.head_pose or v(0, 1.65, 0)) or ((i == 1) and W.left(W.t) or W.right(W.t))
                    p.x, p.y, p.z = pos.X, pos.Y, pos.Z
                    if i == 0 then
                        q.x, q.y, q.z, q.w = W.head_q.x, W.head_q.y, W.head_q.z, W.head_q.w
                    elseif i == 2 then
                        q.x, q.y, q.z, q.w = W.right_q.x, W.right_q.y, W.right_q.z, W.right_q.w
                    else
                        q.x, q.y, q.z, q.w = 0, 0, 0, 1
                    end
                end,
            },
        },
        sdk = { callbacks = { on_pre_engine_tick = reg("tick"), on_xinput_get_state = reg("xinput"),
            on_lua_event = reg("lua_event"),
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
        if W.native_pose_enabled and not W.native_pose_paused then
            for _, side in ipairs(W.native_pose_order) do
                local value = W.native_pose_valid[side]
                local prior = W.native_pose_last[side]
                if prior == nil or prior.value ~= value or W.t - prior.time >= 0.1 then
                    W.callbacks.lua_event("dreadmoorvr_pose_validity", side .. "|" .. (value and "1" or "0"))
                    W.native_pose_last[side] = { value = value, time = W.t }
                end
            end
        end
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 0 } }
        W.callbacks.xinput(nil, 0, state)
        local down = state.Gamepad.bRightTrigger > 128
        if down and not was then presses = presses + 1 end
        was = down
    end
    return presses
end

local function move_left_x(W, target, speed)
    speed = speed or 1.0
    local start = W.left(W.t).X
    local start_time = W.t
    local duration = math.abs(target - start) / speed
    W.left = function(t)
        local a = duration > 0 and math.min(1, math.max(0, (t - start_time) / duration)) or 1
        return v(start + (target - start) * a, 1.14, -0.3) -- shallow lower arc on the wheel
    end
    run(W, duration + 0.25)
end

local function move_left_pose(W, target_x, target_y, speed)
    speed = speed or 1.0
    local start = W.left(W.t)
    local distance = math.sqrt((target_x - start.X) ^ 2 + (target_y - start.Y) ^ 2)
    local start_time = W.t
    local duration = distance / speed
    W.left = function(t)
        local a = duration > 0 and math.min(1, math.max(0, (t - start_time) / duration)) or 1
        return v(start.X + (target_x - start.X) * a, start.Y + (target_y - start.Y) * a, start.Z)
    end
    run(W, duration + 0.25)
end

local function move_right_pose(W, target_y, target_z, speed)
    speed = speed or 1.0
    local start = W.right(W.t)
    local distance = math.sqrt((target_y - start.Y) ^ 2 + (target_z - start.Z) ^ 2)
    local start_time = W.t
    local duration = distance / speed
    W.right = function(t)
        local a = duration > 0 and math.min(1, math.max(0, (t - start_time) / duration)) or 1
        return v(0.2, start.Y + (target_y - start.Y) * a, start.Z + (target_z - start.Z) * a)
    end
    run(W, duration + 0.25)
end

-- Left hand circling the crank point: right hand at the origin facing -Z, crank axis = X,
-- crank point offset (-0.06, 0, 0.04); circle of 10 cm in the Y/Z plane at 360 deg/s.
local function cranking(W)
    local started_at = W.t
    W.right = function() return v(0.2, 1.2, -0.3) end
    W.left = function(t)
        local a = math.rad(360 * (t - started_at))
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
    test_boat_home_calibration_accepts_measured_wheel_pose = function()
        local W = world("None", false)
        W.set_mode("boat")
        -- Captured at 09:57:58: intended wheel hand was 2 cm below the old -0.75 m bound.
        W.left = function() return v(-0.16, 0.88, -0.04) end
        W.right = function() return v(0.17, 0.84, 0.09) end
        run(W, 0.8)
        assert(has(W, "boat control frame locked from home pose"),
            "measured 120-o'clock / hip-fire home pose calibrates without edge-boundary flicker")
        assert(not has(W, "boat home pose not recognized"),
            "the measured home pose is recognized throughout the settle interval")
        no_failures(W)
    end,

    test_boat_zero_hmd_tracking_fails_safe_to_neutral = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 1.5)
        local state = { Gamepad = { sThumbLX = 0, sThumbLY = 0 } }
        move_right_pose(W, 1.15, -0.42)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY > 0, "fixture first enters forward throttle")

        W.head_pose = v(0, 0, 0)
        run(W, 0.1)
        state.Gamepad.sThumbLX, state.Gamepad.sThumbLY = 1234, 5678
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0 and state.Gamepad.sThumbLY == 0,
            "identity HMD pose at the tracking origin neutralizes both helm axes")
        assert(has(W, "HMD pose at tracking origin"), "tracking-origin rejection is diagnosable")
        no_failures(W)
    end,

    test_fishing_bite_qte_sets_hook_on_quick_upward_twitch = function()
        local W = world("None", false)
        W.set_mode("fishing")
        W.native_pose_enabled = true
        W.controllers_active = false
        W.pawn.CurrentQTE = gameplay_tag("QTE.Type.FishingBite")
        run(W, 0.08) -- capture the hand's bite-QTE baseline
        local start_time = W.t
        W.right = function(t)
            local a = math.min(1, math.max(0, (t - start_time) / 0.16))
            return v(0.2, 1.2 + 0.20 * a, -0.3)
        end
        local saw_press, pulse_frames = false, 0
        for _ = 1, 10 do
            W.t = W.t + DT
            W.callbacks.tick(nil, DT)
            local state = { Gamepad = { bRightTrigger = 0, sThumbRX = 1234, sThumbRY = -2345 } }
            W.callbacks.xinput(nil, 0, state)
            if state.Gamepad.bRightTrigger == 255 then
                saw_press = true
                pulse_frames = pulse_frames + 1
            end
            assert(state.Gamepad.sThumbRX == 1234 and state.Gamepad.sThumbRY == -2345,
                "hook-set gesture does not alter camera-look axes")
        end
        assert(saw_press, "upward twitch sends a short hook-set press")
        assert(pulse_frames >= 1 and pulse_frames <= 7,
            "hook-set press stays a brief pulse (observed " .. pulse_frames .. " frames)")
        run(W, 0.1)
        local released = { Gamepad = { bRightTrigger = 0, sThumbRX = 1234, sThumbRY = -2345 } }
        W.callbacks.xinput(nil, 0, released)
        assert(released.Gamepad.bRightTrigger == 0, "hook-set press is released after its short pulse")
        assert(has(W, "fishing hook%-set gesture: upward twitch"), table.concat(W.logs, " | "))
        local hits = 0
        for _, line in ipairs(W.logs) do if line:find("fishing hook%-set gesture: upward twitch") then hits = hits + 1 end end
        assert(hits == 1, "one hook set per bite QTE")
        W.right = function() return v(0.2, 1.2, -0.3) end
        run(W, 0.1)
        local second_start = W.t
        W.right = function(t)
            local a = math.min(1, math.max(0, (t - second_start) / 0.16))
            return v(0.2, 1.2 + 0.20 * a, -0.3)
        end
        local second_twitch = false
        for _ = 1, 12 do
            W.t = W.t + DT
            W.callbacks.tick(nil, DT)
            local s = { Gamepad = { bRightTrigger = 0 } }
            W.callbacks.xinput(nil, 0, s)
            if s.Gamepad.bRightTrigger == 255 then second_twitch = true end
        end
        assert(not second_twitch, "one bite QTE accepts only one upward twitch")
        no_failures(W)
    end,

    test_fishing_cast_right_ear_load_then_forward_extension_presses_and_releases_cast = function()
        local W = world("None", false)
        W.set_mode("fishing")
        W.native_pose_enabled = true
        W.controllers_active = false
        W.pawn.StrugglingFish = nil
        W.right = function() return v(0.2, 1.65, 0.10) end -- right ear, slightly behind head
        run(W, 0.2)
        local loaded = { Gamepad = { bRightTrigger = 0, sThumbRX = 1234, sThumbRY = -2345 } }
        W.callbacks.xinput(nil, 0, loaded)
        assert(loaded.Gamepad.bRightTrigger == 255, "ear load holds IA_Fishing_Cast to charge power; got " .. tostring(loaded.Gamepad.bRightTrigger) .. "; logs=" .. table.concat(W.logs, " | "))
        assert(loaded.Gamepad.sThumbRX == 1234 and loaded.Gamepad.sThumbRY == -2345,
            "cast gesture does not write camera look axes")

        W.right = function() return v(0.2, 1.65, -0.32) end -- extend forward to throw
        run(W, 0.1)
        local released = { Gamepad = { bRightTrigger = 0, sThumbRX = 1234, sThumbRY = -2345 } }
        W.callbacks.xinput(nil, 0, released)
        assert(released.Gamepad.bRightTrigger == 0, "forward extension releases IA_Fishing_Cast")
        assert(released.Gamepad.sThumbRX == 1234 and released.Gamepad.sThumbRY == -2345,
            "cast release still leaves camera axes untouched")
        assert(has(W, "fishing cast gesture: charging from right%-ear load"), table.concat(W.logs, " | "))
        assert(has(W, "fishing cast gesture: released at forward reach"), table.concat(W.logs, " | "))
        no_failures(W)
    end,

    test_fishing_native_invalidity_releases_a_held_cast = function()
        local W = world("None", false)
        W.set_mode("fishing")
        W.pawn.StrugglingFish = nil
        W.native_pose_enabled = true
        W.controllers_active = false
        W.right = function() return v(0.2, 1.65, 0.10) end -- right ear load
        run(W, 0.25)
        local state = { Gamepad = { bRightTrigger = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 255, "native-valid cast pose holds the cast trigger despite false UEVR hint")

        W.native_pose_valid.R = false
        run(W, 0.05)
        state.Gamepad.bRightTrigger = 73
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 73, "invalid native right pose releases cast and preserves physical trigger")
        assert(has(W, "fishing cast fail%-safe"), "cast invalidity is reported: " .. table.concat(W.logs, " | "))
        no_failures(W)
    end,

    test_fishing_native_invalidity_releases_hook_set_pulse = function()
        local W = world("None", false)
        W.set_mode("fishing")
        W.native_pose_enabled = true
        W.controllers_active = false
        W.pawn.CurrentQTE = gameplay_tag("QTE.Type.FishingBite")
        run(W, 0.08) -- hook-set baseline
        local start_time = W.t
        W.right = function(t)
            local a = math.min(1, math.max(0, (t - start_time) / 0.16))
            return v(0.2, 1.2 + 0.20 * a, -0.3)
        end
        local pulsed = false
        for _ = 1, 12 do
            W.t = W.t + DT
            W.callbacks.tick(nil, DT)
            local state = { Gamepad = { bRightTrigger = 0 } }
            W.callbacks.xinput(nil, 0, state)
            if state.Gamepad.bRightTrigger == 255 then pulsed = true; break end
        end
        assert(pulsed, "valid native right pose sets the hook despite false UEVR hint")

        W.native_pose_valid.R = false
        run(W, 0.03)
        local released = { Gamepad = { bRightTrigger = 73 } }
        W.callbacks.xinput(nil, 0, released)
        assert(released.Gamepad.bRightTrigger == 73, "invalid native pose immediately cancels the hook-set pulse")
        assert(has(W, "fishing hook%-set fail%-safe"), "hook-set invalidity is reported: " .. table.concat(W.logs, " | "))
        W.native_pose_valid.R = true
        W.right = function() return v(0.2, 1.2, -0.3) end
        run(W, 0.08) -- reacquire a fresh baseline within the same bite QTE
        local recovery_start = W.t
        W.right = function(t)
            local a = math.min(1, math.max(0, (t - recovery_start) / 0.16))
            return v(0.2, 1.2 + 0.20 * a, -0.3)
        end
        local second_pulse = false
        for _ = 1, 12 do
            W.t = W.t + DT
            W.callbacks.tick(nil, DT)
            local state = { Gamepad = { bRightTrigger = 0 } }
            W.callbacks.xinput(nil, 0, state)
            if state.Gamepad.bRightTrigger == 255 then second_pulse = true end
        end
        assert(not second_pulse, "tracking recovery cannot fire a second hook set in the same bite QTE")
        no_failures(W)
    end,

    test_boat_hands_drive_existing_axes_and_throttle_detents_haptically = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 1.5) -- wait for the initial stable-hand calibration
        local state = { Gamepad = { sThumbLX = 1234, sThumbLY = -2345 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0 and state.Gamepad.sThumbLY == 0,
            "first-person calibration holds both axes neutral instead of leaking physical sticks")
        move_left_x(W, 0.11)
        assert(W.haptics and W.haptic[5] == 1, "steering detents click the left controller")
        W.haptics = 0
        move_right_pose(W, 1.32, -0.42) -- extend the right hand forward from the hip/elbow reference
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 7500 and state.Gamepad.sThumbLX < 14000,
            "positive left-hand travel writes positive IA_BoatMove X, which selects the Blueprint +65-degree wheel target (got " .. tostring(state.Gamepad.sThumbLX) .. ")")
        local initial_forward = state.Gamepad.sThumbLY
        assert(initial_forward > 0 and initial_forward < 32767,
            "initial forward reach gives a proportional positive throttle value")
        move_right_pose(W, 1.32, -0.70) -- farther forward increases throttle continuously
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY > initial_forward and state.Gamepad.sThumbLY <= 32767,
            "farther forward reach increases throttle input")
        assert(W.haptic and W.haptic[2] == 0.025 and W.haptic[3] == 150 and W.haptic[4] == 0.45 and W.haptic[5] == 2,
            "right controller gets a short haptic click on throttle transition")
        assert(has(W, "boat throttle detent: forward"))
        move_right_pose(W, 1.2, -0.3) -- return to hip-fire neutral
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY == 0, "returning the hand to its calibrated height selects neutral")
        move_right_pose(W, 1.2, -0.05) -- deliberate full pull behind the hip reference
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY == -32767, "negative IA_BoatMove Y selects the Blueprint -22-degree reverse throttle target")
        assert(W.haptics == 3, "forward, neutral, and reverse each give one click")
        config("return { gestures = { enabled = true, boat_steer_range_m = 0.11 } }")
        run(W, 1.2)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 32000, "boat steering range reloads live")
        no_failures(W)
    end,

    test_boat_throttle_returns_from_reverse_through_neutral_to_forward = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 1.5) -- hip-fire neutral reference
        local state = { Gamepad = { sThumbLX = 0, sThumbLY = 0 } }

        -- Vary hand height while translating along the SteamVR forward/back axis. Throttle
        -- direction is reach (Z), so changing elbow/hand height alone cannot hold reverse.
        move_right_pose(W, 1.05, -0.05, 2.0) -- deliberate pull back toward/behind the hip
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY == -32767, "hand drawn back to hip selects reverse")

        move_right_pose(W, 1.32, -0.30, 2.0) -- return to neutral at a different height
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY == 0, "passing through calibrated reach releases reverse to neutral")

        move_right_pose(W, 1.15, -0.42, 2.0) -- reach forward with the elbow still near the hip
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLY > 0, "hand extended forward from the elbow selects forward throttle")
        assert(has(W, "boat throttle detent: reverse") and has(W, "boat throttle detent: neutral")
            and has(W, "boat throttle detent: forward"), "all throttle detents are observed in order")
        no_failures(W)
    end,

    test_boat_gestures_only_override_axes_in_first_person = function()
        local W = world("None", false)
        W.set_mode("boat", false)
        run(W, 0.1)
        local state = { Gamepad = { sThumbLX = 12345, sThumbLY = -23456, sThumbRX = 23456, sThumbRY = -12345 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 12345 and state.Gamepad.sThumbLY == -23456
            and state.Gamepad.sThumbRX == 23456 and state.Gamepad.sThumbRY == -12345,
            "third-person native steering and throttle pass through unchanged")
        assert(has(W, "boat third"), table.concat(W.logs, " | "))

        W.pawn.bFirstPersonCameraEnabled = true
        run(W, 1.5) -- stable placement poll before first-person control
        move_left_x(W, 0.11)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 7500 and state.Gamepad.sThumbLX < 14000,
            "first-person left-hand steering takes over the existing X axis")
        assert(state.Gamepad.sThumbRX == 0 and state.Gamepad.sThumbRY == 0,
            "first-person helm suppresses gamepad look axes while head tracking remains active")

        W.pawn.bFirstPersonCameraEnabled = false
        run(W, 0.1)
        state.Gamepad.sThumbLX, state.Gamepad.sThumbLY = 12345, -23456
        state.Gamepad.sThumbRX, state.Gamepad.sThumbRY = 23456, -12345
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 12345 and state.Gamepad.sThumbLY == -23456
            and state.Gamepad.sThumbRX == 23456 and state.Gamepad.sThumbRY == -12345,
            "returning to third-person immediately restores native move and look axes")
        assert(has(W, "boat gestures paused; native axes restored"))
        no_failures(W)
    end,

    test_boat_requires_native_pose_validity_and_recovers_with_recalibration = function()
        local W = world("None", false)
        W.set_mode("boat")
        W.native_pose_enabled = true
        W.native_pose_order = { "R", "L" } -- either event may arrive first
        W.controllers_active = false
        run(W, 1.5) -- calibration succeeds from valid poses even if the runtime flag is false
        move_left_x(W, 0.11)
        local state = { Gamepad = { sThumbLX = 12345, sThumbLY = -23456 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 7500,
            "native-valid hand poses steer when is_using_controllers reports false")

        W.native_pose_valid.R = false -- one invalid hand is enough to stop both axes
        run(W, 0.1) -- UEVR continues returning finite, unchanged pose coordinates
        state.Gamepad.sThumbLX, state.Gamepad.sThumbLY = 12345, -23456
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0 and state.Gamepad.sThumbLY == 0,
            "native-invalid hand pose holds axes neutral despite stale finite UEVR coordinates")
        assert(has(W, "native_pose_valid=false"), "native invalidity is logged: " .. table.concat(W.logs, " | "))

        W.native_pose_valid.R = true
        W.native_pose_paused = true
        run(W, 0.6) -- no validity event for >500 ms makes cached validity stale
        state.Gamepad.sThumbLX, state.Gamepad.sThumbLY = 12345, -23456
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0 and state.Gamepad.sThumbLY == 0,
            "missing native heartbeat expires and holds axes neutral")

        W.native_pose_paused = false
        W.left = function() return v(0, 1.2, -0.3) end
        run(W, 1.5) -- return to neutral and allow a fresh stable calibration
        move_left_x(W, 0.22)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 32000,
            "restored native validity recalibrates and resumes full steering")

        W.pose_read_fails = true
        run(W, 0.1)
        state.Gamepad.sThumbLX, state.Gamepad.sThumbLY = 12345, -23456
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0 and state.Gamepad.sThumbLY == 0,
            "UEVR pose read errors also hold first-person axes neutral")
        no_failures(W)
    end,

    test_boat_head_turn_after_calibration_does_not_change_steering = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 1.5)
        move_left_x(W, 0.11)
        run(W, 0.5) -- let steering smoothing settle before comparing frames
        local state = { Gamepad = { sThumbLX = 0, sThumbLY = 0 } }
        W.callbacks.xinput(nil, 0, state)
        local before = state.Gamepad.sThumbLX
        assert(before > 0, "rightward left-hand travel produces positive wheel input")

        -- Turn the HMD 90 degrees around world-up while leaving tracked hand positions fixed.
        W.head_q = { x = 0, y = math.sin(math.pi / 4), z = 0, w = math.cos(math.pi / 4) }
        W.camera_rotation = { Pitch = 1, Yaw = 42, Roll = 3 }
        W.boat_rotation = { Pitch = 0, Yaw = 60, Roll = 0 }
        run(W, 0.5)
        W.callbacks.xinput(nil, 0, state)
        assert(math.abs(state.Gamepad.sThumbLX - before) < 100,
            "head yaw after helm calibration does not rotate the frozen steering reference frame")
        run(W, 1.2)
        assert(has(W, "boat view: uevr_controllers=true poses_valid=Ltrue,Rtrue,Htrue native_valid=true hmd_q=")
            and has(W, "camera_rot=%(1%.0,42%.0,3%.0%)")
            and has(W, "boat_rot=%(0%.0,60%.0,0%.0%)"),
            "low-rate helm view diagnostics distinguish head orientation, camera rotation, and boat yaw: " .. table.concat(W.logs, " | "))
        assert(has(W, "boat gesture deltas: steer_x="), "helm telemetry includes steering and throttle deltas from calibration")
        no_failures(W)
    end,

    test_boat_harness_checks_both_rudder_directions_and_center_deadzone = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 1.5) -- calibrate the neutral hand positions
        local state = { Gamepad = { sThumbLX = 0, sThumbLY = 0 } }
        move_left_x(W, 0.22, 1.2); W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 32000, "22 cm right hand travel reaches near-full right rudder")
        move_left_x(W, -0.22, 1.2); W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX < -32000, "22 cm left hand travel reaches near-full left rudder")
        move_left_x(W, 0.01, 1.2); W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0, "small hand drift stays in the steering center deadzone")
        no_failures(W)
    end,

    test_boat_wheel_arc_keeps_top_straight_and_clicks_left_hand_detents = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 1.5)
        local state = { Gamepad = { sThumbLX = 0, sThumbLY = 0 } }
        W.left = function() return v(0.10, 1.2, -0.3) end -- rightward, but still at wheel top
        run(W, 0.4)
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0, "top-of-wheel hand motion stays straight until it drops into the arc")

        move_left_pose(W, -0.31, 1.14) -- left and slightly down
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX < -8000, "left-and-down wheel arc selects left rudder")
        assert(W.haptics and W.haptic[2] == 0.012 and W.haptic[4] == 0.20 and W.haptic[5] == 1,
            "small left-hand clicks provide steering-step feedback")
        local clicks_at_hold = W.haptics
        run(W, 0.5)
        assert(W.haptics == clicks_at_hold, "holding a steering step does not buzz continuously")

        move_left_pose(W, 0.21, 1.14) -- right and slightly down
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 8000, "right-and-down wheel arc selects right rudder")

        move_left_pose(W, -0.2, 1.2) -- hand back at the top
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 0, "returning the hand to the top centers the wheel")
        no_failures(W)
    end,

    test_boat_harness_copies_cosmetic_wheel_after_game_tick = function()
        local W = world("None", false)
        W.set_mode("boat")
        run(W, 1.5)
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
        local parked = W.left(W.t)
        W.left = function() return parked end -- stop without teleporting through jump fail-safe
        run(W, 0.4) -- exceed the crank detector's 0.25 s active grace
        local state = { Gamepad = { bRightTrigger = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 0, "reel trigger releases after crank stops")
        assert(not has(W, "implausible pose jump"), "normal crank stop does not use the pose-spike fail-safe")
        no_failures(W)
    end,

    test_fishing_rod_lean_writes_fight_axis = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.6) -- calibrate neutral
        local start_time = W.t
        W.right = function(t)
            local a = math.min(1, math.max(0, (t - start_time) / 0.4))
            return v(0.2 + 0.2 * a, 1.2, -0.3)
        end
        run(W, 0.5)
        local state = { Gamepad = { bRightTrigger = 0, sThumbLX = 0, sThumbLY = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 15000, "rod lean should write signed fishing fight X")
        assert(state.Gamepad.sThumbLY == 0, "normal fight leaves physical Y untouched")
        no_failures(W)
    end,

    test_fishing_fight_axis_has_signed_lean_and_deadzone = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.6)
        W.right = function() return v(0.26, 1.2, -0.3) end -- +6 cm, inside 8 cm deadzone
        run(W, 0.1)
        local state = { Gamepad = { bRightTrigger = 0, sThumbLX = 4321, sThumbLY = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX == 4321, "fight deadzone preserves physical X input")

        local start_time = W.t
        W.right = function(t)
            local a = math.min(1, math.max(0, (t - start_time) / 0.4))
            return v(0.2 - 0.4 * a, 1.2, -0.3)
        end
        run(W, 0.5)
        state.Gamepad.sThumbLX = 0
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX < -15000, "leftward rod lean writes a negative fight X axis")
        no_failures(W)
    end,

    test_directional_drag_writes_two_stick_axes = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.6)
        W.pawn.CurrentQTE = gameplay_tag("QTE.Type.DirectionalDrag")
        W.t = W.t + DT
        W.callbacks.tick(nil, DT) -- calibrate QTE neutral
        local start_time = W.t
        W.right = function(t)
            local a = math.min(1, math.max(0, (t - start_time) / 0.4))
            return v(0.2 + 0.2 * a, 1.2 + 0.2 * a, -0.3)
        end
        run(W, 0.5)
        local state = { Gamepad = { bRightTrigger = 0, wButtons = 0x1000, sThumbLX = 0, sThumbLY = 0 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.sThumbLX > 15000 and state.Gamepad.sThumbLY > 15000,
            "directional drag should write right-hand X/Y movement to left stick")
        assert(state.Gamepad.bRightTrigger == 0, "fishing crank is suppressed during QTE")
        assert(state.Gamepad.wButtons == 0x1000,
            "DirectionalDrag preserves the physical A button while supplying drag axes")
        no_failures(W)
    end,

    test_fishing_tracking_loss_releases_gestures_and_recalibrates = function()
        local W = world("None", false)
        W.set_mode("fishing")
        W.native_pose_enabled = true
        W.controllers_active = false
        run(W, 0.3)
        cranking(W)
        run(W, 0.8)
        local state = { Gamepad = { bRightTrigger = 73, sThumbLX = 1234, sThumbLY = -2345 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 255, "valid native poses reel despite false UEVR controller hint")

        W.native_pose_valid.R = false -- one invalid hand fails the L+R fight gate
        run(W, 0.05)
        state.Gamepad.bRightTrigger = 73
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 73, "invalid native hand releases synthetic reel and preserves physical trigger")
        assert(state.Gamepad.sThumbLX == 1234 and state.Gamepad.sThumbLY == -2345,
            "native invalidity clears gesture axes and leaves physical stick input alone")
        assert(has(W, "native_pose_valid=false"), "native invalidity is reported: " .. table.concat(W.logs, " | "))

        W.native_pose_valid.R = true
        local parked = W.left(W.t)
        W.left = function() return parked end
        run(W, 0.6)
        assert(has(W, "fishing fight gesture: calibrated"), "valid tracking reacquires a fresh fish neutral pose")
        cranking(W)
        run(W, 0.8)
        state.Gamepad.bRightTrigger = 73
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 255, "recovered validity allows reel after recalibration")

        W.native_pose_paused = true
        run(W, 0.6)
        state.Gamepad.bRightTrigger = 73
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 73, "stale validity heartbeat releases an active reel")
        no_failures(W)
    end,

    test_fishing_zero_hmd_pose_releases_reel_and_fight_reference = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.6)
        cranking(W)
        run(W, 0.8)
        local state = { Gamepad = { bRightTrigger = 0, sThumbLX = 1234, sThumbLY = -2345 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 255, "valid fish fight enters held reel input")

        W.head_pose = v(0, 0, 0)
        run(W, 0.05)
        state.Gamepad.bRightTrigger = 73
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 73,
            "tracking-origin HMD releases synthetic reel and preserves the game's physical trigger")
        assert(state.Gamepad.sThumbLX == 1234 and state.Gamepad.sThumbLY == -2345,
            "tracking-origin HMD clears fishing pose references without overwriting physical sticks")
        assert(has(W, "HMD pose at tracking origin"), "fishing logs the shared HMD tracking failure")
        no_failures(W)
    end,

    test_fishing_pose_spike_is_rejected_before_axis_write = function()
        local W = world("None", false)
        W.set_mode("fishing")
        run(W, 0.3)
        W.right = function() return v(0.5, 1.2, -0.3) end -- plausible coordinates, implausible one-frame speed
        W.t = W.t + DT
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 41, sThumbLX = 1234, sThumbLY = 5678 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 41, "bad pose does not synthesize reel input")
        assert(state.Gamepad.sThumbLX == 1234 and state.Gamepad.sThumbLY == 5678,
            "bad pose does not overwrite physical axes")
        assert(has(W, "implausible pose jump"), "pose discontinuity is logged")
        W.right = function() return v(0.2, 1.2, -0.3) end
        run(W, 0.1)
        assert(has(W, "fishing fight gesture: calibrated"), "pose recovery captures a new neutral reference")
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
