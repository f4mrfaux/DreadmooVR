-- Held items (pure): which components attached to the game mesh belong to a hand, so the bridge
-- can re-attach them to the VR arms' Body at the same socket. A component counts when its socket's
-- bone is hand_l / hand_r or anything below it; head-attached things (camera, flashlight) and arm
-- bones above the hand do not. Verified against the game (docs/research/2026-11-17-held-items.md):
-- tools attach to CharacterMesh0 (tag PlayerMesh) at HookSimple / Harpoon_Socket / KnifeSocket,
-- all on hand_r in SK_DreadMoreSkeleton.
local itemfollow = {}

local HANDS = { hand_l = "L", hand_r = "R" }
local MAX_DEPTH = 64   -- skeletons are far shallower; guards against a malformed parent chain

-- parent_of(bone) -> parent bone name, or "None" at the root (USkinnedMeshComponent::GetParentBone).
function itemfollow.hand_side(bone, parent_of)
    local b = bone
    for _ = 1, MAX_DEPTH do
        if b == nil or b == "None" or b == "" then return nil end
        if HANDS[b] then return HANDS[b] end
        b = parent_of(b)
    end
    return nil
end

-- children: list of { id, socket, bone }. Returns the hand-held ones, in order, with their side.
function itemfollow.plan(children, parent_of)
    local moves = {}
    for _, c in ipairs(children) do
        local side = itemfollow.hand_side(c.bone, parent_of)
        if side then moves[#moves + 1] = { id = c.id, socket = c.socket, side = side } end
    end
    return moves
end

return itemfollow
