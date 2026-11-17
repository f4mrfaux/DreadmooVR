-- Hook gun reticle math (pure). The game's aim (GA_HookGun.CalculateLaunchTransform, bp-dumps
-- L00F4..L0525): trace from GetPlayerViewPoint along the view rotation for TraceLength; the hook
-- flies from the gun's muzzle to the hit point. The reticle sits on that same hit point.
local reticle = {}

reticle.MIN_SCALE, reticle.MAX_SCALE = 0.005, 1.0
reticle.DEG_ACROSS = 0.4   -- apparent size of the dot

-- Unit vector for an Unreal rotator (degrees), as KismetMathLibrary.Conv_RotatorToVector.
function reticle.direction(pitch, yaw)
    local p, y = math.rad(pitch), math.rad(yaw)
    return { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end

function reticle.trace_end(start, pitch, yaw, length)
    local d = reticle.direction(pitch, yaw)
    return { X = start.X + d.X * length, Y = start.Y + d.Y * length, Z = start.Z + d.Z * length }
end

-- Scale for the engine's 100 cm sphere so it spans DEG_ACROSS degrees at distance cm.
function reticle.dot_scale(distance)
    local size = 2 * distance * math.tan(math.rad(reticle.DEG_ACROSS / 2))
    return math.max(reticle.MIN_SCALE, math.min(reticle.MAX_SCALE, size / 100))
end

return reticle
