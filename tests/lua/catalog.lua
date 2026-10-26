-- Differential command-catalog snapshot. Run against upstream and candidate
-- with RK_SOURCE and diff the output. Every candidate gets a fresh parser.
local t = dofile('tests/lua/support.lua')
local serpent = require 'serpent'
local actions = require 'definitions.actions'
local function flatten(entries, prefix, result)
    for key, entry in pairs(entries) do
        if type(entry) == 'table' then flatten(entry[2], prefix .. key, result)
        elseif entry ~= '' then
            local opts = actions[entry]
            local suffix = type(opts) == 'table' and opts.registerAction and 'a' or ''
            result[#result + 1] = prefix .. key .. suffix
            if type(opts) == 'table' and opts.prefixRepetitionCount then
                result[#result + 1] = '3' .. prefix .. key .. suffix
            end
        end
    end
end
local cases = {}
for _, context in ipairs({'main', 'midi'}) do
    for _, mode in ipairs({'normal', 'visual_timeline', 'visual_track'}) do
        package.loaded.build = nil; package.loaded.action_sequence = nil
        local _, entries = t.build('', context, mode, false)
        local types = {}
        for kind, definitions in pairs(entries) do
            types[kind] = {}; flatten(definitions, '', types[kind])
            for _, key in ipairs(types[kind]) do cases[context .. '\t' .. mode .. '\t' .. key] = {context, mode, key} end
        end
        if mode == 'normal' then
            -- Cover operator/motion and operator/selector composition, not just leaves.
            local _, all = t.build('', context, 'visual_timeline', false)
            local _, tracks = t.build('', context, 'visual_track', false)
            for _, pair in ipairs({{'timeline_operator', 'timeline_motion'}, {'timeline_operator', 'timeline_selector'},
                {'track_operator', 'track_motion'}, {'track_operator', 'track_selector'}}) do
                local left, right = {}, {}
                flatten(entries[pair[1]] or {}, '', left)
                flatten(all[pair[2]] or tracks[pair[2]] or {}, '', right)
                for _, op in ipairs(left) do
                    for _, motion in ipairs(right) do
                        local key = op .. motion
                        cases[context .. '\t' .. mode .. '\t' .. key] = {context, mode, key}
                    end
                end
            end
        end
    end
end
local keys = {}; for key in pairs(cases) do keys[#keys + 1] = key end; table.sort(keys)
for _, key in ipairs(keys) do
    local case = cases[key]
    package.loaded.build = nil; package.loaded.action_sequence = nil
    local command = t.build(case[3], case[1], case[2])
    print(key .. '\t' .. serpent.line(command, {comment = false, sortkeys = true}))
end
