-- Host benchmark: invoked in a fresh ReaScript VM for each key.
local root = assert(os.getenv('RK_SOURCE'))
local output = assert(os.getenv('RK_OUTPUT'))
local start = reaper.time_precise()
package.path = root .. '/internal/?.lua;' .. root .. '/vendor/?.lua;' .. root .. '/vendor/scythe/?.lua'
local config = require('definitions.config').general
config.show_start_up_message = false
local original = reaper.get_action_context
reaper.get_action_context = function()
    return true, root .. '/internal/rk.lua', 0, 0, 0, 0, 0, 'key:V:76'
end
local messages, show = {}, reaper.ShowConsoleMsg
reaper.ShowConsoleMsg = function(s) messages[#messages + 1] = s; show(s) end
dofile(root .. '/internal/rk.lua')
reaper.get_action_context = original
local elapsed = (reaper.time_precise() - start) * 1000
local f = assert(io.open(output .. '/cold-keys.tsv', 'a'))
f:write(('%0.6f\t%d\n'):format(elapsed, #messages)); f:close()
