local config = require("config")

local tmp = os.getenv("TEMP") .. "\\dreadmoorvr_test_config.lua"

local function write(text)
    local f = assert(io.open(tmp, "w"))
    f:write(text)
    f:close()
end

local GOOD = "return { readout = { enabled = true } }"

return {
    test_config_load_good = function()
        write(GOOD)
        local t, err = config.load(tmp)
        assert(err == nil, tostring(err))
        assert(t.readout.enabled == true)
        assert(config.get().readout.enabled == true)
        assert(config.last_error == nil)
    end,

    test_config_bad_reload_keeps_last_good = function()
        write(GOOD)
        config.load(tmp)
        write("return {")
        config.reload()
        assert(config.get().readout.enabled == true)
        assert(config.last_error ~= nil)
        write("return { readout = { enabled = false } }")
        config.reload()
        assert(config.get().readout.enabled == false)
        assert(config.last_error == nil, "error clears after a good reload")
    end,

    test_config_missing_key_rejected = function()
        write(GOOD)
        config.load(tmp)
        write("return {}")
        config.reload()
        assert(config.get().readout.enabled == true)
        assert(config.last_error and config.last_error:find("readout"), tostring(config.last_error))
    end,

    test_config_cannot_touch_globals = function()
        write("os.exit(1) return { readout = { enabled = true } }")
        local _, err = config.load(tmp)
        assert(err ~= nil, "a config file has no access to os")
    end,

    test_config_reload_if_changed_only_on_change = function()
        write(GOOD)
        config.load(tmp)
        assert(config.reload_if_changed(0) == false, "unchanged file is not reloaded")
        write("return { readout = { enabled = false } }")
        assert(config.reload_if_changed(0) == true)
        assert(config.get().readout.enabled == false)
    end,
}
