-- Smoke test: runs the real m2_arms.lua and its lib modules against a fake UEVR and a fake game
-- for ~15 s of frames. Checks the whole bridge wires up without errors, pushes the tuning into
-- UEVR, moves a hand-held item onto the VR arms and gives it back. Staged under build/smoke.
local STAGE = "build/smoke/"
local LIBS = { "gameapi", "modes", "armsloader", "m1flow", "armsflow", "armstats", "tuning", "wristfit", "ubik", "itemfollow", "gestures", "reticle", "boatcontrols" }

local function copy(src, dst)
    local i = assert(io.open(src, "rb")); local s = i:read("a"); i:close()
    local o = assert(io.open(dst, "wb")); o:write(s); o:close()
end
local function write(path, s) local o = assert(io.open(path, "wb")); o:write(s); o:close() end

local function stage(tuning_text)
    os.execute('mkdir "build\\smoke\\scripts\\lib" 2>nul')
    copy("src/scripts/m2_arms.lua", STAGE .. "scripts/m2_arms.lua")
    copy("src/scripts/m3_gestures.lua", STAGE .. "scripts/m3_gestures.lua")
    for _, m in ipairs(LIBS) do copy("src/scripts/lib/" .. m .. ".lua", STAGE .. "scripts/lib/" .. m .. ".lua") end
    write(STAGE .. "dreadmoorvr_arms_tuning.lua", tuning_text)
end

local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function fname(s) return { to_string = function() return s end } end

