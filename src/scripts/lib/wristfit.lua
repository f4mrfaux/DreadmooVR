-- Wrist fit (pure): from where the hand's fingers actually point, expressed in the controller's own
-- frame, compute the hand rotation offset that gives a natural grip: wrist -> middle knuckle along
-- the controller's forward, pinky -> index knuckle line along its up. Matrices are 3x3, m[row][col],
-- columns = the rotated frame's X, Y, Z axes, using Unreal's FRotator convention.
local wf = {}

local rad, deg = math.rad, math.deg

function wf.rotator_to_matrix(p, y, r)
    local sp, cp = math.sin(rad(p)), math.cos(rad(p))
    local sy, cy = math.sin(rad(y)), math.cos(rad(y))
    local sr, cr = math.sin(rad(r)), math.cos(rad(r))
    local X = { cp * cy, cp * sy, sp }
    local Y = { sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp }
    local Z = { -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp }
    return { { X[1], Y[1], Z[1] }, { X[2], Y[2], Z[2] }, { X[3], Y[3], Z[3] } }
end

function wf.matrix_to_rotator(m)
    local xz = math.max(-1, math.min(1, m[3][1]))
    local p = deg(math.asin(xz))
    local y = deg(math.atan(m[2][1], m[1][1]))
    local r = deg(math.atan(-m[3][2], m[3][3]))
    return p, y, r
end

local function mul(a, b)
    local c = {}
    for i = 1, 3 do
        c[i] = {}
        for j = 1, 3 do c[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
    end
    return c
end

local function sub(a, b) return { a.X - b.X, a.Y - b.Y, a.Z - b.Z } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function vec(t) return { t.X, t.Y, t.Z } end
local function norm(a)
    local l = math.sqrt(dot(a, a))
    return { a[1] / l, a[2] / l, a[3] / l }
end
local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

-- Columns -> matrix.
local function cols(x, y, z) return { { x[1], y[1], z[1] }, { x[2], y[2], z[2] }, { x[3], y[3], z[3] } } end
local function transpose(m) return cols(m[1], m[2], m[3]) end

-- s: {F, R, U (controller axes, world), hand, middle, index, pinky (bone positions, world),
--     current = {p, y, r} offset in use}. Returns the suggested {p, y, r}.
function wf.suggest(s)
    local F, R, U = vec(s.F), vec(s.R), vec(s.U)
    local function to_ctrl(w) return { dot(w, F), dot(w, R), dot(w, U) } end
    local f = norm(to_ctrl(sub(s.middle, s.hand)))
    local k = to_ctrl(sub(s.index, s.pinky))
    local kd = dot(k, f)
    local kk = norm({ k[1] - kd * f[1], k[2] - kd * f[2], k[3] - kd * f[3] })
    local A = cols(f, kk, cross(f, kk))
    local D = cols({ 1, 0, 0 }, { 0, 0, 1 }, cross({ 1, 0, 0 }, { 0, 0, 1 }))
    local C = mul(D, transpose(A))
    local O = wf.rotator_to_matrix(s.current.p, s.current.y, s.current.r)
    local p, y, r = wf.matrix_to_rotator(mul(C, O))
    return { p = p, y = y, r = r }
end

return wf
