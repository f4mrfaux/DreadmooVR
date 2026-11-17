-- Smoke test: runs the real m2_arms.lua and its lib modules against a fake UEVR and a fake game
-- for ~15 s of frames. Checks the whole bridge wires up without errors, pushes the tuning into
-- UEVR, moves a hand-held item onto the VR arms and gives it back. Staged under build/smoke.
local STAGE = "build/smoke/"
local LIBS = { "gameapi", "modes", "armsloader", "m1flow", "armsflow", "armstats", "tuning", "wristfit", "ubik", "itemfollow", "gestures" }

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
    local W = { logs = {}, mods = {}, offsets = {}, callbacks = {} }
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
        return obj({ K2_GetComponentLocation = function() return loc end,
            K2_GetComponentRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
            GetForwardVector = function() return v(1, 0, 0) end, GetRightVector = function() return v(0, 1, 0) end,
            GetUpVector = function() return v(0, 0, 1) end })
    end

    local pawn_mesh = mesh("GameMesh")
    local anim_fn = { hook_ptr = function(_, pre, post) W.anim_post = post end }
    W.anim = { ControlRotaton = { x = 0, y = 90, z = 0 },
        get_class = function() return { get_fname = function() return fname("ABP_V03_C") end,
            find_function = function(_, n) return n == "BlueprintUpdateAnimation" and anim_fn or nil end } end }
    pawn_mesh.GetAnimInstance = function() return W.anim end
    W.camera = attachable("Camera", pawn_mesh, "head")
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
    W.pawn = obj({ name = "Pawn", Mesh = pawn_mesh, get_class = function() return class_at(1) end,
        GetTransform = function() return {} end, K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end })
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
        local body = mesh("Body" .. W.spawns)
        body.K2_AttachToComponent = function(self, p)
            if self.dead then error("arms actor is gone") end
            local old = self.parent and self.parent.AttachChildren
            if old then for i = #old, 1, -1 do if old[i] == self then table.remove(old, i) end end end
            p.AttachChildren = p.AttachChildren or {}; table.insert(p.AttachChildren, self)
            self.parent = p; return true
        end
        W.body = body
        W.arms = obj({ name = "BP_VRArms", Body = body,
            LeftHandTarget = target(v(30, -25, 110)), RightHandTarget = target(v(30, 25, 110)),
            SetActorHiddenInGame = function() end, K2_DestroyActor = function(self) self.destroyed = true end })
        return W.arms
    end

    local gs = { BeginDeferredActorSpawnFromClass = function() return new_arms() end,
        FinishSpawningActor = function(_, a) return a end }
    local arms_class = { get_class_default_object = function() return {} end }
    local function state(hand)
        local s = { hand = hand }
        s.set_hand = function(self, h) self.hand = h end
        s.set_permanent = function() end
        s.set_location_offset = function(self, off) W.offsets[#W.offsets + 1] = off end
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
return { grip_back = 8, shoulder_widen = 5, camera_forward = -30, camera_up = 0,
         aim_method = 2, movement_orientation = 1, items_follow_hands = true, level_torso = true }
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

local function boot(scripts)
    stage(TUNING_ON)
    local W = make_world()
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
        assert(tonumber(W.mods.VR_CameraForwardOffset) == -30 and tonumber(W.mods.VR_CameraUpOffset) == 0)
        assert(#W.offsets == 2 and W.offsets[1].z == 8, "grip_back on both controllers")
    end,

    test_held_item_moves_to_vr_hand_and_camera_stays = function()
        local W = boot()
        assert(W.gun.parent == W.body and W.gun.socket == "HookSimple", "hook gun rides the VR hand")
        assert(W.camera.parent == W.pawn_mesh, "camera stays on the game head")
        assert(has(W.logs, "held item %-> VR hand R"), "logged")
    end,

    test_turning_items_off_live_returns_them = function()
        local W = boot()
        write(STAGE .. "dreadmoorvr_arms_tuning.lua", "return { items_follow_hands = false }\n")
        run(W, 2)
        assert(W.gun.parent == W.pawn_mesh and W.gun.socket == "HookSimple", "hook gun back on the game mesh")
    end,

    test_arms_and_gestures_together_crank_reels_the_moved_gun = function()
        -- The real pairing: m2 moves the gun onto the VR hand, m3 must still find it there.
        local W = boot({ "m2_arms", "m3_gestures" })
        assert(W.gun.parent == W.body, "gun on the VR hand")
        assert(has(W.logs, "tool in hand: hookgun"), "m3 found the moved gun")
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
        assert(W.gun.parent == W.body, "hook gun still moved past the broken component")
        local f = failures(W.logs)
        assert(not f:find("items FAILED"), "per-item errors stay per-item:\n" .. f)
    end,

    test_gives_up_on_an_item_the_game_keeps_taking_back = function()
        stage(TUNING_ON)
        local saved = package.path
        package.path = STAGE .. "scripts/?.lua;" .. saved
        local W = make_world()
        load_scripts(W, { "m2_arms" })
        package.path = saved
        local tick = W.callbacks.tick
        W.callbacks.tick = function(...)   -- the game snaps the hook gun back to its own hand every frame
            W.gun:K2_AttachToComponent(W.pawn_mesh, "HookSimple")
            return tick(...)
        end
        run(W, 15)
        local moves = 0
        for _, l in ipairs(W.logs) do if l:find("held item %-> VR hand") then moves = moves + 1 end end
        assert(moves <= 5, "stops fighting the game, moved " .. moves .. " times")
        assert(has(W.logs, "keeps re%-attaching"), "says why it stopped")
    end,

    test_normal_re_equips_keep_following = function()
        stage(TUNING_ON)
        local saved = package.path
        package.path = STAGE .. "scripts/?.lua;" .. saved
        local W = make_world()
        load_scripts(W, { "m2_arms" })
        package.path = saved
        local tick, t = W.callbacks.tick, 0
        W.callbacks.tick = function(e, d)   -- re-equip the hook gun every 5 s, like a player swapping tools
            t = t + d
            if t >= 5 then t = 0; W.gun:K2_AttachToComponent(W.pawn_mesh, "HookSimple") end
            return tick(e, d)
        end
        run(W, 40)
        assert(W.gun.parent == W.body, "still following after many re-equips")
        assert(not has(W.logs, "keeps re%-attaching"), "re-equips are not a fight")
    end,

    test_script_reset_restores_items_and_body = function()
        local W = boot()
        W.callbacks.reset()
        assert(W.gun.parent == W.pawn_mesh, "hook gun returned on reset")
        assert(next(W.pawn_mesh.hidden) == nil, "game bones unhidden")
        assert(W.arms.destroyed, "arms actor destroyed")
    end,
}
