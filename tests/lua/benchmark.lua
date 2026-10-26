local t = dofile('tests/lua/support.lua')
local start = os.clock()
local build = require 'build'
print(('parser_load_ms %.3f'):format((os.clock() - start) * 1000))
local cases = {'l', '12l', '<SPC>', '<SPC>s', '<SPC>ps', 'd', 'dL', '3gg', ',a', '2@a'}
local samples = {}
for i = 1, 1000 do
    local key = cases[(i - 1) % #cases + 1]
    local t0 = os.clock()
    build({key_sequence = key, mode = 'normal', context = 'main'}, true)
    samples[i] = (os.clock() - t0) * 1000
end
table.sort(samples)
print(('parser_warm_ms p50=%.3f p95=%.3f max=%.3f'):format(samples[500], samples[950], samples[1000]))
-- Fresh parser per key: REAPER runs each action in a separate Lua state.
start = os.clock()
for i = 1, 100 do
    package.loaded.build = nil
    t.build(cases[(i - 1) % #cases + 1])
end
print(('parser_fresh_mean_ms %.3f'):format((os.clock() - start) * 10))
local feedback = require 'gui.feedback.controller'
t.ext['reaper_keys:reaper_started'] = 'open'
require('reaper_state').setKeys('feedback', {open = true})
t.writes = {}
local _, entries = t.build('<SPC>')
feedback.clear(); feedback.displayMessage('SPC'); feedback.displayCompletions(entries)
feedback.displayState(require('default_state'))
local bytes, persisted = 0, 0
for _, w in ipairs(t.writes) do bytes = bytes + w.bytes; if w.persist then persisted = persisted + 1 end end
print(('feedback_one_key writes=%d bytes=%d persisted=%d gui_modules=%d'):format(#t.writes, bytes, persisted, t.view_loads))
