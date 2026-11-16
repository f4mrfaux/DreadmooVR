local modes = require("modes")

return {
    test_modes_matches_base_class = function()
        assert(modes.classify({ "BP_FishingController_Tutorial_C", "BP_FishingController_C",
            "DrdFishingControllerBase", "Pawn" }) == "fishing")
    end,

    test_modes_each_mode = function()
        assert(modes.classify({ "BP_PlayerCharacter_C", "DrdPlayerCharacter", "Character" }) == "walking")
        assert(modes.classify({ "BP_CraftController_C", "Pawn" }) == "crafting")
        assert(modes.classify({ "BP_SmallBoat_V2_C", "DrdShipBase", "Pawn" }) == "boat")
        assert(modes.classify({ "BP_DiverCharacter_C", "Character" }) == "diving")
    end,

    test_modes_unknown_class = function()
        assert(modes.classify({ "BP_MenuPawn_C", "Pawn", "Actor" }) == "unknown")
        assert(modes.classify({}) == "unknown")
    end,

    test_modes_switch_runs_exit_once = function()
        local calls = {}
        local function h(name)
            return {
                enter = function() calls[#calls + 1] = "enter:" .. name end,
                exit = function() calls[#calls + 1] = "exit:" .. name end,
            }
        end
        local t = modes.new({ walking = h("walking"), fishing = h("fishing") })
        for _, m in ipairs({ "walking", "walking", "fishing", "fishing", "walking" }) do t:update(m) end
        local got = table.concat(calls, ",")
        assert(got == "enter:walking,exit:walking,enter:fishing,exit:fishing,enter:walking", got)
        assert(t.current == "walking")
    end,

    test_modes_missing_handler_is_fine = function()
        local t = modes.new({})
        t:update("boat")
        t:update("unknown")
        assert(t.current == "unknown")
    end,
}
