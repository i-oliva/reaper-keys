local t = dofile('tests/lua/support.lua')
local state = require 'reaper_state'
local feedback = require 'gui.feedback.controller'
t.ext['reaper_keys:reaper_started'] = 'open'
state.setKeys('feedback', {open = true})
t.writes = {}
local _, entries = t.build('<SPC>')
feedback.clear(); feedback.displayMessage('SPC'); feedback.displayCompletions(entries)
feedback.displayState(state.getState())
t.eq(#t.writes, 1, 'one feedback publish per key')
t.eq(t.writes[1].persist, false)
t.eq(t.view_loads, 0, 'existing feedback must not load window adapters')
local first = state.observe('feedback')
local serpent = require 'serpent'
local original = serpent.load
local parses = 0
serpent.load = function(...) parses = parses + 1; return original(...) end
for _ = 1, 1000 do assert(state.observe('feedback') == first) end
serpent.load = original
t.eq(parses, 0, 'idle feedback parsing')
local search = require 'binding_search'
assert(not search.changed({query = '', binding_list_box = 1}, {query = '', binding_list_box = 2}), 'selection movement must not refilter')
assert(search.changed({query = ''}, {query = 'track'}))
local rows = {{action_name = 'SaveProject', action_binding = '<SPC>ps', action_type = 'command', context = 'global'}}
t.eq(#search.filter(rows, {query = '<SPC>ps', context_filter_active = true, context = 'main'}), 1)
print('PASS feedback publish, idle parse, lazy GUI, selection and key-search budgets')
