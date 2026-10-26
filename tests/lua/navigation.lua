local t = dofile('tests/lua/support.lua')
local tracks = {{}, {}}
local n = tonumber(arg[1]) or 10000
for i = 1, n do
    local track = tracks[(i % 2) + 1]
    track[#track + 1] = {pos = i, len = 1.25}
end
reaper.CountSelectedTracks = function() return #tracks end
reaper.GetSelectedTrack = function(_, i) return tracks[i + 1] end
reaper.GetTrackNumMediaItems = function(track) return #track end
reaper.GetTrackMediaItem = function(track, i) return track[i + 1] end
reaper.GetMediaItemInfo_Value = function(item, key) return key == 'D_POSITION' and item.pos or item.len end
local utils = require 'movement_utils'
collectgarbage('collect')
local started = os.clock()
local result = utils.getItemPositionsOnSelectedTracks()
local elapsed = os.clock() - started
t.eq(#result, n)
for i, item in ipairs(result) do t.eq(item.left, i) end
local big = utils.getBigItemPositionsOnSelectedTracks()
t.eq(#big, 1); t.eq(big[1].left, 1); t.eq(big[1].right, n + 1.25)
print(('items=%d sorted_positions_ms=%.3f'):format(n, elapsed * 1000))
-- A work-budget assertion is deterministic, unlike a wall-clock threshold.
if arg[2] ~= '--benchmark' then
    local original, shifts = table.remove, 0
    table.remove = function(list, index)
        if index == 1 then shifts = shifts + #list - 1 end
        return original(list, index)
    end
    utils.getItemPositionsOnSelectedTracks()
    table.remove = original
    t.eq(shifts, 0, 'quadratic array-tail shifts')
    print('PASS no array-tail shifting')
end
