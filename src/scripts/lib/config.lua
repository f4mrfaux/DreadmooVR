-- Tunables loaded from a Lua file that returns a table. Reloadable while the game runs; a bad
-- edit keeps the last good table and reports the error instead of breaking the mod.
local config = { last_error = nil }

local REQUIRED = {
    { "readout", "table" },
    { "readout.enabled", "boolean" },
}

local path, current, last_text, since_check = nil, nil, nil, 0

local function read(p)
    local f, err = io.open(p, "r")
    if not f then return nil, err end
    local text = f:read("a")
    f:close()
    return text
end

local function lookup(t, dotted)
    for key in dotted:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[key]
    end
    return t
end

local function parse(text)
    -- Empty environment: a config file can build tables, nothing else.
    local chunk, err = load(text, "=dreadmoorvr_config", "t", {})
    if not chunk then return nil, err end
    local ok, t = pcall(chunk)
    if not ok then return nil, t end
    if type(t) ~= "table" then return nil, "config must return a table" end
    for _, req in ipairs(REQUIRED) do
        if type(lookup(t, req[1])) ~= req[2] then
            return nil, "config key '" .. req[1] .. "' must be a " .. req[2]
        end
    end
    return t
end

local function apply(text)
    last_text = text
    local t, err = parse(text)
    if t then
        current, config.last_error = t, nil
    else
        config.last_error = err
    end
    return t, err
end

function config.load(p)
    path = p
    local text, err = read(p)
    if not text then
        config.last_error = err
        return nil, err
    end
    return apply(text)
end

function config.reload()
    return config.load(path)
end

-- Call every frame with the frame time; checks the file about once a second.
-- Returns true when the file changed and was re-read.
function config.reload_if_changed(delta)
    since_check = since_check + (delta or 0)
    if delta ~= 0 and since_check < 1 then return false end
    since_check = 0
    local text = path and read(path)
    if not text or text == last_text then return false end
    apply(text)
    return true
end

function config.get()
    return current
end

return config
