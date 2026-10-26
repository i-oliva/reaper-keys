local t = dofile('tests/lua/support.lua')
local tests = {}
local function test(name, fn) tests[#tests + 1] = {name, fn} end

test('ordinary command and counted motion', function()
    t.eq(t.build('l').action_keys[1], 'RightGridDivision')
    local c = t.build('12l')
    t.eq(c.action_keys[1][1], 'RightGridDivision')
    t.eq(c.action_keys[1].prefixedRepetitions, 12)
    t.eq(t.build('<SPC>ps').action_keys[1], 'SaveProject')
    t.eq(t.build('k', 'midi').action_keys[1], 'PitchUp')
end)
test('completions do not mutate execution grammar', function()
    local serpent = require 'serpent'
    local sequences = require 'action_sequence'
    local before = serpent.dump(sequences.action_sequence_keys)
    t.build('d', 'main', 'normal', false)
    t.eq(serpent.dump(sequences.action_sequence_keys), before, 'grammar changed')
    t.eq(t.build('dL').action_keys[1], 'CutItems')
end)
test('counted operator still offers motion completions', function()
    local _, entries = t.build('d2')
    assert(entries and entries.timeline_motion and entries.timeline_motion.L)
end)
test('feedback off recovers from invalid keys', function()
    require('definitions.config').general.show_feedback_window = false
    t.press(32813) -- unbound Insert
    t.eq(require('reaper_state').getState().key_sequence, '')
    t.press(85) -- u / Undo, must not be swallowed
    assert(#t.calls > 0, 'Undo never reached the action dispatcher')
end)
test('transient state is not persisted', function()
    t.writes = {}
    require('reaper_state').setState(require('default_state'))
    require('reaper_state').setKeys('feedback', {message = 'test'})
    for _, w in ipairs(t.writes) do t.eq(w.persist, false, w.key) end
    require('reaper_state').clearMacro('a')
    t.eq(t.writes[#t.writes].persist, true, 'macros must survive restarts')
end)
test('unmatched binding search returns no rows', function()
    local rows = {{action_name = 'SaveProject', action_binding = '<SPC>ps', action_type = 'command', context = 'main'}}
    t.eq(#require('binding_search').filter(rows, {query = 'zzzzqwerty'}), 0)
end)
test('complete fuzzy match, not one character short', function()
    local fuzzy = require('fuzzy').fuzzy_match
    t.eq(fuzzy('save', 'SaveProject'), true)
    t.eq(fuzzy('savex', 'SaveProject'), false)
end)
test('failed action balances undo and resets input', function()
    require('definitions.actions').Undo = function() error('injected action failure') end
    t.press(85)
    t.eq(t.undo, 0, 'unclosed undo block')
    t.eq(require('reaper_state').getState().key_sequence, '')
end)
test('recursive macros fail promptly instead of freezing', function()
    local command = {context = 'main', mode = 'normal', action_sequence = {'command'}, action_keys = {{'PlayMacro', register = 'a'}}}
    require('reaper_state').set('macros', {a = {command}})
    debug.sethook(function() error('instruction budget exceeded') end, '', 100000)
    local ok, err = pcall(require('meta_command'), require('reaper_state').getState(), command)
    debug.sethook()
    assert(not ok and tostring(err):find('Recursive macro'), tostring(err))
end)
test('huge repetition counts fail before dispatch', function()
    t.calls = {}
    local ok = pcall(require('action_sequence').run, {123, prefixedRepetitions = 1000000000})
    assert(not ok); t.eq(#t.calls, 0)
end)
test('fast Ctrl+A is not inserted as a control character', function()
    local called = false
    local box = {insertChar = function() error('control character inserted') end}
    local bypass = require('gui.elements.shared.text').doCtrlChar(box, {kb = {char = 1, ctrl = false}},
        function() called = true end)
    assert(called and bypass)
end)
test('macro state changes are returned to the caller', function()
    local change = {context = 'main', mode = 'normal', action_sequence = {'command'}, action_keys = {'SetModeVisualTimeline'}}
    require('reaper_state').set('macros', {b = {change}})
    local command = {context = 'main', mode = 'normal', action_sequence = {'command'}, action_keys = {{'PlayMacro', register = 'b'}}}
    local result = require('meta_command')(require('reaper_state').getState(), command)
    t.eq(result.mode, 'visual_timeline')
end)
local failed = 0
for _, entry in ipairs(tests) do
    package.loaded.build = nil
    package.loaded.action_sequence = nil
    t.ext = {}; t.undo = 0
    local ok, err = pcall(entry[2])
    print((ok and 'PASS ' or 'FAIL ') .. entry[1] .. (ok and '' or ': ' .. tostring(err)))
    if not ok then failed = failed + 1 end
end
print(('%d tests, %d failures'):format(#tests, failed))
os.exit(failed == 0 and 0 or 1)
