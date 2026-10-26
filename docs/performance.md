# Performance and production-coach fork

Based on upstream `22f63ee` (2.0.0-a20). Fork release: **2.0.0-a21**.
This is an alpha fork, not an upstream release. Existing default shortcuts are
preserved; **Space → ?** adds the production coach.

## Measured results

On Linux, REAPER 7.82, an isolated Xvfb display and a disposable profile:

| Measurement | Upstream | Fork | Interpretation |
|---|---:|---:|---|
| Fresh-VM key processing, median | 5.617 ms | 3.390 ms | About 40% less processing time |
| Fresh-VM key processing, p95 | 9.935 ms | 4.022 ms | About 60% less processing time |
| Fresh-VM key processing, maximum of 100 | 14.027 ms | 4.456 ms | Sample maximum, not a latency guarantee |
| 20,000-item position gathering, median of 5 | 521.355 ms | 22.784 ms | About 23× faster in this synthetic test |
| Feedback publication for one Space prefix | 5 writes | 1 write | One coherent update per key |
| Persistent feedback writes for that key | 5 | 0 | Transient UI data stays session-local |
| Parsing an unchanged feedback snapshot 1,000 times | 1,000 parses | 0 parses | Raw-value comparison before deserialization |

**Method and limits:** the fresh-VM test runs the real `rk.lua` once per fresh
ReaScript VM, with a resident feedback window, two empty tracks, and a grid-right
command. It measures script processing, **not physical key-to-screen or audio
latency**. The first window-creation sample is excluded. The dense-item test
uses real navigation code with stubbed REAPER getters: it isolates the list
algorithm, not the cost of a real 20,000-item project's API/UI updates. Host
load and CPU frequency affect timings. A previous run had different absolute
numbers but the same direction of improvement.

These changes do not accelerate plug-in loading, audio rendering, disk streaming,
SWS internals or REAPER's audio engine. Macros remain synchronous; a heavy action
can still block the UI. No broad asynchronous key interception was introduced.

## What changed

- **Input/parser:** direct first-token parsing; per-invocation option-filter
  caches; correct multi-key prefix stripping; anchored count parsing. Completion
  queries no longer mutate the shared execution grammar or merged bindings.
  Counted composed commands still offer the right next actions.
- **Execution:** keyboard and binding-browser actions share `dispatch.lua`.
  Undo blocks close even on exceptions, and item/MIDI edits are included in undo
  state. Failure resets pending input and macro recording, rather than leaving
  the keyboard stuck. Partial edits are not automatically rolled back.
- **Feedback:** publish one batch, sort completions once, avoid durable writes
  for transient state, cache read-only snapshots while idle, and load the GUI
  only when opening a window. Window geometry remains durable separately.
- **Diagnostics:** disabled log levels no longer format/serialize whole state
  objects on every key. Non-keyboard action contexts are ignored safely.
- **Binding browser:** reject non-matches, search key strings as well as action
  names, avoid rescoring when moving selection, keep global entries when
  filtering a context, use deterministic tie ordering, and preserve focus.
  Enter executes a complete valid command through the normal dispatcher. A
  partial operator/register binding explains what is still required instead of
  running it against an unintended selection.
- **Bundled GUI:** initialize the vendored Scythe helpers without requiring a
  separate global installation. Decoded Ctrl/Cmd control characters remain
  shortcuts even if the modifier is released before the deferred GUI handles
  them.
- **Dense-item navigation:** replace repeated front-removal from arrays with one
  stable-by-position sort. Equal-position track/item ordering is retained.
- **Macros:** reject recursive playback, cap nesting at 16, validate repetition
  counts (default maximum 10,000), cap macro command steps, and return internal
  mode changes to the caller. Limits reject, rather than silently truncate.
- **Learning:** 11 native-gfx lessons, illustrative diagrams, live mode/selection
  status, saved self-reported progress, a confirmed new-tab practice builder,
  and a [written production guide](production-guide.md) with REAPER screenshots.
