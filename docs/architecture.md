# How reaper-keys works

## One keystroke is one REAPER action invocation

The installer generates a keymap that routes many main/MIDI keyboard shortcuts
to `internal/rk.lua`. REAPER supplies the key code, modifiers and action section.
The script normalizes them into tokens such as `l`, `<SPC>` or `<CM-x>`.

A key invocation has its own Lua state; a deferred feedback/browser script can
remain alive in another state. Consequently, a warm Lua benchmark is not enough:
module loading, shared-state serialization and GUI imports matter on every key.
We retain this native action routing instead of adding a global keyboard hook.

```text
REAPER keyboard action (main / MIDI)
  -> rk.lua: normalize token, retrieve state, append to sequence
  -> build.lua: resolve complete command OR suggest continuations
       -> dispatch.lua: one undo/state/repeat/macro execution path
            -> meta_command.lua: macros, repeat, binding list, coach
            -> execute_command.lua: resolve action names and composition
                 -> action_sequence.lua: apply selector/motion/operator
                      -> definitions.actions / movements / marks
                           -> native REAPER + SWS actions
  -> reaper_state.lua: publish the next state
  -> feedback controller: publish ONE message/completion/mode batch
       -> resident feedback view: observe changed snapshots and redraw
```

## Grammar, definitions and modes

`definitions/bindings.lua` maps keys to symbolic action names, separated into
`global`, `main` and `midi` contexts and action types. Context bindings merge with
and override global bindings. Same-named folders merge recursively; an empty
binding removes an inherited binding.

`action_sequence.lua` defines ordered grammars for Normal, Visual Timeline and
Visual Track. In Normal, `timeline_operator + timeline_motion` can form a command:
`t4L` means loop/play from the cursor through a counted measure motion. In Visual
Timeline, a timeline operator instead acts immediately on the visible selection.
The same principle applies to track operators and Visual Track.

`build.lua` returns a command containing context, mode, action-type sequence and
action keys (including optional count/register arguments). Definitions and
execution grammar are treated as immutable for the lifetime of the Lua state.
Filtered definition tables are cached **per invocation**, not across processes.
Completing a prefix must never remove entries from the execution grammar.

## Execution and selections

`definitions/actions.lua` maps symbolic names to native command IDs, SWS/named
commands, Lua functions, or nested action lists. Action flags specify MIDI
context, count support, register arguments and selection behavior.

`execute_command.lua` resolves these definitions and finds the matching grammar
handler. `action_sequence.lua` makes temporary selections when composing a motion
with an operator and restores them according to the action/config flags. This is
why executing a browser row by action name alone was unsafe: it bypassed context,
composition, undo and macro history. The browser now builds a complete command
and uses the same dispatcher as typed input.

`dispatch.lua` owns the undo block and state reconciliation. It only reloads state
if an internal action published a change. It records repeatable commands/macros
and returns a description. Both callers handle failure explicitly. Closing an
undo block does not mean the command is transactional: if an action partially
edits and then fails, the user may need Undo.

## Shared state and GUI lifetime

`reaper_state.lua` serializes tables through the bundled Serpent library into the
`reaper_keys` ExtState namespace. Runtime `state` and `feedback` are nonpersistent;
macros, marks and preferences remain durable. The new `feedback_window` key keeps
window geometry durable independently of transient feedback.

The feedback controller gathers message, completions and mode in memory. Once the
key has been handled, it publishes one batch with a monotonically increasing
update number. The resident view polls through `observe`, which compares the raw
serialized value before decoding. **Observed snapshots are read-only**: callers
must use `get` and `set`/`setKeys` to modify data. External updates invalidate the
snapshot naturally when the serialized value changes.

GUI modules are loaded only when a window is opened, including the binding
browser in `meta_command.lua`. The bundled Scythe initializes its own helpers
without relying on a separately installed global Scythe copy. The coach uses
native `gfx` directly in its own ReaScript state, not the feedback window's GUI.
It redraws on input, resize or changed live status rather than rebuilding on
every deferred tick.

## Navigation and search work budgets

`movement_utils.lua` enumerates selected-track items once and sorts positions
once. Stable tie ordering is encoded by the original ordinal. Overlapping/touching
items are merged into contiguous "big item" ranges in a linear pass. This removes
the old quadratic array-tail shifting, without caching stale media-item pointers.

`binding_search.lua` owns query scoring/filtering independently of GUI elements.
Only a changed query rescans a row's action name/key string. Filter changes reuse
scores; changing the selected row does not rebuild the list. Matching requires a
complete subsequence, and ties have deterministic ordering.

## Safety and compatibility choices

- No global key interception, detached editing queue, automatic project edits
  from lessons, plug-in substitution or audio-engine changes.
- Existing default command parsing is checked against upstream over 5,919 inputs.
- Limits bound macro nesting/command counts and reject huge repetitions. They do
  not make heavy individual REAPER/SWS actions interruptible or asynchronous.
- There is no persistent project-item cache: correctness across edits/undo/tabs
  is more important than avoiding a cheap enumeration in small projects.
- External action IDs and project-dependent behavior are mostly unchanged.
  Parser equivalence is not a substitute for testing every external action.
- The practice builder edits only a newly created empty tab after confirmation.
  It creates silent MIDI, no files, plug-ins, playback or recording.

See [performance.md](performance.md) for measurements, reproductions and untested
areas, and [production-guide.md](production-guide.md) for workflows.
