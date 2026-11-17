-- Smoke test: the real m3_gestures.lua and its lib modules against a fake UEVR (no require, like
-- the real one) and a fake game. Real names: tools sit at HookSimple / KnifeSocket, and the hook
-- gun's Hook mesh is hidden while the hook is out (docs/research/2026-11-17-remaining-hooks.md).
local STAGE = "build/smoke3/"
local LIBS = { "gameapi", "modes", "gestures" }
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
    local chain = { "BP_PlayerCharacter_C", "DrdPlayerCharacter", "Character", "Pawn" }
    local function class_at(i)
        if i > #chain then return nil end
        return { get_fname = function() return fname(chain[i]) end, get_super_struct = function() return class_at(i + 1) end }
    end
    W.pawn = { Mesh = mesh, get_class = function() return class_at(1) end }
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
        api = { get_local_pawn = function() return W.pawn end },
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
        assert(after <= 1, "stops when the hook is home (one queued tap may finish), got " .. after)
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

    test_real_trigger_passes_through_when_idle = function()
        local W = world("KnifeSocket", false)
        run(W, 0.6)
        W.callbacks.tick(nil, DT)
        local state = { Gamepad = { bRightTrigger = 200 } }
        W.callbacks.xinput(nil, 0, state)
        assert(state.Gamepad.bRightTrigger == 200, "player's own trigger untouched")
    end,
}
