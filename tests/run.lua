-- Desk test runner for the bridge's pure units.
-- Usage (from the repo root): lua tests/run.lua [pattern]
-- Each tests/test_*.lua returns { name = function() ... end }. Plain asserts.

package.path = "src/scripts/lib/?.lua;src/scripts/?.lua;tests/?.lua;" .. package.path

local function list_tests()
    local files = {}
    local p = io.popen('dir /b "tests\\test_*.lua" 2>nul')
    if p then
        for line in p:lines() do files[#files + 1] = line end
        p:close()
    end
    table.sort(files)
    return files
end

local filter = arg[1]
local passed, failed = 0, 0
for _, file in ipairs(list_tests()) do
    local mod = file:gsub("%.lua$", "")
    if not filter or mod:find(filter, 1, true) then
        package.loaded[mod] = nil
        local ok, suite = pcall(require, mod)
        if not ok then
            print("FAIL " .. file .. ": could not load: " .. tostring(suite):match("[^\n]*"))
            failed = failed + 1
        else
            local names = {}
            for name in pairs(suite) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local okt, err = pcall(suite[name])
                if okt then
                    passed = passed + 1
                else
                    failed = failed + 1
                    print("FAIL " .. file .. "::" .. name .. ": " .. tostring(err))
                end
            end
        end
    end
end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
