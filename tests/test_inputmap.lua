local inputmap = require("inputmap")

return {
    test_observe_logs_only_on_change = function()
        local m = inputmap.new()
        local l1 = m:observe({ "AButtonRight@R" }, 0x1000, true, true)
        assert(l1 == "act=AButtonRight@R pad=0x1000 hmd=1 ctl=1", tostring(l1))
        assert(m:observe({ "AButtonRight@R" }, 0x1000, true, true) == nil, "unchanged state logs nothing")
        assert(m:observe({}, 0, true, true) == "act=- pad=0x0000 hmd=1 ctl=1")
    end,

    test_single_action_records_mapping = function()
        local m = inputmap.new()
        m:observe({ "BButtonRight@R" }, 0x4000, true, true)
        m:observe({}, 0, true, true)
        m:observe({ "BButtonRight@R" }, 0x4000, true, true)
        m:observe({ "AButtonLeft@L", "DPad_Up@L" }, 0x2001, true, true) -- two at once: not recorded
        assert(m:summary() == "BButtonRight@R->0x4000 x2", m:summary())
    end,

    test_gated_input_is_recorded_as_gated = function()
        -- Passthrough case: action down, UEVR gate closed, pad stays 0.
        local m = inputmap.new()
        local line = m:observe({ "AButtonRight@R" }, 0, false, false)
        assert(line == "act=AButtonRight@R pad=0x0000 hmd=0 ctl=0", line)
        assert(m:summary() == "AButtonRight@R->gated x1", m:summary())
    end,

    test_actions_sorted_in_line = function()
        local m = inputmap.new()
        local line = m:observe({ "Grip@R", "Grip@L" }, 0x0300, true, true)
        assert(line == "act=Grip@L,Grip@R pad=0x0300 hmd=1 ctl=1", line)
    end,
}
