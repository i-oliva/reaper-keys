-- One execution path for typed commands and the binding browser: balanced undo,
-- internal state changes, repeat history and macro recording stay consistent.
local execute = require 'execute_command'
local meta = require 'meta_command'
local state_store = require 'reaper_state'
local config = require('definitions.config').general

local function describe(command)
    local parts = {}
    for _, action in ipairs(command.action_keys) do
        if type(action) == 'table' then
            parts[#parts + 1] = (action.prefixedRepetitions and action.prefixedRepetitions .. ' ' or '')
                .. action[1] .. (action.register and ' [' .. action.register .. ']' or '')
        else parts[#parts + 1] = action end
    end
    return table.concat(parts, ' + ')
end

local function handle(state, command)
    local new_state = meta(state, command)
    if new_state then return new_state end
    local token = state_store.stateToken()
    execute(command)
    if token ~= state_store.stateToken() then state = state_store.getState() end
    for _, action_type in ipairs(command.action_sequence) do
        for _, pattern in ipairs(config.repeatable_commands_action_type_match) do
            if action_type:find(pattern) then state.last_command = command; break end
        end
    end
    if state.macro_recording then state_store.appendToMacro(state.macro_register, command) end
    state.key_sequence = ''
    return state
end

return function(state, command)
    local description = describe(command)
    reaper.Undo_BeginBlock2(0)
    local ok, result = xpcall(function() return handle(state, command) end, debug.traceback)
    reaper.Undo_EndBlock2(0, 'reaper-keys: ' .. description, -1)
    if not ok then error(result, 0) end
    return result, description
end
