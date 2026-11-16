-- Upper-body arm solver (pure), ported from UBIKSolver (MIT, (c) 2023 Jonas Molgaard,
-- https://github.com/kjduling/UBIKSolver), itself after Mathias Parger's master thesis and
-- VRArmIK. Line refs are to AnimNode_UBIKSolver.cpp. Outputs are world positions that feed
-- ABP_VRArms' Two-Bone IK (elbow joint target) and clavicle offset, so bone axes never matter.
local ubik = {}

-- UBIK.h defaults.
ubik.SETTINGS = {
    elbow_y_weight = 130, elbow_y_distance_start = 0.2,          -- RotateElbowByHandPosition
    shoulder_mult = 60, shoulder_limit = 45,                     -- RotateUpperArm
}

local function sub(a, b) return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z } end
local function add(a, b) return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z } end
local function scale(a, s) return { X = a.X * s, Y = a.Y * s, Z = a.Z * s } end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function len(a) return math.sqrt(dot(a, a)) end
local function norm(a) local l = len(a); return l > 1e-9 and scale(a, 1 / l) or { X = 0, Y = 0, Z = 0 } end
local function reject(a, n) return sub(a, scale(n, dot(a, n))) end   -- a minus its component along unit n
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- UUBIK::CosineRule: angle (deg) between the two adjacent sides.
function ubik.cosine_rule(a1, a2, opposite)
    local c = (a1 * a1 + a2 * a2 - opposite * opposite) / (2 * a1 * a2)
    return math.deg(math.acos(clamp(c, -1, 1)))
end

-- Elbow on the circle about shoulder->hand (SetElbowBasePosition + RotateElbow).
-- p: {shoulder, hand, upper, lower, swivel (deg, 0 = straight down, + = toward outward), outward}
function ubik.elbow(p)
    local axis = sub(p.hand, p.shoulder)
    local d = clamp(len(axis), 1e-3, p.upper + p.lower - 1e-6)
    local u = norm(axis)
    local alpha = math.rad(ubik.cosine_rule(p.upper, d, p.lower))   -- angle at the shoulder
    local center = add(p.shoulder, scale(u, p.upper * math.cos(alpha)))
    local radius = p.upper * math.sin(alpha)
    local down = norm(reject({ X = 0, Y = 0, Z = -1 }, u))
    if len(down) < 1e-6 then down = norm(reject(p.outward, u)) end
    local out = norm(reject(reject(p.outward, u), down))
    local t = math.rad(p.swivel)
    return add(center, add(scale(down, radius * math.cos(t)), scale(out, radius * math.sin(t))))
end

-- RotateElbowByHandPosition (L608-618) minus its 90 deg base offset: outward = hand's sideways
-- distance from the shoulder, positive away from the body (cm); arm_len normalises.
function ubik.base_swivel(outward, arm_len)
    local s = ubik.SETTINGS
    return s.elbow_y_weight * math.max(0, outward / arm_len + s.elbow_y_distance_start)
end

-- RotateUpperArm (L450-479): clavicle yaw (forward) and roll (up) from where the hand is,
-- relative to the upper arm's rest position, as fractions of the arm length.
function ubik.clavicle_angles(forward, upward, arm_len)
    local s = ubik.SETTINGS
    local f, u = forward / arm_len, upward / arm_len
    local yaw
    if f > 0 then yaw = clamp((f - 0.5) * s.shoulder_mult, 0, s.shoulder_limit)
    else yaw = clamp((f - 0.08) * s.shoulder_mult, -s.shoulder_limit, 0) end
    local roll = clamp((u - 0.2) * s.shoulder_mult, 0, s.shoulder_limit)
    return yaw, roll
end

-- World offset for the upper-arm root after swinging the clavicle (root->upper arm) by yaw toward
-- the body's forward and roll toward up. p: {clavicle, rest, yaw, roll, forward, up}.
function ubik.shoulder_shift(p)
    local c = sub(p.rest, p.clavicle)
    local r = len(c)
    local horiz = norm(reject(c, p.up))
    local fwd = norm(reject(p.forward, p.up))
    local y = math.rad(p.yaw)
    local dirh = norm(add(scale(horiz, math.cos(y)), scale(fwd, math.sin(y))))
    local ro = math.rad(p.roll)
    local dir = norm(add(scale(dirh, math.cos(ro)), scale(p.up, math.sin(ro))))
    -- keep c's original vertical tilt out of the comparison: rest maps to zero shift
    local base = norm(add(scale(horiz, math.cos(0)), scale(p.up, 0)))
    local rest_dir = norm(c)
    local moved = add(p.clavicle, scale(norm(add(sub(dir, base), rest_dir)), r))
    return sub(moved, p.rest)
end

-- Arm-length calibration (VRIK/FRIK convention): the widest hand span seen.
ubik.calibration = {}
ubik.calibration.__index = ubik.calibration
function ubik.calibration.new() return setmetatable({ best = nil }, ubik.calibration) end
function ubik.calibration:add(left_hand, right_hand, shoulder_width)
    local arm = (len(sub(left_hand, right_hand)) - shoulder_width) / 2
    if self.best == nil or arm > self.best then self.best = arm end
end
function ubik.calibration:arm_length() return self.best end

return ubik
