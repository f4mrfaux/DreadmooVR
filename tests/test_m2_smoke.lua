-- Smoke test: runs the real m2_arms.lua and its lib modules against a fake UEVR and a fake game
-- for ~15 s of frames. Checks the whole bridge wires up without errors, pushes the tuning into
-- UEVR, moves a hand-held item onto the VR arms and gives it back. Staged under build/smoke.
local STAGE = "build/smoke/"
local LIBS = { "gameapi", "modes", "armsloader", "m1flow", "armsflow", "armstats", "tuning", "wristfit", "ubik", "itemfollow" }

local function copy(src, dst)
    local i = assert(io.open(src, "rb")); local s = i:read("a"); i:close()
    local o = assert(io.open(dst, "wb")); o:write(s); o:close()
end
local function write(path, s) local o = assert(io.open(path, "wb")); o:write(s); o:close() end

local function stage(tuning_text)
    os.execute('mkdir "build\\smoke\\scripts\\lib" 2>nul')
    copy("src/scripts/m2_arms.lua", STAGE .. "scripts/m2_arms.lua")
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
    local SOCKETS = { HookSimple = "hand_r", KnifeSocket = "hand_r", Harpoon_Socket = "hand_r", Camera = "head" }
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
        c.K2_AttachToComponent = function(self, p, s) self.parent = p; self.socket = s; return true end
        return c
    end
    local function target(loc)
        return obj({ K2_GetComponentLocation = function() return loc end,
            K2_GetComponentRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
            GetForwardVector = function() return v(1, 0, 0) end, GetRightVector = function() return v(0, 1, 0) end,
            GetUpVector = function() return v(0, 0, 1) end })
    end

    local pawn_mesh = mesh("GameMesh")
    W.camera = attachable("Camera", pawn_mesh, "head")
    W.gun = attachable("BP_HookGunEquipment.DefaultSceneRoot", pawn_mesh, "HookSimple")
    pawn_mesh.AttachChildren = { W.camera, W.gun }
    W.pawn_mesh = pawn_mesh

    local chain = { "BP_PlayerCharacter_C", "DrdPlayerCharacter", "Character", "Pawn", "Actor", "Object" }
    local function class_at(i)
        if i > #chain then return nil end
        return { get_fname = function() return fname(chain[i]) end, get_super_struct = function() return class_at(i + 1) end }
    end
    W.pawn = obj({ name = "Pawn", Mesh = pawn_mesh, get_class = function() return class_at(1) end,
        GetTransform = function() return {} end, K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end })

    W.body = mesh("Body")
    W.body.K2_AttachToComponent = function(self, p) self.parent = p; return true end
    W.arms = obj({ name = "BP_VRArms", Body = W.body,
        LeftHandTarget = target(v(30, -25, 110)), RightHandTarget = target(v(30, 25, 110)),
        SetActorHiddenInGame = function() end, K2_DestroyActor = function(self) self.destroyed = true end })
    pawn_mesh.AttachChildren[#pawn_mesh.AttachChildren + 1] = W.body   -- Body rides the game mesh too

    local gs = { BeginDeferredActorSpawnFromClass = function() return W.arms end,
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
    local function reg(name) return function(fn) W.callbacks[name] = fn end end
    _G.uevr = {
        params = {
            functions = { log_info = function(s) W.logs[#W.logs + 1] = s end },
            vr = {
                set_mod_value = function(k, val) W.mods[k] = val end,
                get_hmd_index = function() return 0 end,
                get_left_controller_index = function() return 1 end,
                get_right_controller_index = function() return 2 end,
                get_pose = function(i, p) p.x, p.y, p.z = (i == 1 and -0.2 or i == 2 and 0.2 or 0), (i == 0 and 1.6 or 1.2), -0.3 end,
            },
        },
        sdk = { callbacks = {
            on_lua_event = reg("lua_event"), on_pre_engine_tick = reg("tick"), on_script_reset = reg("reset"),
            on_post_calculate_stereo_view_offset = reg("view"),
        } },
        api = {
            get_local_pawn = function() return W.pawn end,
            get_engine = function() return { GameViewport = { World = {} } } end,
            find_uobject = function(_, name)
                if name:find("BP_VRArms") then return arms_class end
                return { get_class_default_object = function() return gs end }
            end,
            dispatch_custom_event = function(_, name, data)
                if name == "dreadmoorvr_request_class" then W.pending_reply = "ok|" .. data end
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
        W.callbacks.tick(nil, 0.05)
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
         aim_method = 2, movement_orientation = 1, items_follow_hands = true }
]]

local function boot()
    stage(TUNING_ON)
    local saved = package.path
    package.path = STAGE .. "scripts/?.lua;" .. saved
    local W = make_world()
    local chunk = assert(loadfile(STAGE .. "scripts/m2_arms.lua"))
    chunk()
    package.path = saved
    run(W, 15)
    return W
end

return {
    test_bridge_runs_without_failures = function()
        local W = boot()
        local f = failures(W.logs)
        assert(f == "", "FAILED lines:\n" .. f)
        assert(has(W.logs, "spawned BP_VRArms"), "arms spawned")
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

    test_one_broken_component_does_not_stop_the_scan = function()
        stage(TUNING_ON)
        local saved = package.path
        package.path = STAGE .. "scripts/?.lua;" .. saved
        local W = make_world()
        local broken = { get_address = function() return 0x9999 end,
            GetAttachSocketName = function() error("component is gone") end }
        table.insert(W.pawn_mesh.AttachChildren, 1, broken)
        assert(loadfile(STAGE .. "scripts/m2_arms.lua"))()
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
        assert(loadfile(STAGE .. "scripts/m2_arms.lua"))()
        package.path = saved
        local tick = W.callbacks.tick
        W.callbacks.tick = function(...)   -- the game snaps the hook gun back to its own hand every frame
            W.gun.parent, W.gun.socket = W.pawn_mesh, "HookSimple"
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
        assert(loadfile(STAGE .. "scripts/m2_arms.lua"))()
        package.path = saved
        local tick, t = W.callbacks.tick, 0
        W.callbacks.tick = function(e, d)   -- re-equip the hook gun every 5 s, like a player swapping tools
            t = t + d
            if t >= 5 then t = 0; W.gun.parent, W.gun.socket = W.pawn_mesh, "HookSimple" end
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
