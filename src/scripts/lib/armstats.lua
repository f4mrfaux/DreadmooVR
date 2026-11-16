-- Arms refinement stats (pure). One sample = controller target vs the arms' actual bones.
-- reach_err: cm between target and hand bone (IK accuracy). over_reach: target beyond the arm's
-- length from the shoulder. d_*: hand bone rotation minus controller rotation, wrapped to +-180;
-- the means are the hand rotation offset to dial in.
local armstats = {}
armstats.__index = armstats

local function dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function armstats.wrap(a)
    while a > 180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end

-- s: {target, target_rot, hand, hand_rot, shoulder, elbow} as {X,Y,Z} / {Pitch,Yaw,Roll}.
function armstats.sample(s)
    local arm_len = dist(s.shoulder, s.elbow) + dist(s.elbow, s.hand)
    local to_target = dist(s.shoulder, s.target)
    return {
        reach_err = dist(s.target, s.hand),
        shoulder_to_target = to_target,
        arm_len = arm_len,
        over_reach = to_target > arm_len,
        d_pitch = armstats.wrap(s.hand_rot.Pitch - s.target_rot.Pitch),
        d_yaw = armstats.wrap(s.hand_rot.Yaw - s.target_rot.Yaw),
        d_roll = armstats.wrap(s.hand_rot.Roll - s.target_rot.Roll),
    }
end

function armstats.new()
    return setmetatable({ hands = {} }, armstats)
end

function armstats:add(hand, s)
    local h = self.hands[hand]
    if not h then h = { n = 0, err_sum = 0, err_max = 0, over = 0, p = 0, y = 0, r = 0 }; self.hands[hand] = h end
    h.n = h.n + 1
    h.err_sum = h.err_sum + s.reach_err
    if s.reach_err > h.err_max then h.err_max = s.reach_err end
    if s.over_reach then h.over = h.over + 1 end
    h.p, h.y, h.r = h.p + s.d_pitch, h.y + s.d_yaw, h.r + s.d_roll
end

function armstats:summary(hand)
    local h = self.hands[hand]
    if not h or h.n == 0 then return hand .. " n=0" end
    return string.format("%s n=%d reach_err mean=%.1f max=%.1f out_of_reach=%d%% rot_offset(p,y,r)=(%.1f,%.1f,%.1f)",
        hand, h.n, h.err_sum / h.n, h.err_max, math.floor(100 * h.over / h.n + 0.5), h.p / h.n, h.y / h.n, h.r / h.n)
end

return armstats
