local utils = {}

function utils.getItemPositionsOnSelectedTracks()
    local positions = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        for j = 0, reaper.GetTrackNumMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local start = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            positions[#positions + 1] = {left = start, right = start + length, order = #positions + 1}
        end
    end
    -- The old merge removed the first element of a track's array on every
    -- iteration, shifting the entire tail: quadratic on densely edited tracks.
    -- Sort once. The ordinal preserves the old track/item tie ordering.
    table.sort(positions, function(a, b)
        if a.left ~= b.left then return a.left < b.left end
        return a.order < b.order
    end)
    for _, position in ipairs(positions) do position.order = nil end
    return positions
end

function utils.getBigItemPositionsOnSelectedTracks()
    local positions = utils.getItemPositionsOnSelectedTracks()
    local merged = {}
    for _, item in ipairs(positions) do
        local current = merged[#merged]
        if current and item.left <= current.right then
            current.right = math.max(current.right, item.right)
        else
            merged[#merged + 1] = {left = item.left, right = item.right}
        end
    end
    return merged
end

function utils.getTrackPosition()
    local track = reaper.GetLastTouchedTrack()
    if not track then return 0 end
    return reaper.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER') - 1
end

return utils
