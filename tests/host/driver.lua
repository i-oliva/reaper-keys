-- Run ONLY in the disposable profile created by run.py.
local root = assert(os.getenv('RK_SOURCE'))
local test_root = assert(os.getenv('RK_TEST_ROOT'))
local output = assert(os.getenv('RK_OUTPUT'))
assert(reaper.GetResourcePath() == os.getenv('RK_RESOURCE'), 'Wrong REAPER profile')
local function report(text)
    local f = assert(io.open(output .. '/report.txt', 'a')); f:write(text .. '\n'); f:close()
end
local function main()
    reaper.Audio_Quit() -- no hardware/audio activity in this test session
    package.path = root .. '/internal/?.lua;' .. root .. '/vendor/?.lua;' .. root .. '/vendor/scythe/?.lua'
    local messages, original_show = {}, reaper.ShowConsoleMsg
    reaper.ShowConsoleMsg = function(message) messages[#messages + 1] = message; original_show(message) end
    report('REAPER ' .. reaper.GetAppVersion())
    assert(reaper.CountTracks(0) == 0)
    local mode = os.getenv('RK_MODE') or 'smoke'
    if mode == 'demo' then
        local original = reaper.ShowMessageBox
        reaper.ShowMessageBox = function() return 6 end
        dofile(root .. '/Scripts/create-practice-project.lua')
        reaper.ShowMessageBox = original
        assert(reaper.CountTracks(0) == 3)
        reaper.Main_SaveProjectEx(0, output .. '/practice.rpp', 8)
        reaper.GetSet_LoopTimeRange(true, false, 0, 8, false)
        local id = reaper.AddRemoveReaScript(true, 0, root .. '/Scripts/show-production-coach.lua', true)
        reaper.Main_OnCommand(id, 0)
        report('COMPLETE demo')
        return
    end
    reaper.InsertTrackAtIndex(0, true); reaper.InsertTrackAtIndex(1, true)
    local a, b = reaper.GetTrack(0, 0), reaper.GetTrack(0, 1)
    reaper.GetSetMediaTrackInfo_String(a, 'P_NAME', 'RK TEST A', true)
    reaper.GetSetMediaTrackInfo_String(b, 'P_NAME', 'RK TEST B', true)
    reaper.SetOnlyTrackSelected(a); reaper.SetEditCurPos(0, false, false)
    reaper.SetProjectGrid(0, 0.25)
    if mode == 'benchmark' then
        -- Open feedback from a separate warmup script, so it stays alive while
        -- each measured script finishes. No rerun/termination prompt involved.
        local input = assert(io.open(test_root .. '/tests/host/cold-key.lua', 'r'))
        local body = input:read('*a'); input:close()
        local warmup = output .. '/warmup.lua'
        local f = assert(io.open(warmup, 'w')); f:write(body); f:close()
        reaper.Main_OnCommand(reaper.AddRemoveReaScript(true, 0, warmup, true), 0)
        local id = reaper.AddRemoveReaScript(true, 0, test_root .. '/tests/host/cold-key.lua', true)
        local count = 0
        local function step()
            reaper.Main_OnCommand(id, 0); count = count + 1
            if count < 100 then reaper.defer(step) else report('COMPLETE benchmark') end
        end
        reaper.defer(step)
        return
    end
    local config = require('definitions.config').general
    config.show_feedback_window = false
    local original_context = reaper.get_action_context
    local function press(code, mod, section)
        reaper.get_action_context = function()
            return true, root .. '/internal/rk.lua', section or 0, 0, 0, 0, 0, 'key:' .. (mod or 'V') .. ':' .. code
        end
        dofile(root .. '/internal/rk.lua')
        reaper.get_action_context = original_context
        assert(#messages == 0, table.concat(messages, '\n'))
    end
    press(32813); press(76)
    assert(reaper.GetCursorPosition() > 0, 'invalid key swallowed motion')
    report('PASS invalid key recovery + grid motion')
    press(74); assert(reaper.GetSelectedTrack(0, 0) == b)
    press(75); assert(reaper.GetSelectedTrack(0, 0) == a)
    report('PASS j/k track navigation')
    press(86); press(76, 'VS')
    local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    assert(e > s and require('reaper_state').getState().mode == 'visual_timeline')
    press(27); assert(require('reaper_state').getState().mode == 'normal')
    report('PASS visual time selection + reset')
    reaper.SetOnlyTrackSelected(a)
    press(86, 'VS'); press(74)
    assert(reaper.CountSelectedTracks(0) == 2)
    press(27); reaper.SetOnlyTrackSelected(a)
    report('PASS visual track selection')
    local marked_position = reaper.GetCursorPosition()
    press(77); press(65); press(76); press(96, ''); press(65)
    assert(math.abs(reaper.GetCursorPosition() - marked_position) < 0.00001)
    report('PASS mark storage + cursor recall')
    reaper.SetEditCurPos(0, false, false)
    require('reaper_state').setState(require('default_state'))
    press(44, ''); press(65); press(76); press(44, '')
    local pos = reaper.GetCursorPosition()
    press(64, ''); press(65); assert(reaper.GetCursorPosition() > pos)
    report('PASS macro recording/playback')
    -- Real item edit + undo validates the undo mask, not merely parser output.
    local item = reaper.CreateNewMIDIItemInProj(a, 0, 4, false)
    reaper.SetMediaItemSelected(item, true); reaper.SetEditCurPos(1, false, false)
    reaper.Undo_OnStateChange2(0, 'test fixture: MIDI item')
    press(37, '') -- %
    assert(reaper.CountMediaItems(0) == 2, 'split count=' .. reaper.CountMediaItems(0))
    reaper.Undo_DoUndo2(0)
    assert(reaper.CountMediaItems(0) == 1, 'undo count=' .. reaper.CountMediaItems(0))
    report('PASS split item + undo')
    item = reaper.GetMediaItem(0, 0)
    local take = reaper.GetActiveTake(item)
    reaper.MIDI_InsertNote(take, true, false, 0, 480, 0, 60, 90, false)
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(40153, 0) -- open MIDI editor
    assert(reaper.MIDIEditor_GetActive())
    press(75, 'VA', 32060) -- Alt+k
    local _, _, _, _, _, _, pitch = reaper.MIDI_GetNote(take, 0)
    assert(pitch == 61, 'MIDI transpose failed')
    press(90, 'VS', 32060)
    report('PASS MIDI context transpose + close')
    config.show_feedback_window = true
    press(32)
    assert(require('reaper_state').getKey('feedback', 'open') == true)
    assert(#require('reaper_state').getKey('feedback', 'completions') > 0)
    report('PASS feedback window + completions')
    reaper.Main_SaveProjectEx(0, output .. '/smoke.rpp', 8)
    report('COMPLETE smoke')
end
local deadline = reaper.time_precise() + 0.75
local function wait_for_startup()
    if reaper.time_precise() < deadline then reaper.defer(wait_for_startup); return end
    local ok, err = xpcall(main, debug.traceback)
    if not ok then report('FAIL ' .. err) end
end
reaper.defer(wait_for_startup)
