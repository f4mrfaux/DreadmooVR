local itemfollow = require("itemfollow")

-- The game's bone chain (SK_DreadMoreSkeleton). Sockets resolve to their bone through
-- GetSocketBoneName first, so only bones appear here.
local PARENT = {
    pelvis = "root", spine_01 = "pelvis", neck_01 = "spine_01", head = "neck_01",
    clavicle_r = "spine_01", upperarm_r = "clavicle_r", lowerarm_r = "upperarm_r", hand_r = "lowerarm_r",
    index_01_r = "hand_r",
    clavicle_l = "spine_01", upperarm_l = "clavicle_l", lowerarm_l = "upperarm_l", hand_l = "lowerarm_l",
}
local function parent_of(b) return PARENT[b] or "None" end

return {
    test_hand_side_walks_up_to_the_hand = function()
        assert(itemfollow.hand_side("hand_r", parent_of) == "R")
        assert(itemfollow.hand_side("index_01_r", parent_of) == "R")
        assert(itemfollow.hand_side("hand_l", parent_of) == "L")
        assert(itemfollow.hand_side("head", parent_of) == nil, "camera and flashlight stay put")
        assert(itemfollow.hand_side("lowerarm_r", parent_of) == nil, "above the hand is not held")
        assert(itemfollow.hand_side("None", parent_of) == nil)
    end,

    test_hand_side_ignores_case_like_unreal_names = function()
        -- In game the bone came back as "Hand_R" (log 16:50:13); FNames compare case-insensitively.
        assert(itemfollow.hand_side("Hand_R", parent_of) == "R")
        assert(itemfollow.hand_side("HAND_L", parent_of) == "L")
        local upper = function(b) local p = PARENT[b:lower()]; return p and p:upper() or "None" end
        assert(itemfollow.hand_side("INDEX_01_R", upper) == "R", "walks a differently-cased chain")
    end,

    test_hand_side_survives_a_cycle = function()
        local loop = function(b) return b == "a" and "b" or "a" end
        assert(itemfollow.hand_side("a", loop) == nil)
    end,

    test_plan_moves_only_hand_attachments = function()
        -- Real attachments (docs/research/2026-11-17-held-items.md): Camera and SpotLight on the
        -- head bone, tools on hand_r sockets, the forceps socket on hand_l.
        local children = {
            { id = "camera", socket = "head", bone = "head" },
            { id = "hookgun", socket = "HookSimple", bone = "hand_r" },
            { id = "sickle", socket = "KnifeSocket", bone = "hand_r" },
            { id = "forceps", socket = "Forceps_LHand", bone = "hand_l" },
            { id = "clothing", socket = "None", bone = "None" },
        }
        local moves = itemfollow.plan(children, parent_of)
        assert(#moves == 3, "three held items, got " .. #moves)
        assert(moves[1].id == "hookgun" and moves[1].side == "R" and moves[1].socket == "HookSimple")
        assert(moves[2].id == "sickle" and moves[2].side == "R")
        assert(moves[3].id == "forceps" and moves[3].side == "L")
    end,
}
