-- Self-contained gfx coach. Lessons are read-only and do not intercept
-- Arrange/MIDI keys. The explicit practice button launches a confirmed new tab.
local lessons = require 'coach.lessons'
local state = require 'reaper_state'
local M = {}

function M.open()
    local saved = state.get('coach') or {}
    local page = math.max(1, math.min(#lessons, tonumber(saved.page) or 1))
    local completed = saved.completed or {}
    local width, height = tonumber(saved.w) or 1100, tonumber(saved.h) or 880
    gfx.init('Reaper Keys - Production Coach', width, height, 0)
    local scroll, content_height = 0, 0
    local dirty, last_mouse, last_wheel = true, 0, 0
    local previous_w, previous_h, last_poll, live = 0, 0, 0, ''
    local buttons = {}
    local colors = {
        bg = {0.075, 0.09, 0.105}, panel = {0.115, 0.14, 0.16},
        ink = {0.91, 0.93, 0.91}, muted = {0.65, 0.72, 0.74},
        accent = {0.46, 0.83, 0.67}, warm = {0.95, 0.72, 0.42},
    }
    local function color(name, alpha)
        local c = colors[name]; gfx.set(c[1], c[2], c[3], alpha or 1)
    end
    local function text(x, y, value, size, shade)
        gfx.setfont(1, 'DejaVu Sans', size or 17)
        color(shade or 'ink'); gfx.x, gfx.y = x, y; gfx.drawstr(value)
    end
    local function rect(x, y, w, h, shade, fill)
        color(shade); gfx.rect(x, y, w, h, fill == false and 0 or 1)
    end
    local function wrap(x, y, value, w, size, shade)
        gfx.setfont(1, 'DejaVu Sans', size or 17)
        local line, line_h = '', (size or 17) + 7
        for word in value:gmatch('%S+') do
            local candidate = line == '' and word or line .. ' ' .. word
            if gfx.measurestr(candidate) > w and line ~= '' then
                text(x, y, line, size, shade); y = y + line_h; line = word
            else line = candidate end
        end
        if line ~= '' then text(x, y, line, size, shade); y = y + line_h end
        return y
    end
    local function button(x, y, w, label, fn, active)
        rect(x, y, w, 34, active and 'accent' or 'panel')
        text(x + 10, y + 6, label, 16, active and 'bg' or 'ink')
        buttons[#buttons + 1] = {x = x, y = y, w = w, h = 34, fn = fn}
    end
    local function change_page(next_page)
        page = math.max(1, math.min(#lessons, next_page)); scroll = 0; dirty = true
    end
    local function diagram(kind, w)
        rect(0, 0, w, 126, 'panel')
        if kind == 'modes' then
            local labels = {'Normal', 'v: Time range', 'V: Tracks'}
            for i, label in ipairs(labels) do
                rect(18 + (i - 1) * w / 3, 24, w / 3 - 28, 45, i == 1 and 'accent' or 'muted', false)
                text(28 + (i - 1) * w / 3, 36, label, 17)
            end
            text(20, 91, 'Esc returns to Normal. Context: Arrange or MIDI editor.', 16, 'muted')
        elseif kind == 'signal' or kind == 'finish' or kind == 'repeat' then
            local labels = kind == 'signal' and {'Instrument', 'Track FX', 'Master'}
                or kind == 'finish' and {'Save version', 'Check bounds', 'Render + listen'}
                or {'Record ,a', 'Try @a once', 'Repeat 3@a'}
            for i, label in ipairs(labels) do
                local x = 16 + (i - 1) * w / 3
                rect(x, 25, w / 3 - 36, 45, 'accent', false)
                text(x + 10, 38, label, 16)
                if i < 3 then text(x + w / 3 - 28, 37, '>', 18, 'warm') end
            end
            text(20, 94, kind == 'repeat' and 'Small, tested sequences. No dialogs or recursive macros.'
                or 'Use keys to open the right view; use eyes and ears to decide.', 15, 'muted')
        elseif kind == 'tracks' or kind == 'levels' then
            for i, name in ipairs({'Kick', 'Percussion', 'Bass'}) do
                local y = 12 + (i - 1) * 33
                rect(12, y, w - 24, 28, 'muted', false)
                text(24, y + 4, name, 15)
                rect(154, y + 8, (w - 200) * (0.8 - i * 0.12), 12, 'accent')
            end
            if kind == 'tracks' then text(w - 132, 17, 'V2j: 3 tracks', 14, 'warm') end
        else
            local x0, span = 46, w - 74
            for i = 0, 8 do
                local x = x0 + span * i / 8
                color('muted', 0.45); gfx.line(x, 23, x, 107)
                if i % 2 == 0 then text(x + 3, 5, tostring(i + 1), 13, 'muted') end
            end
            if kind == 'midi' then
                for i = 0, 7 do rect(x0 + i * span / 8 + 3, 86 - (i % 3) * 20, span / 10, 14, 'accent') end
                text(12, 48, 'C', 14, 'warm')
            elseif kind == 'envelope' then
                color('accent'); gfx.line(x0, 90, x0 + span / 3, 42)
                gfx.line(x0 + span / 3, 42, x0 + span * 2 / 3, 42)
                gfx.line(x0 + span * 2 / 3, 42, x0 + span, 85)
                text(x0 + 12, 96, 'Mouse: draw and shape. Keys: show lanes and choose modes.', 14, 'muted')
            elseif kind == 'items' then
                for i = 0, 3 do rect(x0 + i * span / 4 + 3, 36, span / 4 - 6, 46, 'accent', false) end
                text(x0 + 10, 92, 'Select items first. % splits at the edit cursor.', 15, 'muted')
            else
                rect(x0 + 2, 32, span / 2 - 3, 48, 'accent', false)
                text(x0 + 12, 46, '4 bars / 4L', 18, 'accent')
                text(x0 + 10, 94, kind == 'selection' and 't + 4L = play and loop this range' or 'h/l = grid       H/L = measure       4L = four measures', 15, 'muted')
            end
        end
    end
    local function draw()
        buttons = {}
        gfx.dest = -1; rect(0, 0, gfx.w, gfx.h, 'bg')
        if gfx.w < 840 or gfx.h < 640 then
            text(20, 24, 'Enlarge this window to at least 840 x 640.', 20)
            text(20, 60, 'Close with Esc. Your lesson progress is saved.', 16, 'muted')
            gfx.update(); return
        end
        local lesson, sidebar = lessons[page], 224
        text(20, 16, 'REAPER KEYS', 16, 'accent')
        text(20, 42, 'Production coach', 22)
        text(20, 78, 'Default bindings', 14, 'muted')
        for i, entry in ipairs(lessons) do
            local y = 116 + (i - 1) * 35
            local label = (completed[i] and '+ ' or '  ') .. i .. '. ' .. entry.title
            -- Sidebar intentionally uses short labels, full title is in content.
            if #label > 24 then label = label:sub(1, 22) .. '..' end
            button(12, y, sidebar - 28, label, function() change_page(i) end, page == i)
        end
        button(12, 525, sidebar - 28, 'New practice tab...', function()
            local root = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') .. '../../'
            local id = reaper.AddRemoveReaScript(true, 0, root .. 'Scripts/create-practice-project.lua', true)
            if id ~= 0 then reaper.Main_OnCommand(id, 0) end
        end)
        wrap(20, 569, 'A new, silent MIDI tab. Existing projects stay untouched.', sidebar - 40, 14, 'muted')
        local x, w = sidebar + 12, gfx.w - sidebar - 36
        text(x, 16, page .. ' / ' .. #lessons .. '    ' .. lesson.context, 15, 'accent')
        text(x, 43, lesson.title, 25)
        wrap(x, 82, lesson.goal, w, 17, 'muted')
        local viewport_y, viewport_h = 130, gfx.h - 232
        -- Render into an offscreen canvas, then clip by blitting the viewport.
        gfx.setimgdim(1, w, 2000); gfx.dest = 1
        rect(0, 0, w, 2000, 'bg'); diagram(lesson.diagram, w)
        local y = 146
        for _, row in ipairs(lesson.keys) do
            local key_bottom = wrap(4, y, row[1], 185, 17, 'accent')
            local desc_bottom = wrap(200, y, row[2], w - 206, 17)
            y = math.max(key_bottom, desc_bottom) + 9
        end
        for _, block in ipairs({{'TRY IT', lesson.exercise}, {'LOOK FOR', lesson.look}, {'MOUSE IS GOOD HERE', lesson.mouse}}) do
            y = y + 15; text(4, y, block[1], 14, 'warm'); y = y + 26
            y = wrap(4, y, block[2], w - 12, 17, 'muted')
        end
        content_height = y + 16
        scroll = math.max(0, math.min(scroll, math.max(0, content_height - viewport_h)))
        gfx.dest = -1
        gfx.blit(1, 1, 0, 0, scroll, w, viewport_h, x, viewport_y, w, viewport_h)
        if content_height > viewport_h then
            text(x, gfx.h - 95, 'Scroll for the exercise and mouse-friendly advice.', 14, 'warm')
        end
        button(x, gfx.h - 65, 100, '< Previous', function() change_page(page - 1) end)
        button(x + 110, gfx.h - 65, 90, 'Next >', function() change_page(page + 1) end)
        button(x + 212, gfx.h - 65, 155, completed[page] and 'Practiced [+]' or 'Mark practiced', function()
            completed[page] = not completed[page]; dirty = true
        end, completed[page])
        text(x + 385, gfx.h - 58, 'Arrows: lessons | Esc: close', 14, 'muted')
        text(16, gfx.h - 25, live, 13, 'muted')
        gfx.update()
    end
    reaper.atexit(function()
        state.set('coach', {page = page, completed = completed, w = gfx.w, h = gfx.h})
        gfx.quit()
    end)
    local function loop()
        local key = gfx.getchar()
        if key == -1 or key == 27 then return end
        if key == 1818584692 then change_page(page - 1) end -- left
        if key == 1919379572 then change_page(page + 1) end -- right
        if key == 1685026670 then scroll = scroll + 60; dirty = true end -- down
        if key == 30064 then scroll = scroll - 60; dirty = true end -- up
        if gfx.mouse_wheel ~= last_wheel then
            scroll = scroll - (gfx.mouse_wheel - last_wheel) / 120 * 70
            last_wheel = gfx.mouse_wheel; dirty = true
        end
        local mouse = gfx.mouse_cap & 1
        if mouse == 1 and last_mouse == 0 then
            for _, b in ipairs(buttons) do
                if gfx.mouse_x >= b.x and gfx.mouse_x <= b.x + b.w and gfx.mouse_y >= b.y and gfx.mouse_y <= b.y + b.h then b.fn(); break end
            end
        end
        last_mouse = mouse
        if gfx.w ~= previous_w or gfx.h ~= previous_h then previous_w, previous_h, dirty = gfx.w, gfx.h, true end
        local now = reaper.time_precise()
        if now - last_poll > 0.15 then
            last_poll = now
            local current = state.observe('state') or {}
            local left, right = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
            local status = ('LIVE: %s / %s | pending: %s | %d selected tracks | time selection: %.2f - %.2f s'):format(
                current.context or 'main', current.mode or 'normal', current.key_sequence or '',
                reaper.CountSelectedTracks(0), left, right)
            if status ~= live then live, dirty = status, true end
        end
        if dirty then draw(); dirty = false end
        reaper.defer(loop)
    end
    loop()
end
return M
