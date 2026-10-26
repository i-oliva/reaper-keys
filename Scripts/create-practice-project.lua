-- @description reaper-keys: create a disposable practice project in a NEW tab
-- @author gwatcha, i-oliva contributors
if reaper.ShowMessageBox(
    'Create a NEW, unsaved practice tab with three MIDI tracks?\n\n' ..
    'Your existing project is left alone. No plug-ins, recording, playback or audio files are created.\n' ..
    'The MIDI is silent until you add instruments. Close the practice tab without saving to discard it.',
    'Reaper Keys Practice Project', 4) ~= 6 then return end

reaper.Main_OnCommand(40859, 0) -- New project tab (not New project)
if reaper.CountTracks(0) ~= 0 then
    reaper.ShowMessageBox('The new tab is not empty. Nothing was changed.', 'Practice project cancelled', 0)
    return
end
reaper.Undo_BeginBlock2(0)
local ok, err = xpcall(function()
    reaper.SetCurrentBPM(0, 120, false)
    reaper.SetProjectGrid(0, 0.25)
    local names = {'01 KICK - practice', '02 PERCUSSION - practice', '03 BASS - practice'}
    local colors = {{94, 184, 146}, {228, 176, 102}, {112, 169, 202}}
    local end_time = reaper.TimeMap2_QNToTime(0, 16)
    for i, name in ipairs(names) do
        reaper.InsertTrackAtIndex(i - 1, false)
        local track = reaper.GetTrack(0, i - 1)
        reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', name, true)
        reaper.SetTrackColor(track, reaper.ColorToNative(table.unpack(colors[i])) | 0x1000000)
        reaper.SetMediaTrackInfo_Value(track, 'D_VOL', 0.25)
        local item = reaper.CreateNewMIDIItemInProj(track, 0, end_time, false)
        local take = reaper.GetActiveTake(item)
        reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', 'Four-bar keyboard practice', true)
        for beat = 0, 15 do
            local qn = beat + (i == 2 and 0.5 or 0)
            local start_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn)
            local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn + (i == 3 and 0.75 or 0.2))
            local pitch = i == 1 and 36 or i == 2 and 42 or (beat % 4 == 3 and 43 or 36)
            reaper.MIDI_InsertNote(take, false, false, start_ppq, end_ppq, 0, pitch, i == 3 and 75 or 95, true)
        end
        reaper.MIDI_Sort(take)
    end
    reaper.AddProjectMarker2(0, true, 0, end_time, 'PRACTICE: four bars at 120 BPM', -1, 0)
    reaper.SetOnlyTrackSelected(reaper.GetTrack(0, 0))
    reaper.SetMediaItemSelected(reaper.GetTrackMediaItem(reaper.GetTrack(0, 0), 0), true)
    reaper.SetEditCurPos(0, false, false)
    reaper.TrackList_AdjustWindows(false)
    reaper.Main_OnCommand(40295, 0) -- Zoom project
    reaper.UpdateArrange()
    local root = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') .. '../'
    package.path = root .. 'internal/?.lua;' .. root .. 'vendor/?.lua;' .. package.path
    require('reaper_state').setState(require('default_state'))
end, debug.traceback)
reaper.Undo_EndBlock2(0, 'reaper-keys: create practice project', -1)
if not ok then reaper.ShowMessageBox(err, 'Practice project error (Undo to revert)', 0) end