-- Fake world -------------------------------------------------------------------------------
local function make_world()
    local W = { logs = {}, mods = { VR_AimMethod = "1", VR_MovementOrientation = "0", VR_RoomscaleMovement = "true" }, offsets = {}, callbacks = {} }
    local next_addr = 0x1000
    local function obj(t) next_addr = next_addr + 0x10; local a = next_addr; t.get_address = function() return a end
        t.get_full_name = function() return t.name or "obj" end; return t end

    local PARENT = { pelvis = "root", spine_01 = "pelvis", neck_01 = "spine_01", head = "neck_01",
        clavicle_l = "spine_01", upperarm_l = "clavicle_l", lowerarm_l = "upperarm_l", hand_l = "lowerarm_l",
        clavicle_r = "spine_01", upperarm_r = "clavicle_r", lowerarm_r = "upperarm_r", hand_r = "lowerarm_r" }
    -- Skeleton sockets -> bone, from SK_DreadMoreSkeleton (docs/research/2026-11-17-held-items.md).
    -- Bone names as the live game reports them (log 16:50): Hand_R, Head.
    local SOCKETS = { HookSimple = "Hand_R", KnifeSocket = "Hand_R", Harpoon_Socket = "Hand_R", Camera = "Head" }
    local BONES = { head = v(0, 0, 165), clavicle_l = v(0, -5, 145), upperarm_l = v(0, -20, 145),
        lowerarm_l = v(0, -20, 117), hand_l = v(0, -20, 91), clavicle_r = v(0, 5, 145),
        upperarm_r = v(0, 20, 145), lowerarm_r = v(0, 20, 117), hand_r = v(0, 20, 91) }
    for _, f in ipairs({ "middle_01", "index_01", "pinky_01" }) do
        BONES[f .. "_l"] = v(5, -20, 86); BONES[f .. "_r"] = v(5, 20, 86)
    end
    local function mesh(name)
        return obj({ name = name, hidden = {},
            GetSocketLocation = function(_, b) return BONES[b] or v(0, 0, 0) end,
            GetSocketRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
            GetSocketTransform = function(self, s) return { socket = s, on = self.name } end,
            GetSocketBoneName = function(_, s) return fname(SOCKETS[s] or s) end,
            GetParentBone = function(_, b) return fname(PARENT[b] or "None") end,
            DoesSocketExist = function(_, s) return PARENT[s] ~= nil or SOCKETS[s] ~= nil end,
            HideBoneByName = function(self, b) self.hidden[b] = true end,
            UnHideBoneByName = function(self, b) self.hidden[b] = nil end,
            K2_AttachToComponent = function() return true end })
    end
    local function attachable(name, parent, socket)
        local c = obj({ name = name, parent = parent, socket = socket })
        c.GetAttachSocketName = function(self) return fname(self.socket) end
        c.GetAttachParent = function(self) return self.parent end
        c.rel = { grip = name }   -- the game's grip offset (EquipTransform)
        c.GetRelativeTransform = function(self) return self.rel end
        c.K2_SetRelativeTransform = function(self, t) self.rel_set = t end
        c.K2_SetWorldTransform = function(self, t) self.world = t; W.placements = (W.placements or 0) + 1 end
        -- Like the engine: moving a component takes it out of the old parent's AttachChildren and
        -- puts it in the new one's.
        c.K2_AttachToComponent = function(self, p, s)
            local old = self.parent and self.parent.AttachChildren
            if old then for i = #old, 1, -1 do if old[i] == self then table.remove(old, i) end end end
            p.AttachChildren = p.AttachChildren or {}
            table.insert(p.AttachChildren, self)
            self.parent = p; self.socket = s; return true
        end
        return c
    end
    local function target(loc)
        return obj({ location = loc, forward = v(1, 0, 0), right = v(0, 1, 0), up = v(0, 0, 1),
            K2_GetComponentLocation = function(self) return self.location end,
            K2_GetComponentRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
            GetForwardVector = function(self) return self.forward end,
            GetRightVector = function(self) return self.right end,
            GetUpVector = function(self) return self.up end })
    end

    local pawn_mesh = mesh("GameMesh")
    local anim_fn = { hook_ptr = function(_, pre, post) W.anim_post = post end }
    W.anim = { ControlRotaton = { x = 0, y = 90, z = 0 },
        get_class = function() return { get_fname = function() return fname("ABP_V03_C") end,
            find_function = function(_, n) return n == "BlueprintUpdateAnimation" and anim_fn or nil end } end }
    pawn_mesh.GetAnimInstance = function() return W.anim end
    W.camera = attachable("Camera", pawn_mesh, "head")
    W.attachable = attachable
    W.gun = attachable("BP_HookGunEquipment.DefaultSceneRoot", pawn_mesh, "HookSimple")
    W.hook_visible = true   -- BP_HookGunEquipment.Hook: hidden while the hook is out
    local gun_actor = { Hook = { IsVisible = function() return W.hook_visible end } }
    W.gun.GetOwner = function() return gun_actor end
    pawn_mesh.AttachChildren = { W.camera, W.gun }
    W.pawn_mesh = pawn_mesh

    local chain = { "BP_PlayerCharacter_C", "DrdPlayerCharacter", "Character", "Pawn", "Actor", "Object" }
    local function class_at(i)
        if i > #chain then return nil end
        return { get_fname = function() return fname(chain[i]) end, get_super_struct = function() return class_at(i + 1) end }
    end
    W.boat_socket_shift = v(0, 0, 0)
    local function shift_location(p)
        return v(p.X + W.boat_socket_shift.X, p.Y + W.boat_socket_shift.Y, p.Z + W.boat_socket_shift.Z)
    end
    local wheel_component = mesh("Wheel")
    wheel_component.GetSocketLocation = function(_, socket)
        return shift_location(socket == "LHand_Socket" and v(10, -20, 100) or v(15, 20, 90))
    end
    local throttle_component = mesh("Throttle")
    throttle_component.GetSocketLocation = function(_, socket)
        return shift_location(socket == "RHand" and v(15, 20, 90) or v(0, 0, 0))
    end
    W.shift_boat_sockets = function(dx, dy, dz)
        W.boat_socket_shift = v(W.boat_socket_shift.X + dx, W.boat_socket_shift.Y + dy, W.boat_socket_shift.Z + dz)
    end
    W.translate_boat_frame = function(dx, dy, dz)
        W.shift_boat_sockets(dx, dy, dz)
        for _, hand_target in ipairs({ W.arms.LeftHandTarget, W.arms.RightHandTarget }) do
            local p = hand_target.base_location or hand_target.location
            hand_target.base_location = v(p.X + dx, p.Y + dy, p.Z + dz)
            hand_target.location = hand_target.base_location
        end
    end
    W.pawn = obj({ name = "Pawn", Mesh = pawn_mesh,
        BP_ShipSteeringWheel = { ChildActor = { Small_Boat_Steerwheel = wheel_component } },
        Throttle_lever = throttle_component,
        get_class = function() return class_at(1) end,
        RootComponent = obj({ name = "BoatRoot", AttachChildren = {} }),
        GetTransform = function() return {} end, K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end })
    W.set_mode = function(mode)
        chain = mode == "boat" and { "BP_SmallBoat_V2_C", "DrdShipBase", "Pawn" }
            or mode == "fishing" and { "BP_FishingController_C", "DrdFishingControllerBase", "Pawn" }
            or { "BP_PlayerCharacter_C", "DrdPlayerCharacter", "Character", "Pawn", "Actor", "Object" }
        W.pawn.bFirstPersonCameraEnabled = mode == "boat"
    end
    -- A replacement pawn (respawn, level load): a fresh mesh with nothing attached.
    W.new_pawn = function()
        local m = mesh("GameMesh2"); m.AttachChildren = {}
        W.class_loaded = false   -- the engine unloads BP_VRArms with the old pawn (in game 16:42)
        W.pawn = obj({ name = "Pawn2", Mesh = m, get_class = W.pawn.get_class,
            GetTransform = W.pawn.GetTransform, K2_GetActorRotation = W.pawn.K2_GetActorRotation })
        return W.pawn
    end

    -- Each spawn makes a new arms actor. A dead one (it died with its pawn) throws on use.
    W.spawns = 0
    local function new_arms()
        W.spawns = W.spawns + 1
        W.finger_anim = { get_class = function() return { get_fname = function() return fname("ABP_VRArms_C") end } end }
        local body = mesh("Body" .. W.spawns)
        body.GetAnimInstance = function()
            if W.finger_anim_nil then return nil end
            return W.finger_anim
        end
        body.K2_AttachToComponent = function(self, p)
            if self.dead then error("arms actor is gone") end
            local old = self.parent and self.parent.AttachChildren
            if old then for i = #old, 1, -1 do if old[i] == self then table.remove(old, i) end end end
            p.AttachChildren = p.AttachChildren or {}; table.insert(p.AttachChildren, self)
            self.parent = p; return true
        end
        body.GetAttachParent = function(self) return self.parent end
        body.SetHiddenInGame = function(self, hidden) self.hidden_in_game = hidden end
        W.body = body
        W.arms = obj({ name = "BP_VRArms", Body = body,
            LeftHandTarget = target(v(30, -25, 110)), RightHandTarget = target(v(30, 25, 110)),
            SetActorHiddenInGame = function(_, hidden) W.hidden = hidden end,
            K2_DestroyActor = function(self) self.destroyed = true end })
        return W.arms
    end

    local gs = { BeginDeferredActorSpawnFromClass = function() return new_arms() end,
        FinishSpawningActor = function(_, a) return a end }
    local arms_class = { get_class_default_object = function() return {} end }
    W.motion_states = {}
    local function apply_controller_offset(state)
        local hand_target, off = state.target, state.offset
        if not W.simulate_location_offsets or off == nil or hand_target.base_location == nil then return end
        local forward, right, up = hand_target:GetForwardVector(), hand_target:GetRightVector(), hand_target:GetUpVector()
        local d = { X = right.X * off.x + up.X * off.y - forward.X * off.z,
            Y = right.Y * off.x + up.Y * off.y - forward.Y * off.z,
            Z = right.Z * off.x + up.Z * off.y - forward.Z * off.z }
        local base = hand_target.base_location
        hand_target.location = v(base.X + d.X, base.Y + d.Y, base.Z + d.Z)
    end
    W.apply_controller_offsets = function()
        for _, motion_state in pairs(W.motion_states) do apply_controller_offset(motion_state) end
    end
    W.set_controller_basis = function(side, forward, right, up)
        local hand_target = side == "L" and W.arms.LeftHandTarget or W.arms.RightHandTarget
        hand_target.forward, hand_target.right, hand_target.up = forward, right, up
    end
    local function state(hand)
        local s = { hand = hand, target = hand }
        s.set_hand = function(self, h) self.hand = h end
        s.set_permanent = function() end
        s.set_location_offset = function(self, off)
            W.offsets[#W.offsets + 1] = off
            self.offset = { x = off.x, y = off.y, z = off.z }
            apply_controller_offset(self)
        end
        W.motion_states[hand == W.arms.LeftHandTarget and "L" or "R"] = s
        return s
    end

    _G.Vector3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.UEVR_Vector3f = { new = function() return { x = 0, y = 0, z = 0 } end }
    _G.UEVR_Quaternionf = { new = function() return { x = 0, y = 0, z = 0, w = 1 } end }
    _G.UEVR_UObjectHook = { activate = function() end, get_or_add_motion_controller_state = function(o) return state(o) end }
    -- UEVR calls every script's callback, so registrations chain.
    local function reg(name) return function(fn)
        local prev = W.callbacks[name]
        W.callbacks[name] = prev and function(...) prev(...); return fn(...) end or fn
    end end
    _G.uevr = {
        params = {
            functions = { log_info = function(s) W.logs[#W.logs + 1] = s end },
            vr = {
                set_mod_value = function(k, val) W.mods[k] = val end,
                get_mod_value = function(k) return W.mods[k] end,
                get_hmd_index = function() return 0 end,
                get_left_controller_index = function() return 1 end,
                get_right_controller_index = function() return 2 end,
                get_pose = function(i, p, q)
                    if W.pose then local r = W.pose(i, W.t or 0); p.x, p.y, p.z = r.X, r.Y, r.Z
                    else p.x, p.y, p.z = (i == 1 and -0.2 or i == 2 and 0.2 or 0), (i == 0 and 1.6 or 1.2), -0.3 end
                    if q then q.x, q.y, q.z, q.w = 0, 0, 0, 1 end
                end,
            },
        },
        sdk = { callbacks = {
            on_lua_event = reg("lua_event"), on_pre_engine_tick = reg("tick"), on_script_reset = reg("reset"),
            on_post_calculate_stereo_view_offset = reg("view"), on_xinput_get_state = reg("xinput"),
        } },
        api = {
            get_local_pawn = function() return W.pawn end,
            get_engine = function() return { GameViewport = { World = {} } } end,
            find_uobject = function(_, name)
                if name:find("BP_VRArms") then return W.class_loaded ~= false and arms_class or nil end
                if name:find("StaticMeshActor") or name:find("Sphere") or name:find("HitResult") then return nil end
                if name == "Class /Script/Engine.KismetMathLibrary" then
                    return { get_class_default_object = function() return {
                        ComposeTransforms = function(_, a, b) return { a = a, b = b } end,
                        MakeTransform = function(_, loc, rot, sc) return { rot = rot } end } end }
                end
                if name == "BlueprintGeneratedClass /InventoryFrameworkPlugin/Core/ActorParents/SubObjects/SO_ExecuteEquipmentData.SO_ExecuteEquipmentData_C" then
                    return { get_fname = function() return fname("SO_ExecuteEquipmentData_C") end,
                        find_function = function(_, n)
                            if n ~= "ExecuteUnequipmentInformation" then return nil end
                            return { hook_ptr = function(_, pre) W.unequip_pre = pre end }
                        end }
                end

                return { get_class_default_object = function() return gs end }
            end,
            dispatch_custom_event = function(_, name, data)
                if name == "dreadmoorvr_request_class" then W.class_loaded = true; W.pending_reply = "ok|" .. data end
            end,
        },
    }
    return W
end

local function run(W, seconds)
    for _ = 1, math.floor(seconds / 0.05) do
        if W.pending_reply then local r = W.pending_reply; W.pending_reply = nil; W.callbacks.lua_event("dreadmoorvr_class_loaded", r) end
        if W.callbacks.view then
            W.callbacks.view(nil, 0, 100, { x = 10, y = 0, z = 170 }, { x = 0, y = 0, z = 0 }, true)
            W.callbacks.view(nil, 1, 100, { x = 10, y = 0, z = 170 }, { x = 0, y = 0, z = 0 }, true)
        end
        -- UObjectHook reapplies its saved controller-local offset through the *current* basis
        -- before each script tick. Simulate that engine step so wrist rotations expose stale-frame
        -- subtraction regressions in the real bridge math.
        if W.apply_controller_offsets then W.apply_controller_offsets() end
        W.t = (W.t or 0) + 0.05
        W.callbacks.tick(nil, 0.05)
        -- The game's anim update: ABP_V03 copies control rotation (pitch 35 = hand raised), then
        -- any post-hook runs, then the Control Rig reads it.
        W.anim.ControlRotaton.x = 35
        if W.anim_post then W.anim_post(nil, W.anim) end
        W.rig_pitch = W.anim.ControlRotaton.x
        if W.callbacks.xinput then
            local st = { Gamepad = { bRightTrigger = 0 } }
            W.callbacks.xinput(nil, 0, st)
            local down = st.Gamepad.bRightTrigger > 128
            if down and not W.was_down then W.presses = (W.presses or 0) + 1 end
            W.was_down = down
        end
    end
end

local function has(logs, pat) for _, l in ipairs(logs) do if l:find(pat) then return true end end return false end
local function failures(logs)
    local out = {}
    for _, l in ipairs(logs) do if l:find("FAILED") then out[#out + 1] = l end end
    return table.concat(out, "\n")
end

local TUNING_ON = [[
return { grip_back = 8, shoulder_widen = 5, camera_forward = -12, boat_camera_forward = -30, camera_up = 0,
         aim_method = 2, movement_orientation = 1, items_follow_hands = true, level_torso = true,
         item_rot = { y = 15 } }
]]

-- Loads the given scripts the way UEVR does: no working require.
local function load_scripts(W, scripts)
    local saved, saved_require = package.path, require
    package.path = STAGE .. "scripts/?.lua;" .. saved
    _G.require = function(n) error("UEVR has no working require (asked for " .. tostring(n) .. ")") end
    local ok, err = pcall(function()
        for _, sc in ipairs(scripts) do assert(loadfile(STAGE .. "scripts/" .. sc .. ".lua"))() end
    end)
    _G.require, package.path = saved_require, saved
    assert(ok, "load failed: " .. tostring(err))
end

local function boot(scripts, before_run)
    stage(TUNING_ON)
    local W = make_world()
    if before_run then before_run(W) end
    load_scripts(W, scripts or { "m2_arms" })
    run(W, 15)
    return W
end

return {
    test_bridge_runs_without_failures = function()
        local W = boot()
        local f = failures(W.logs)
        assert(f == "", "FAILED lines:\n" .. f)
        assert(has(W.logs, "spawned BP_VRArms"), "arms spawned")
        assert(W.body.hidden.neck_01, "VR arms' own head hidden, or the view sits inside it")
        assert(has(W.logs, "tuning applied"), "tuning pushed into BP_VRArms")
        assert(has(W.logs, "arm L target="), "harness sampled")
        assert(has(W.logs, "fit eye_ahead="), "fit line logged")
    end,

    test_uevr_settings_and_grip_offset_are_pushed = function()
        local W = boot()
        assert(W.mods.VR_AimMethod == "2", "aim " .. tostring(W.mods.VR_AimMethod))
        assert(W.mods.VR_MovementOrientation == "1", "movement " .. tostring(W.mods.VR_MovementOrientation))
        assert(tonumber(W.mods.VR_CameraForwardOffset) == -12 and tonumber(W.mods.VR_CameraUpOffset) == 0)
        assert(#W.offsets == 2 and W.offsets[1].z == 8, "grip_back on both controllers")
    end,

    test_held_item_moves_to_vr_hand_and_camera_stays = function()
        local W = boot()
        -- The tool stays where the game put it, so the game's own unequip can find it.
        assert(W.gun.parent == W.pawn_mesh and W.gun.socket == "HookSimple", "stays attached to the game mesh")
        local w = W.gun.world
        assert(w and w.a.rot.Yaw == 15 and w.b.a == W.gun.rel and
            w.b.b.socket == "HookSimple" and w.b.b.on == W.body.name,
            "placed every frame at the VR hand's HookSimple with the game's grip offset")
        assert(W.camera.world == nil, "camera untouched")
        assert(has(W.logs, "held item %-> VR hand R"), "logged")
    end,

    test_finger_curls_drive_independent_anim_channels_and_fail_open = function()
        local W = boot()
        W.callbacks.lua_event("dreadmoorvr_finger_curls", "L|1.000,0.000,0.500,0.250,1.000")
        run(W, 0.05)
        assert(W.finger_anim.FingerCurlLThumb > 0.5, "left thumb channel receives curl")
        assert(W.finger_anim.FingerCurlLIndex == 0, "open index remains independent")
        assert(W.finger_anim.FingerCurlLMiddle > 0.25 and W.finger_anim.FingerCurlLMiddle < 0.5,
            "middle channel receives its own smoothed value")
        assert(W.finger_anim.FingerCurlLRing > 0 and W.finger_anim.FingerCurlLPinky > 0.5,
            "ring and pinky channels map independently")
        assert(W.finger_anim.FingerCurlRThumb == 0 and W.finger_anim.FingerCurlRIndex == 0,
            "left hand sample does not affect right hand")

        W.callbacks.lua_event("dreadmoorvr_finger_curls", "L|inactive")
        run(W, 0.1)
        assert(W.finger_anim.FingerCurlLThumb < 0.5, "inactive tracking eases fingers open")

        W.callbacks.lua_event("dreadmoorvr_finger_curls", "R|1.000,1.000,1.000,1.000,1.000")
        run(W, 0.05)
        assert(W.finger_anim.FingerCurlRIndex > 0.5, "right hand maps independently")
        run(W, 0.8) -- No further sensor events: stale curls must fail open if the plugin disappears.
        assert(W.finger_anim.FingerCurlRIndex < 0.01, "stale tracking sample returns the hand to open")
        assert(has(W.logs, "finger AnimInstance=ABP_VRArms_C property probe PASS"), "AnimBP finger property is writable and readable")
        assert(has(W.logs, "finger animation readback: ABP_VRArms_C Lindex="), "AnimInstance index properties are read back after writes")
        assert(failures(W.logs) == "", failures(W.logs))
    end,

    test_finger_anim_nil_is_reported_then_live_index_readbacks_follow_input = function()
        local W = boot(nil, function(world) world.finger_anim_nil = true end)
        assert(has(W.logs, "finger AnimInstance unavailable: Body:GetAnimInstance returned nil"),
            "nil AnimInstance has a visible diagnostic")
        assert(not has(W.logs, "finger AnimInstance=ABP_VRArms_C property probe PASS"),
            "probe waits until an AnimInstance exists")

        W.finger_anim_nil = false
        W.callbacks.lua_event("dreadmoorvr_finger_curls", "L|1.000,1.000,0.000,0.000,0.000")
        W.callbacks.lua_event("dreadmoorvr_finger_curls", "R|0.000,0.250,1.000,0.000,0.000")
        run(W, 0.25)
        assert(W.finger_anim.FingerCurlLIndex > 0.5 and W.finger_anim.FingerCurlRIndex > 0.1,
            "left and right index inputs independently reach AnimInstance properties")
        assert(W.finger_anim.FingerCurlLIndex > W.finger_anim.FingerCurlRIndex,
            "different per-hand curl values remain distinct")
        assert(has(W.logs, "finger animation readback: ABP_VRArms_C Lindex="),
            "logged AnimInstance class and post-write index readbacks")
        assert(failures(W.logs) == "", failures(W.logs))
    end,

    test_boat_socket_anchors_converge_without_compounding_and_restore = function()
        local W = boot()
        W.simulate_location_offsets = true -- UObjectHook replaces the controller's absolute location offset.
        W.arms.LeftHandTarget.location = v(W.arms.LeftHandTarget.location.X - 8,
            W.arms.LeftHandTarget.location.Y, W.arms.LeftHandTarget.location.Z)
        W.arms.RightHandTarget.location = v(W.arms.RightHandTarget.location.X - 8,
            W.arms.RightHandTarget.location.Y, W.arms.RightHandTarget.location.Z)
        W.arms.LeftHandTarget.base_location = v(W.arms.LeftHandTarget.location.X + 8,
            W.arms.LeftHandTarget.location.Y, W.arms.LeftHandTarget.location.Z)
        W.arms.RightHandTarget.base_location = v(W.arms.RightHandTarget.location.X + 8,
            W.arms.RightHandTarget.location.Y, W.arms.RightHandTarget.location.Z)
        local before_l = W.arms.LeftHandTarget.location
        local before_r = W.arms.RightHandTarget.location
        W.set_mode("boat"); run(W, 1.5)
        local left = W.arms.LeftHandTarget.location
        local right = W.arms.RightHandTarget.location
        assert(math.abs(left.X - 10) < 0.1 and math.abs(left.Y + 20) < 0.1 and math.abs(left.Z - 100) < 0.1,
            "left target converges to the authored wheel grip socket: " .. left.X .. "," .. left.Y .. "," .. left.Z .. " logs=" .. table.concat(W.logs, " | "))
        assert(math.abs(right.X - 15) < 0.1 and math.abs(right.Y - 20) < 0.1 and math.abs(right.Z - 90) < 0.1,
            "right target converges to the authored throttle grip socket")
        assert(not has(W.logs, "boat hand grip socket FAILED"), "stable finite socket offsets")
        local yaw_forward, yaw_right, yaw_up = v(0, 1, 0), v(-1, 0, 0), v(0, 0, 1)
        W.set_controller_basis("L", yaw_forward, yaw_right, yaw_up)
        W.set_controller_basis("R", yaw_forward, yaw_right, yaw_up)
        run(W, 0.5)
        left, right = W.arms.LeftHandTarget.location, W.arms.RightHandTarget.location
        assert(math.abs(left.X - 10) < 0.1 and math.abs(left.Y + 20) < 0.1 and math.abs(left.Z - 100) < 0.1,
            "left target stays at wheel socket when controller basis rotates")
        assert(math.abs(right.X - 15) < 0.1 and math.abs(right.Y - 20) < 0.1 and math.abs(right.Z - 90) < 0.1,
            "right target stays at throttle socket when controller basis rotates")
        W.set_controller_basis("L", v(1, 0, 0), v(0, 1, 0), v(0, 0, 1))
        W.set_controller_basis("R", v(1, 0, 0), v(0, 1, 0), v(0, 0, 1))
        run(W, 0.5)
        left, right = W.arms.LeftHandTarget.location, W.arms.RightHandTarget.location
        assert(math.abs(left.X - 10) < 0.1 and math.abs(right.X - 15) < 0.1,
            "anchors reconverge after controller basis returns")
        W.set_mode("walking"); run(W, 0.1)
        left, right = W.arms.LeftHandTarget.location, W.arms.RightHandTarget.location
        assert(math.abs(left.X - before_l.X) < 0.1 and math.abs(left.Y - before_l.Y) < 0.1 and math.abs(left.Z - before_l.Z) < 0.1,
            "left controller offset returns to its walking baseline")
        assert(math.abs(right.X - before_r.X) < 0.1 and math.abs(right.Y - before_r.Y) < 0.1 and math.abs(right.Z - before_r.Z) < 0.1,
            "right controller offset returns to its walking baseline")
    end,

    test_boat_socket_anchor_failure_holds_last_pair_and_recovers_without_chatter = function()
        local W = boot()
        W.simulate_location_offsets = true
        W.arms.LeftHandTarget.base_location = v(30, -25, 110)
        W.arms.RightHandTarget.base_location = v(30, 25, 110)
        W.set_mode("boat")
        run(W, 0.5)
        local left_anchor, right_anchor = W.motion_states.L.offset, W.motion_states.R.offset
        assert(left_anchor and right_anchor, "initial valid socket pair is applied")
        local writes_before_common_translation = #W.offsets

        -- Boat motion moves both socket and controller world transforms together. The relative
        -- correction should remain stable in a shared frame.
        W.translate_boat_frame(20000, -15000, 300)
        run(W, 0.25)
        assert(#W.offsets == writes_before_common_translation + 10,
            "a shared world translation keeps both hand offsets active frame to frame")
        assert(math.abs(W.motion_states.L.offset.x - left_anchor.x) < 0.1
            and math.abs(W.motion_states.R.offset.y - right_anchor.y) < 0.1,
            "common boat translation preserves controller-local grip offsets")

        -- The ship can move far from the current UEVR view origin. A large but finite world
        -- correction is valid and must keep the visual hands on the moving helm sockets.
        W.shift_boat_sockets(20000, 0, 0)
        run(W, 0.25)
        assert(math.abs(W.motion_states.L.offset.z) > 15000,
            "large finite camera-to-boat displacement is accepted instead of failing an arm-reach cap")
        local left_on_socket = W.arms.LeftHandTarget.location
        assert(math.abs(left_on_socket.X - 40010) < 0.1 and math.abs(left_on_socket.Y + 15020) < 0.1,
            "left visual target tracks the boat socket across a large world-origin separation")
        local writes_at_far_helm = #W.offsets

        -- A genuinely invalid world coordinate must not reset both hands to walking offsets on
        -- every frame. Keep the last accepted pair until valid socket data returns.
        W.shift_boat_sockets(150000, 0, 0)
        run(W, 0.5)
        assert(#W.offsets == writes_at_far_helm,
            "invalid socket frames do not write offsets or reset to walking baseline")
        assert(math.abs(W.motion_states.L.offset.z) > 15000 and math.abs(W.motion_states.R.offset.z) > 15000,
            "last valid paired offsets are retained during the correction failure")
        local active_count, released_count = 0, 0
        for _, line in ipairs(W.logs) do
            if line:find("boat hand grip anchors active", 1, true) then active_count = active_count + 1 end
            if line:find("boat hand grip anchors released", 1, true) then released_count = released_count + 1 end
        end
        assert(active_count == 1 and released_count == 0,
            "socket failures do not flap anchor activation or release while still at the helm")

        W.shift_boat_sockets(-150000, 0, 0)
        run(W, 0.25)
        assert(has(W.logs, "boat hand grip anchors recovered"), "valid sockets recover the retained anchor pair")
        W.set_mode("walking")
        run(W, 0.1)
        assert(has(W.logs, "boat hand grip anchors released"), "leaving the helm restores normal controller offsets")
    end,

    test_boat_camera_moves_forward_and_restores_walking_view = function()
        local W = boot()
        W.set_mode("boat"); run(W, 1.2)
        assert(tonumber(W.mods.VR_CameraForwardOffset) == -30, "boat view advances past the torso")
        W.set_mode("walking"); run(W, 1.2)
        assert(tonumber(W.mods.VR_CameraForwardOffset) == -12, "walking camera offset is restored")
    end,

    test_turning_items_off_live_returns_them = function()
        local W = boot()
        write(STAGE .. "dreadmoorvr_arms_tuning.lua", "return { items_follow_hands = false }\n")
        run(W, 2)
        assert(W.gun.rel_set == W.gun.rel, "back at the game's own grip offset")
        local n = W.placements
        run(W, 1)
        assert(W.placements == n, "no longer placed")
    end,

    test_arms_and_gestures_together_crank_reels_the_moved_gun = function()
        -- The real pairing: m2 moves the gun onto the VR hand, m3 must still find it there.
        local W = boot({ "m2_arms", "m3_gestures" })
        assert(W.gun.world ~= nil, "gun placed at the VR hand")
        assert(has(W.logs, "tool in hand: hookgun"), "m3 found the gun")
        W.presses = 0
        W.pose = function(i, t)   -- right hand still; left hand circles the crank point at 360 deg/s
            if i ~= 1 then return v(0, 1.2, -0.3) end
            local a = math.rad(360 * t)
            return v(-0.06, 1.2 + 0.10 * math.cos(a), -0.3 + 0.04 + 0.10 * math.sin(a))
        end
        run(W, 2)
        assert(W.presses == 0, "hook home: cranking must not fire, pressed " .. W.presses)
        W.hook_visible = false
        run(W, 2)
        assert(W.presses >= 5, "hook out: crank reels, pressed " .. W.presses)
        local f = failures(W.logs)
        assert(f == "", "FAILED lines: " .. f)
    end,

    test_pawn_replaced_and_arms_died_spawns_fresh_arms = function()
        -- In game 2026-11-17 16:08: the pawn was replaced, the old arms died with it, the reattach
        -- threw before hiding the new head, and the view sat inside the character's face.
        local W = boot()
        local old_arms = W.arms
        W.body.dead = true
        local p2 = W.new_pawn()
        run(W, 5)
        assert(p2.Mesh.hidden.neck_01, "new pawn's head hidden even though the reattach threw")
        assert(W.spawns == 2 and W.arms ~= old_arms, "fresh arms spawned, spawns=" .. W.spawns)
        assert(W.body.parent == p2.Mesh, "fresh arms ride the new pawn")
        assert(old_arms.destroyed, "dead arms cleaned up")
        for _, key in ipairs({ "LeftRotP", "LeftRotY", "LeftRotR", "RightRotP", "RightRotY", "RightRotR",
                              "ArmLength", "ElbowOut", "ElbowDown", "ShoulderFollow" }) do
            assert(W.arms[key] == old_arms[key], "respawn reapplies " .. key)
        end
        assert(#W.offsets == 4 and W.offsets[3].z == 8 and W.offsets[4].z == 8, "fresh controller offsets")
        assert(has(W.logs, "arms lost with the old pawn"), "logged")
        local later = {}
        for i, l in ipairs(W.logs) do if l:find("FAILED") and i > #W.logs - 50 then later[#later + 1] = l end end
        assert(#later == 0, "settled, no ongoing failures: " .. table.concat(later, " | "))
    end,

    test_level_torso_zeroes_the_anim_pitch_only = function()
        local W = boot()
        assert(W.rig_pitch == 0, "rig reads a level pitch, got " .. tostring(W.rig_pitch))
        assert(W.anim.ControlRotaton.y == 90, "yaw untouched")
        assert(has(W.logs, "torso levelling on"), "logged")
        write(STAGE .. "dreadmoorvr_arms_tuning.lua", "return { level_torso = false }")
        run(W, 2)
        assert(W.rig_pitch == 35, "off again live, got " .. tostring(W.rig_pitch))
    end,



    test_same_pawn_new_lua_wrapper_is_not_a_new_pawn = function()
        -- UEVR can hand Lua a fresh wrapper for the same pawn (tostring differs, address doesn't).
        -- In game that looked like a new pawn every so often and triggered reattaches.
        stage(TUNING_ON)
        local W = make_world()
        load_scripts(W, { "m2_arms" })
        local real = W.pawn
        uevr.api.get_local_pawn = function()
            return setmetatable({}, { __index = real })   -- new table each call, same object
        end
        run(W, 15)
        assert(not has(W.logs, "reattached") and not has(W.logs, "arms lost"), "no false pawn change")
        assert(W.spawns == 1, "one spawn, got " .. W.spawns)
    end,

    test_one_broken_component_does_not_stop_the_scan = function()
        stage(TUNING_ON)
        local saved = package.path
        package.path = STAGE .. "scripts/?.lua;" .. saved
        local W = make_world()
        local broken = { get_address = function() return 0x9999 end,
            GetAttachSocketName = function() error("component is gone") end }
        table.insert(W.pawn_mesh.AttachChildren, 1, broken)
        load_scripts(W, { "m2_arms" })
        package.path = saved
        run(W, 15)
        assert(W.gun.world ~= nil, "hook gun still followed past the broken component")
        local f = failures(W.logs)
        assert(not f:find("items FAILED"), "per-item errors stay per-item:\n" .. f)
    end,



    test_game_swaps_tools_old_one_forgotten_new_one_follows = function()
        -- In game 17:01-17:43 old tools piled up in the hand. Now the game removes the old tool
        -- from its own mesh (its unequip can find it) and the new one follows.
        local W = boot()
        assert(W.gun.world ~= nil)
        for i, c in ipairs(W.pawn_mesh.AttachChildren) do if c == W.gun then table.remove(W.pawn_mesh.AttachChildren, i); break end end
        W.gun.parent = nil                                   -- destroyed by the game
        local sickle = W.attachable("BP_Sickle_Equipment.StaticMesh", W.pawn_mesh, "KnifeSocket")
        table.insert(W.pawn_mesh.AttachChildren, sickle)
        run(W, 2)
        assert(has(W.logs, "held item gone"), "old gun forgotten")
        assert(sickle.world and sickle.world.b.b.socket == "KnifeSocket", "sickle follows")
        local f = failures(W.logs)
        assert(f == "", "FAILED lines: " .. f)
    end,

    test_script_reset_restores_items_and_body = function()
        local W = boot()
        W.callbacks.reset()
        assert(W.gun.rel_set == W.gun.rel, "hook gun back at the game's grip on reset")
        assert(next(W.pawn_mesh.hidden) == nil, "game bones unhidden")
        assert(W.arms.destroyed, "arms actor destroyed")
    end,

    test_boat_controls_survive_tuning_reload_and_restore_on_exit = function()
        local W = boot()
        local walking = W.pawn
        W.pawn = { get_class = function() return {
            get_fname = function() return fname("DrdShipBase") end,
            get_super_struct = function() return nil end } end }
        run(W, 0.05)
        assert(W.mods.VR_MovementOrientation == "0", "raw throttle/rudder axes immediately on entry")
        assert(W.mods.VR_AimMethod == "0" and W.mods.VR_RoomscaleMovement == "false", "boat owns movement and aim")
        write(STAGE .. "dreadmoorvr_arms_tuning.lua", TUNING_ON:gsub("aim_method = 2", "aim_method = 3"))
        run(W, 2)
        assert(W.mods.VR_AimMethod == "0" and W.mods.VR_MovementOrientation == "0", "live tuning cannot overwrite boat settings")
        W.pawn = walking
        run(W, 0.05)
        assert(W.mods.VR_AimMethod == "2" and W.mods.VR_MovementOrientation == "1", "restore exact entry settings on exit")
        assert(W.mods.VR_RoomscaleMovement == "true")
        run(W, 2)
        assert(W.mods.VR_AimMethod == "3", "walking picks up tuning edited at helm")
        assert(failures(W.logs) == "", failures(W.logs))
    end,

    test_first_person_boat_shows_vr_arms_and_runs_solver = function()
        local W = boot()
        W.set_mode("fishing"); run(W, 0.1)
        assert(W.hidden == true, "fixture hides arms outside walking mode")
        W.set_mode("boat"); run(W, 0.2)
        assert(W.hidden == false, "VR arms are shown at the first-person helm")
        assert(W.body.parent == W.pawn.Mesh and W.body.hidden_in_game == false,
            "arms mesh stays on the diver pose source but clears hidden state at the helm")
        W.set_mode("walking"); run(W, 0.1)
        assert(W.body.parent == W.pawn.Mesh, "arms retain the character pose source when leaving the helm")
        assert(failures(W.logs) == "", failures(W.logs))
    end,

    test_boat_controls_work_before_arms_spawn_and_reset_restores = function()
        stage(TUNING_ON)
        local W = make_world()
        W.pawn = { get_class = function() return {
            get_fname = function() return fname("DrdShipBase") end,
            get_super_struct = function() return nil end } end }
        load_scripts(W, { "m2_arms" })
        run(W, 2)
        assert(W.spawns == 0)
        assert(W.mods.VR_AimMethod == "0" and W.mods.VR_RoomscaleMovement == "false")
        W.callbacks.reset()
        assert(W.mods.VR_AimMethod == "1" and W.mods.VR_RoomscaleMovement == "true", "reset restores original values")
        assert(failures(W.logs) == "", failures(W.logs))
    end,
}
