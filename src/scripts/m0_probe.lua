-- M0 probe: logs what the game does so Plan 2 can be written from facts.
-- Read-only: it never writes a game property and never calls a game function with side effects.
-- Output: <persistent dir>/dreadmoorvr_m0.log, and UEVR's own log via log_info.

local api = uevr.api
local fn = uevr.params.functions

local log_file = nil
local t0 = os.clock()

local function open_log()
    local ok, dir = pcall(fn.get_persistent_dir)
    if not ok or not dir then return end
    local ok2, f = pcall(io.open, dir .. "\\dreadmoorvr_m0.log", "a")
    if ok2 and f then
        log_file = f
        log_file:write("\n===== session " .. os.date("%Y-%m-%d %H:%M:%S") .. " =====\n")
    end
end

local function log(key, value)
    local line = string.format("t=%.2f %s=%s", os.clock() - t0, key, tostring(value))
    pcall(fn.log_info, "[DreadmoorVR M0] " .. line)
    if log_file then
        log_file:write(line, "\n")
        log_file:flush()
    end
end

-- Walks the class chain, most-derived first. The super accessor name is unconfirmed in the
-- docs, so both known spellings are tried.
local function class_chain(obj)
    local out = {}
    local ok, c = pcall(function() return obj:get_class() end)
    if not ok then return out end
    local guard = 0
    while c ~= nil and guard < 32 do
        local okn, name = pcall(function() return c:get_fname():to_string() end)
        if not okn then okn, name = pcall(function() return c:get_short_name() end) end
        out[#out + 1] = okn and name or "?"
        local nxt = nil
        for _, m in ipairs({ "get_super_struct", "get_super" }) do
            local okm, s = pcall(function() return c[m](c) end)
            if okm then nxt = s; break end
        end
        c = nxt
        guard = guard + 1
    end
    return out
end

local function chain_has(chain, name)
    for _, n in ipairs(chain) do
        if n == name then return true end
    end
    return false
end

local function prop(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if not ok then return "<err>" end
    if v == nil then return "nil" end
    local okn, s = pcall(function() return v:to_string() end)  -- FName / gameplay tag wrappers
    if okn and s then return s end
    local okf, full = pcall(function() return v:get_full_name() end)  -- UObject
    if okf and full then return full end
    return tostring(v)
end

-- "Log when changed" memory.
local last = {}
local function log_changed(key, value)
    if last[key] ~= value then
        last[key] = value
        log(key, value)
    end
end

local last_pawn_addr = nil

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    local ok, pawn = pcall(function() return api:get_local_pawn(0) end)
    if not ok or pawn == nil then
        log_changed("pawn", "nil")
        return
    end

    local addr = pawn:get_address()
    if addr ~= last_pawn_addr then
        last_pawn_addr = addr
        log("pawn_chain", table.concat(class_chain(pawn), " > "))
        last = { pawn = last.pawn }  -- reset per-pawn change memory
    end
    local chain = class_chain(pawn)

    if chain_has(chain, "DrdFishingControllerBase") then
        log_changed("fish.State", prop(pawn, "State"))
        log_changed("fish.CurrentQTE", prop(pawn, "CurrentQTE"))
        log_changed("fish.StrugglingFish", prop(pawn, "StrugglingFish"))
        log_changed("fish.StruggleX", prop(pawn, "StruggleX"))
        log_changed("fish.bMousePressed", prop(pawn, "bMousePressed"))
    end
end)

-- Hook gun values: GA_HookGun is an ability instance, not on the pawn, so look it up by class
-- about twice a second while walking.
local hook_cls = nil
local hook_timer = 0
uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
    hook_timer = hook_timer + delta
    if hook_timer < 0.5 then return end
    hook_timer = 0
    if hook_cls == nil then
        hook_cls = api:find_uobject("BlueprintGeneratedClass /Game/Dreadmoor/Core/Features/Hook/GAS/GA_HookGun.GA_HookGun_C")
        if hook_cls == nil then return end
        log("hookgun.class", "found")
    end
    local ok, inst = pcall(function() return hook_cls:get_first_object_matching(false) end)
    if not ok or inst == nil then return end
    log_changed("hook.DragForceMul", prop(inst, "DragForceMul"))
    log_changed("hook.DragForcePercentPerClick", prop(inst, "DragForcePercentPerClick"))
    log_changed("hook.DragForceMulMax", prop(inst, "DragForceMulMax"))
end)

-- Every gamepad change, so prompt buttons can be matched by time stamp.
local last_pad = ""
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    local g = state.Gamepad
    local s = string.format("btn=0x%04X lt=%d rt=%d lx=%d ly=%d rx=%d ry=%d",
        g.wButtons, g.bLeftTrigger, g.bRightTrigger,
        g.sThumbLX // 8192, g.sThumbLY // 8192, g.sThumbRX // 8192, g.sThumbRY // 8192)
    if s ~= last_pad then
        last_pad = s
        log("pad", s)
    end
end)

uevr.sdk.callbacks.on_script_reset(function()
    if log_file then log_file:close() end
end)

open_log()
log("probe", "loaded")
