-- Run from the repo root. One lesson source for the in-REAPER and written guide.
package.path = './internal/?.lua;' .. package.path
local lessons = require 'coach.lessons'
local out = assert(io.open('docs/production-guide.md', 'w'))
out:write([[# Produce with reaper-keys: a keyboard-and-mouse guide

Open the in-REAPER coach with **Space, then ?**. Use its **New practice tab…**
button to create a separate, unsaved MIDI practice project. It asks first and
leaves the existing project untouched. No plug-ins or audio files are required;
add instruments if you want to hear the MIDI.

The coach's arrows change lessons when the coach is focused. To try the actual
production shortcuts, click Arrange or the MIDI editor first. Scroll inside the
coach for exercises and mouse-friendly advice. **Mark practiced** records your
own progress; it is not an automatic assessment of your playing or editing.

![The production coach running inside REAPER with a disposable MIDI project](assets/coach-home.png)

## Before you begin

- These are the fork's **default** bindings. If you customize them, use
  **Ctrl+Alt+X** to check your actual map.
- Uppercase letters mean Shift. `Space t r` means three sequential keypresses;
  `Ctrl+j` means hold Ctrl and press j. Do not type the spaces between keys.
- `Alt` corresponds to Option where applicable. The live host tests were run on
  Linux; macOS/Windows keyboard layouts still need a human smoke test.
- Keep the feedback strip docked. A floating window can own the keyboard;
  click Arrange/MIDI again if commands stop reaching the project.
- The coach's diagrams explain the operation; they are **not** live displays of
  your notes or waveform. Its bottom status line does read live mode/selection.
- Work in a copy when learning cuts, ripple, automation and recording. Esc is a
  reset, **not Undo**: it also stops playback and resets selections.

]] )
for i, lesson in ipairs(lessons) do
    out:write(('## %d. %s\n\n**Context:** %s. %s\n\n'):format(i, lesson.title, lesson.context, lesson.goal))
    for _, row in ipairs(lesson.keys) do
        out:write(('- **%s** — %s\n'):format(row[1], row[2]))
    end
    out:write(('\n**Try it:** %s\n\n**Look for:** %s\n\n**Mouse is good here:** %s\n\n'):format(lesson.exercise, lesson.look, lesson.mouse))
    if i == 3 then out:write('![Looping lesson, displayed inside REAPER](assets/coach-loop.png)\n\n') end
    if i == 6 then out:write('![MIDI editing lesson, displayed inside REAPER](assets/coach-midi.png)\n\n') end
end
out:write([[## A sensible learning order

Spend the first session on navigation and looping. In the next session, add
visible item/track selection and MIDI editing. Learn marks and macros after you
have one repeated workflow worth recording. You do not need to learn every
binding to benefit.

## When something feels wrong

1. Click the intended Arrange/MIDI view; check the context and mode.
2. Press Esc to reset a pending command. It may stop playback/reset selections.
3. Use Ctrl+Alt+X to find the action or Alt+X for REAPER's native action list.
4. Check snap, ripple, selected items/tracks, and automation mode.
5. For slow plug-ins or a busy project, open **Space v p** (performance meter).
   Faster key processing does not lower audio-buffer or plug-in latency.
6. Test macros once before repeating them. They run synchronously; heavy native
   actions can still take time. Recursive macros and excessive counts are rejected.

For installation, rollback and benchmark limits, see [the fork notes](performance.md).

*Generated from `internal/coach/lessons.lua` by `lua5.4 tools/export-guide.lua`.*
]])
out:close()
