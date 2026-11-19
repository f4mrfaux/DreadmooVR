-- Gesture detectors (pure). Inputs are SteamVR tracking-space positions in metres and seconds,
-- so thresholds do not depend on game scale or UEVR camera offsets. Starting values follow
-- docs/superpowers/specs/2026-11-15-dreadmoor-vr-gestures-design.md ("Gesture definitions").
local gestures = {}

local function sub(a, b) return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z } end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function len(a) return math.sqrt(dot(a, a)) end
local function scale(a, s) return { X = a.X * s, Y = a.Y * s, Z = a.Z * s } end
local function norm(a) local l = len(a); return l > 1e-9 and scale(a, 1 / l) or nil end
local function cross(a, b) return { X = a.Y * b.Z - a.Z * b.Y, Y = a.Z * b.X - a.X * b.Z, Z = a.X * b.Y - a.Y * b.X } end
local function reject(a, n) return sub(a, scale(n, dot(a, n))) end
local function wrap(d) while d > math.pi do d = d - 2 * math.pi end while d < -math.pi do d = d + 2 * math.pi end return d end
local function with_defaults(cfg, d) local o = {} for k, val in pairs(d) do o[k] = (cfg and cfg[k] ~= nil) and cfg[k] or val end return o end

-- Crank: the hand's angle around an axis through a pivot. One click per `step_deg` turned in one
-- direction while turning faster than `min_deg_s`. Either direction counts; a reversal starts over.
gestures.CRANK = { r_min = 0.04, r_max = 0.25, radius_hysteresis_m = 0.025,
    min_deg_s = 110, step_deg = 90, grace_s = 0.25 }
local Crank = {}; Crank.__index = Crank
function gestures.crank(cfg)
    return setmetatable({ cfg = with_defaults(cfg, gestures.CRANK), last = nil, t = nil, acc = 0, dir = 0, slow_since = nil, active_until = -math.huge }, Crank)
end
function Crank:reset() self.last, self.t, self.acc, self.dir, self.slow_since, self.active_until = nil, nil, 0, 0, nil, -math.huge end
-- Returns the number of clicks this update (usually 0 or 1).
function Crank:update(t, hand, pivot, axis, up)
    local c = self.cfg
    local ax = norm(axis)
    local e1 = ax and norm(reject(up, ax))
    if not ax or not e1 then self:reset(); return 0, false end
    local e2 = cross(ax, e1)
    local r = reject(sub(hand, pivot), ax)
    local rl = len(r)
    local margin = self.last ~= nil and (c.radius_hysteresis_m or 0) or 0
    local min_r = math.max(0, c.r_min - margin)
    local max_r = c.r_max + margin
    if rl < min_r or rl > max_r then self:reset(); return 0, false end
    local angle = math.atan(dot(r, e2), dot(r, e1))
    if self.last == nil or self.t == nil or t <= self.t then self.last, self.t = angle, t; return 0, false end
    local d = wrap(angle - self.last)
    local speed = math.deg(math.abs(d)) / (t - self.t)
    self.last, self.t = angle, t
    if speed < c.min_deg_s then
        self.slow_since = self.slow_since or t
        if t - self.slow_since > c.grace_s then self.acc, self.dir = 0, 0 end
        return 0, t <= self.active_until
    end
    self.slow_since = nil
    self.active_until = t + c.grace_s
    local dir = d > 0 and 1 or -1
    if dir ~= self.dir then self.acc, self.dir = 0, dir end
    self.acc = self.acc + math.deg(math.abs(d))
    local clicks = 0
    while self.acc >= c.step_deg do self.acc = self.acc - c.step_deg; clicks = clicks + 1 end
    return clicks, true
end

-- Swing: hand speed above `min_m_s` for `frames` updates in a row, then quiet for `cooldown_s`.
-- Needing consecutive fast frames rejects single-frame tracking jumps.
gestures.SWING = { min_m_s = 2.0, frames = 3, cooldown_s = 0.4 }
local Swing = {}; Swing.__index = Swing
function gestures.swing(cfg)
    return setmetatable({ cfg = with_defaults(cfg, gestures.SWING), last = nil, t = nil, fast = 0, ready_at = -math.huge }, Swing)
end
-- Returns true on the update a swing is recognised.
function Swing:update(t, pos)
    local c = self.cfg
    if self.last == nil or t <= self.t then self.last, self.t = pos, t; return false end
    local speed = len(sub(pos, self.last)) / (t - self.t)
    self.last, self.t = pos, t
    if speed >= c.min_m_s then self.fast = self.fast + 1 else self.fast = 0 end
    if self.fast >= c.frames and t >= self.ready_at then
        self.ready_at = t + c.cooldown_s
        self.fast = -math.huge   -- one event per swing: wait for the hand to slow down first
        return true
    end
    if speed < c.min_m_s then self.fast = 0 end
    return false
end

-- Tapper: turns a count of clicks into separate press/release pulses on one button.
gestures.TAP = { hold = 0.06, gap = 0.06, max_queue = 4 }
local Tapper = {}; Tapper.__index = Tapper
function gestures.tapper(cfg)
    return setmetatable({ cfg = with_defaults(cfg, gestures.TAP), queue = 0, phase = "idle", until_t = 0 }, Tapper)
end
function Tapper:add(n) self.queue = math.min(self.cfg.max_queue, self.queue + (n or 1)) end
-- Is the button down at time t?
function Tapper:pressed(t)
    if self.phase == "down" and t >= self.until_t then self.phase, self.until_t = "gap", t + self.cfg.gap end
    if self.phase == "gap" and t >= self.until_t then self.phase = "idle" end
    if self.phase == "idle" and self.queue > 0 then
        self.queue = self.queue - 1
        self.phase, self.until_t = "down", t + self.cfg.hold
    end
    return self.phase == "down"
end

return gestures
