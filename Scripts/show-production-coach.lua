-- @description reaper-keys: production coach (visual, read-only)
-- @author gwatcha, i-oliva contributors
if reaper.set_action_options then reaper.set_action_options(1) end -- re-run toggles closed
local root = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') .. '../'
package.path = root .. 'internal/?.lua;' .. root .. 'vendor/?.lua;' .. package.path
require('coach.view').open()
