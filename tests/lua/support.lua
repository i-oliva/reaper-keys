local root = os.getenv('RK_SOURCE') or assert(os.getenv('PWD'))
package.path = root .. '/internal/?.lua;' .. root .. '/vendor/?.lua;' .. root .. '/vendor/scythe/?.lua;' .. package.path
local M = {root = root, ext = {}, writes = {}, calls = {}, logs = {}, view_loads = 0}
reaper = {
    GetOS = function() return 'Linux' end,
    GetExtState = function(ns, key) return M.ext[ns .. ':' .. key] or '' end,
    SetExtState = function(ns, key, value, persist)
        M.ext[ns .. ':' .. key] = value
        M.writes[#M.writes + 1] = {key = key, persist = persist, bytes = #value}
    end,
    ShowConsoleMsg = function(s) M.logs[#M.logs + 1] = s end,
    time_precise = os.clock,
    atexit = function() end,
    Undo_BeginBlock2 = function() M.undo = (M.undo or 0) + 1 end,
    Undo_EndBlock2 = function() M.undo = M.undo - 1 end,
    NamedCommandLookup = function() return 100 end,
    Main_OnCommand = function(id) M.calls[#M.calls + 1] = id end,
    MIDIEditor_LastFocused_OnCommand = function(id) M.calls[#M.calls + 1] = id end,
    get_action_context = function() return true, root .. '/internal/rk.lua', 0, 0, 0, 0, 0, M.key_context end,
}
-- Only the window adapters are replaced. Parser, definitions, state, executor,
-- feedback controller and runtime entry point are the production code.
package.preload['gui.feedback.View'] = function()
    M.view_loads = M.view_loads + 1
    return {new = function() return {open = function() end} end}
end
package.preload['gui.binding_list.View'] = function() M.view_loads = M.view_loads + 1; return {} end
package.preload['gui.utils'] = function() return {} end
package.preload['gui.core'] = function() return {} end
function M.eq(actual, expected, message)
    assert(actual == expected, (message or '') .. ' expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
function M.build(keys, context, mode, construct)
    return require('build')({key_sequence = keys, context = context or 'main', mode = mode or 'normal'}, construct ~= false)
end
function M.press(code, mod)
    M.key_context = 'key:' .. (mod or 'V') .. ':' .. code
    dofile(root .. '/internal/rk.lua')
end
return M
