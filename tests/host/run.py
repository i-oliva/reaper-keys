#!/usr/bin/env python3
"""Isolated Linux REAPER smoke/benchmark/demo, never the user's desktop/profile.

python3 tests/host/run.py --reaper /usr/lib/REAPER/reaper \
  --sws ~/.config/REAPER/UserPlugins/reaper_sws-x86_64.so \
  --baseline /path/to/upstream --output /tmp/rk-results

Requires Xvfb, xdotool; openbox is optional. No downloads. Closes only its own
processes. Evaluation dialogs are dismissed normally (no licensing changes).
"""
import argparse
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reaper', type=Path, required=True)
    parser.add_argument('--sws', type=Path, required=True)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mode', choices=['all', 'smoke', 'benchmark', 'demo'], default='all')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for tool in ('Xvfb', 'xdotool'):
        if not shutil.which(tool):
            parser.error(f'{tool} is required')
    if not args.sws.is_file() or not args.reaper.is_file():
        parser.error('REAPER executable and SWS library must exist')
    with tempfile.TemporaryDirectory(prefix='reaper-keys-host-') as temporary:
        lab = Path(temporary)
        app = lab / 'app'
        shutil.copytree(args.reaper.resolve().parent, app, symlinks=False)
        # Disable only the copied ReaPack binary to avoid first-run network/UI.
        for plugin in (app / 'Plugins').glob('*reapack*'):
            plugin.rename(lab / plugin.name)
        read_fd, write_fd = os.pipe()
        xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1600x1000x24', '-nolisten', 'tcp'],
                                pass_fds=[write_fd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(write_fd)
        with os.fdopen(read_fd) as display_file:
            display = ':' + display_file.readline().strip()
        assert display != ':' and xvfb.poll() is None, 'Xvfb did not start'
        env = dict(os.environ, DISPLAY=display, HOME=str(lab / 'home'), XDG_CONFIG_HOME=str(lab / 'home/.config'))
        Path(env['HOME']).mkdir()
        wm = None
        try:
            if shutil.which('openbox'):
                wm = subprocess.Popen(['openbox', '--sm-disable'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            cases = []
            if args.mode in ('all', 'benchmark'):
                if args.baseline:
                    cases.append(('baseline', args.baseline.resolve(), 'benchmark'))
                cases.append(('candidate', root, 'benchmark'))
            if args.mode in ('all', 'smoke'):
                cases.append(('smoke', root, 'smoke'))
            if args.mode in ('all', 'demo'):
                cases.append(('demo', root, 'demo'))
            for name, source, mode in cases:
                case = output / name
                case.mkdir(exist_ok=True)
                resource = lab / name
                resource.mkdir()
                (resource / 'UserPlugins').mkdir()
                shutil.copy2(args.sws, resource / 'UserPlugins' / args.sws.name)
                shutil.copy2(root / 'tests/reaper.ini', resource / 'reaper.ini')
                keymap = (root / 'tests/reaper-kb.ini').read_text()
                for section, number in [('main', 0), ('midi', 32060)]:
                    keymap += f'\nSCR 516 {number} _reaper_keys__{section} "reaper-keys" "{source}/internal/rk.lua"\n'
                (resource / 'reaper-kb.ini').write_text(keymap)
                for filename in ('report.txt', 'cold-keys.tsv'):
                    (case / filename).unlink(missing_ok=True)
                child_env = dict(env, RK_SOURCE=str(source), RK_TEST_ROOT=str(root), RK_OUTPUT=str(case),
                                 RK_RESOURCE=str(resource), RK_MODE=mode)
                with (case / 'host.log').open('w') as log:
                    proc = subprocess.Popen([str(app / 'reaper'), '-newinst', '-new', '-nosplash', '-cfgfile',
                                             str(resource / 'reaper.ini'), str(root / 'tests/host/driver.lua')],
                                            env=child_env, stdout=log, stderr=log)
                    try:
                        deadline = time.monotonic() + 60
                        while time.monotonic() < deadline:
                            if proc.poll() is not None:
                                raise RuntimeError(f'{name}: REAPER exited with {proc.returncode}')
                            # All automation is explicitly scoped to the new X display.
                            windows = subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', '^About REAPER'],
                                                     env=child_env, text=True, capture_output=True).stdout.split()
                            for window in windows:
                                geometry = subprocess.run(['xdotool', 'getwindowgeometry', '--shell', window], env=child_env,
                                                          text=True, capture_output=True).stdout
                                dimensions = dict(line.split('=', 1) for line in geometry.splitlines() if '=' in line)
                                if 'WIDTH' in dimensions:
                                    subprocess.run(['xdotool', 'mousemove', '--window', window,
                                                    str(int(dimensions['WIDTH']) - 85), str(int(dimensions['HEIGHT']) - 26), 'click', '1'],
                                                   env=child_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            report_file = case / 'report.txt'
                            report = report_file.read_text() if report_file.exists() else ''
                            if 'FAIL ' in report:
                                raise RuntimeError(f'{name}: {report}')
                            if 'COMPLETE' in report and not windows:
                                break
                            time.sleep(0.2)
                        else:
                            raise TimeoutError(f'{name}: did not complete in 60s')
                        print(report.strip())
                        if mode == 'benchmark':
                            rows = [line.split('\t') for line in (case / 'cold-keys.tsv').read_text().splitlines()]
                            assert len(rows) == 101, f'Expected warmup + 100 samples, got {len(rows)}'
                            assert all(int(row[1]) == 0 for row in rows), 'Unexpected console error during benchmark'
                            samples = sorted(float(row[0]) for row in rows[1:])
                            summary = f'{name}: cold key ms median={statistics.median(samples):.3f} p95={samples[94]:.3f} max={max(samples):.3f}'
                            (case / 'summary.txt').write_text(summary + '\n')
                            print(summary)
                        def xdo(*commands):
                            return subprocess.run(['xdotool', *commands], env=child_env, text=True, capture_output=True)
                        if mode == 'smoke':
                            main_windows = xdo('search', '--onlyvisible', '--name', '^smoke.*REAPER').stdout.split()
                            assert main_windows, 'No REAPER project window'
                            xdo('windowactivate', '--sync', main_windows[0], 'key', 'Escape', 'ctrl+alt+x')
                            time.sleep(0.7)
                            browsers = xdo('search', '--onlyvisible', '--name', '^Reaper Keys Binding List$').stdout.split()
                            if not browsers and shutil.which('import'):
                                consoles = xdo('search', '--onlyvisible', '--name', '^ReaScript console output$').stdout.split()
                                if consoles:
                                    xdo('windowsize', consoles[0], '1050', '900', 'windowmove', consoles[0], '520', '20')
                                    xdo('windowactivate', '--sync', consoles[0], 'key', 'ctrl+Home')
                                    time.sleep(0.2)
                                subprocess.run(['import', '-window', 'root', str(case / 'browser-failure.png')], env=child_env, check=True)
                            assert browsers, 'Binding browser did not open via real Ctrl+Alt+X: ' + xdo('search', '--onlyvisible', '--name', '.*', 'getwindowname').stdout
                            # Do not activate it manually: opening search must keep focus.
                            xdo('type', '--clearmodifiers', 'zzzzqwerty')
                            time.sleep(0.3)
                            if shutil.which('import'):
                                subprocess.run(['import', '-window', 'root', str(case / 'search-no-match.png')], env=child_env, check=True)
                            xdo('key', '--delay', '80', 'ctrl+a'); xdo('type', '--clearmodifiers', '--delay', '25', 'ZoomProject')
                            time.sleep(0.3)
                            xdo('key', 'Return'); time.sleep(0.3)
                            if shutil.which('import'):
                                subprocess.run(['import', '-window', 'root', str(case / 'search-execute.png')], env=child_env, check=True)
                            assert not xdo('search', '--onlyvisible', '--name', '^Reaper Keys Binding List$').stdout.strip(), 'Browser did not execute/close'
                            print('PASS real keyboard -> binding browser -> query -> Enter')
                        if mode == 'demo':
                            coaches = xdo('search', '--onlyvisible', '--name', '^Reaper Keys - Production Coach$').stdout.split()
                            assert coaches, 'Coach window missing'
                            xdo('windowactivate', '--sync', coaches[0])
                            if shutil.which('import'):
                                subprocess.run(['import', '-window', 'root', str(case / 'coach-home.png')], env=child_env, check=True)
                            xdo('key', '--delay', '80', 'Right', 'Right'); time.sleep(0.3)
                            if shutil.which('import'):
                                subprocess.run(['import', '-window', 'root', str(case / 'coach-loop.png')], env=child_env, check=True)
                            xdo('key', '--delay', '80', 'Right', 'Right', 'Right'); time.sleep(0.3)
                            if shutil.which('import'):
                                subprocess.run(['import', '-window', 'root', str(case / 'coach-midi.png')], env=child_env, check=True)
                        if shutil.which('import'):
                            time.sleep(0.4)
                            subprocess.run(['import', '-window', 'root', str(case / 'screen.png')], env=child_env, check=True)
                    finally:
                        proc.terminate()
                        try:
                            proc.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            proc.kill(); proc.wait()
        finally:
            if wm is not None:
                wm.terminate(); wm.wait(timeout=5)
            xvfb.terminate(); xvfb.wait(timeout=5)


if __name__ == '__main__':
    main()
