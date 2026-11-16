-- Which activity the player is in, from the possessed pawn's class chain, and the enter/exit
-- bookkeeping when it changes.
-- main.lua passes already-loaded modules when UEVR has no require; tests use require.
local deps = ...
local gameapi = type(deps) == "table" and deps.gameapi or require("gameapi")

local modes = {}

function modes.classify(chain)
    for _, name in ipairs(chain) do
        for _, pair in ipairs(gameapi.MODE_CLASSES) do
            if name == pair[1] then return pair[2] end
        end
    end
    return "unknown"
end

local Tracker = {}
Tracker.__index = Tracker

-- handlers: { [mode] = { enter = fn, exit = fn } }; any part may be missing.
function modes.new(handlers)
    return setmetatable({ handlers = handlers or {}, current = nil }, Tracker)
end

function Tracker:update(mode)
    if mode == self.current then return end
    local old = self.current and self.handlers[self.current]
    if old and old.exit then old.exit() end
    self.current = mode
    local new = self.handlers[mode]
    if new and new.enter then new.enter() end
end

return modes