- **Installation:** back up an existing generated keymap before replacing it,
  close the output file before showing import instructions, and fix the digit
  range. Source-upgrade tooling preserves config and refuses custom definitions
  rather than overwriting them.

## Install or upgrade

### Existing installation: preserve your shortcut map

The `tools/install-local.py` helper upgrades an existing
`REAPER/Scripts/reaper-keys` tree. It does **not** open REAPER, change a project,
import keymaps or modify ReaPack's database. Run it when not typing into REAPER;
close/reopen the resident feedback script or restart REAPER later for the full
UI changes. Do not interrupt a recording to do this.

```sh
# From this checkout; adjust both absolute paths for your machine.
python3 tools/install-local.py \
  --resource /path/to/REAPER \
  --backup-root /path/outside/the/repo/reaper-keys-backups

# Review the preflight, then repeat with --apply.
```

It preserves `internal/definitions/config.lua` byte for byte, so a new default
option may be absent from your file; `max_repetitions` has a runtime fallback.
Actions/bindings must match upstream a20 or this fork; custom definitions require
an explicit manual merge. The source tree is backed up, and each changed file is
replaced atomically, dependencies before the entry point. This is **not** a
whole-directory atomic transaction: avoid concurrent script use during install.
The tool prints an exact rollback command. Rollback restores source, preserves
current config, leaves unused added modules, and does not rewind your macros or
ExtState. Keep backups private and outside the Git checkout.

A source upgrade does not switch ReaPack ownership. **Pin the old ReaPack package**
if you keep using this manual installation; a later upstream reinstall/update
can overwrite the fork. Do that in ReaPack when convenient, not during a session.

### Fresh installation / managed fork channel

Add this repository URL in ReaPack:

```text
https://raw.githubusercontent.com/i-oliva/reaper-keys/performance-and-coach/fork-index.xml
```

The channel installs into its own `reaper-keys-performance` repository folder.
It uses immutable commit-pinned source URLs. The old `index.xml` is retained as
upstream history; **it is not the fork channel**. Do not run both copies' input
handlers together. Back up/export the current keymap before changing which copy
it points to. SWS is required; the GUI library is bundled.

Run `install-reaper-keys.lua` from the fork, then import the generated keymap as
instructed. This can replace existing mapped shortcuts. The coach and practice
scripts are also exposed as standalone actions by the fork package. Channel XML
and source targets are validated locally; ReaPack's GUI installation is not part
of the automated host suite.

## Reproduce the checks

```sh
sh tests/run-lua
python3 tests/test_install.py
lua5.4 tests/lua/benchmark.lua
lua5.4 tests/lua/navigation.lua 20000

python3 tests/host/run.py \
  --reaper /usr/lib/REAPER/reaper \
  --sws /path/to/reaper_sws-x86_64.so \
  --baseline /path/to/upstream-a20-checkout \
  --output /tmp/reaper-keys-results
```

The host runner creates its own X display, HOME and REAPER profile, disables
its copied ReaPack plug-in, closes its audio device, and terminates only the
processes it created. It does not use a running user's REAPER session. It requires
Xvfb/xdotool; openbox and ImageMagick enable window management/screenshots. It
normally dismisses REAPER's evaluation dialog, without modifying licensing.

The suite checks Lua syntax; parser/state/search/error/macro regressions;
serialization and GUI-load budgets; dense-item ordering; 35 tutorial key
sequences; install/rollback; and real-host navigation, visual selections, marks,
macros, item split/undo, MIDI transpose, feedback, and keyboard-driven binding
search/Enter. The coach is rendered and inspected in the isolated host.

A differential run of `tests/lua/catalog.lua` against a20 and the fork compared
**5,919 inputs across Arrange/MIDI and modes**. Results were identical; the six
additional rows are the new coach shortcut in each context/mode. This is parser
compatibility evidence, not proof that every external REAPER/SWS action works.
The older upstream `.rks` suite remains available; it is not claimed as run by
this new suite. Windows/macOS, alternate layouts/HiDPI, live recording, every
third-party action and long project-specific macros still need user validation.
