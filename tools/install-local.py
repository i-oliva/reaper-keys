#!/usr/bin/env python3
"""Update an existing reaper-keys source tree, preserving config and keymaps.

Only source files are changed. No REAPER windows, projects, keymaps, ExtState,
ReaPack database, license files or services are changed. Stop typing in REAPER
while installing. Restart its feedback script/REAPER later to reload resident UI.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

BASELINE = '22f63ee'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resource', type=Path, required=True)
    parser.add_argument('--backup-root', type=Path, required=True)
    parser.add_argument('--apply', action='store_true', help='default is a read-only preflight')
    parser.add_argument('--restore', type=Path, help='restore code from one backup directory (config stays current)')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    target = args.resource.resolve() / 'Scripts/reaper-keys'
    if target.is_symlink() or not (target / 'internal/rk.lua').is_file():
        parser.error('Target must be an existing, non-symlink reaper-keys installation')
    if any(path.is_symlink() for path in target.rglob('*')):
        parser.error('Symlinks inside the installation require a manual upgrade')
    backup_root = args.backup_root.resolve()
    if backup_root == target or target in backup_root.parents or root == backup_root or root in backup_root.parents:
        parser.error('Backups must be outside the installation and git checkout')
    if not args.restore:
        for relative in ('internal/definitions/actions.lua', 'internal/definitions/bindings.lua'):
            installed = (target / relative).read_bytes()
            upstream = subprocess.check_output(['git', '-C', str(root), 'show', f'{BASELINE}:{relative}'])
            if installed not in (upstream, (root / relative).read_bytes()):
                parser.error(f'Custom definitions detected in {relative}; merge them manually. Nothing changed.')
    source = args.restore.resolve() / 'source' if args.restore else root
    if not (source / 'internal/rk.lua').is_file():
        parser.error('Restore source is not a complete backup')
    files = []
    for folder in ('internal', 'vendor', 'Scripts'):
        for path in (source / folder).rglob('*'):
            if path.is_file() and not path.is_symlink() and path.suffix == '.lua':
                relative = path.relative_to(source)
                if str(relative) == 'internal/definitions/config.lua':
                    continue
                if not (target / relative).exists() or digest(path) != digest(target / relative):
                    files.append(relative)
    # New dependencies first, entry point last. Each replacement is atomic.
    files.sort(key=lambda path: (str(path) == 'internal/rk.lua', str(path)))
    print(f'{len(files)} Lua files to update in {target}; config and keymap are preserved.')
    if not args.apply:
        print('Preflight only. Add --apply to install.')
        return
    backup_root.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-'), dir=backup_root))
    shutil.copytree(target, backup / 'source', symlinks=True)
    manifest = {'target': str(target), 'files': [str(path) for path in files],
                'new_files': [str(path) for path in files if not (target / path).exists()],
                'config_sha256': digest(target / 'internal/definitions/config.lua')}
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    changed = []
    try:
        for relative in files:
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.rk-update-', delete=False) as temporary:
                temporary.write((source / relative).read_bytes())
                name = temporary.name
            os.chmod(name, 0o644)
            os.replace(name, destination)
            changed.append(relative)
        assert digest(target / 'internal/definitions/config.lua') == manifest['config_sha256']
    except BaseException:
        for relative in reversed(changed):
            original = backup / 'source' / relative
            if original.exists():
                shutil.copy2(original, target / relative)
            else:
                (target / relative).unlink(missing_ok=True)
        raise
    print(f'Installed. Code backup: {backup}')
    print('No live REAPER windows or projects were touched. Reload REAPER later for resident GUI changes.')
    print(f'Rollback: python3 tools/install-local.py --resource {args.resource} --backup-root {backup_root} --restore {backup} --apply')
    print('Rollback preserves current config and leaves unused added modules in place; it does not restore stale ExtState.')


if __name__ == '__main__':
    main()
