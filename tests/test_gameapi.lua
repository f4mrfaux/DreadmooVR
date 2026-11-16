local gameapi = require("gameapi")

-- Fake UEVR objects: a class with a name and a super accessor.
local function fake_class(names, accessor)
    local nodes = {}
    for i = #names, 1, -1 do
        local nxt = nodes[i + 1]
        local node = { name = names[i] }
        node.get_fname = function(self) return { to_string = function() return self.name end } end
        node[accessor] = function() return nxt end
        nodes[i] = node
    end
    return { get_class = function() return nodes[1] end }
end

local CHAIN = { "BP_FishingController_C", "DrdFishingControllerBase", "Pawn", "Actor", "Object" }

return {
    test_class_chain_walks_supers = function()
        local got = gameapi.class_chain(fake_class(CHAIN, "get_super"))
        assert(table.concat(got, ",") == table.concat(CHAIN, ","), table.concat(got, ","))
    end,

    test_class_chain_super_struct_spelling = function()
        local got = gameapi.class_chain(fake_class(CHAIN, "get_super_struct"))
        assert(#got == 5 and got[2] == "DrdFishingControllerBase")
    end,

    test_class_chain_nil_object = function()
        assert(#gameapi.class_chain(nil) == 0)
    end,
}
