import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='rk-install-test-') as temporary:
    lab = Path(temporary)
    target = lab / 'resource/Scripts/reaper-keys'
    for name in ('internal', 'vendor', 'Scripts'):
        for line in subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-r', '--name-only', '22f63ee', name], text=True).splitlines():
            path = target / line
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(subprocess.check_output(['git', '-C', str(root), 'show', f'22f63ee:{line}']))
    config = target / 'internal/definitions/config.lua'
    config.write_text(config.read_text().replace('gui_scale = 1.6', 'gui_scale = 2.0'))
    before = {str(p.relative_to(target)): hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*') if p.is_file()}
    keymap = lab / 'resource/reaper-kb.ini'; keymap.write_text('DO NOT CHANGE\n')
    command = ['python3', str(root / 'tools/install-local.py'), '--resource', str(lab / 'resource'), '--backup-root', str(lab / 'backups')]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    assert not (lab / 'backups').exists(), 'preflight wrote a backup'
    subprocess.run(command + ['--apply'], check=True, stdout=subprocess.DEVNULL)
    assert 'gui_scale = 2.0' in config.read_text()
    assert keymap.read_text() == 'DO NOT CHANGE\n'
    assert (target / 'internal/rk.lua').read_bytes() == (root / 'internal/rk.lua').read_bytes()
    backup = next((lab / 'backups').iterdir())
    subprocess.run(command + ['--restore', str(backup), '--apply'], check=True, stdout=subprocess.DEVNULL)
    for name, digest in before.items():
        assert hashlib.sha256((target / name).read_bytes()).hexdigest() == digest, f'rollback mismatch: {name}'
    bindings = target / 'internal/definitions/bindings.lua'
    bindings.write_text(bindings.read_text() + '\n-- custom definitions\n')
    refused = subprocess.run(command + ['--apply'], capture_output=True, text=True)
    assert refused.returncode != 0 and 'Custom definitions' in refused.stderr
print('PASS install preflight, config/keymap preservation, source rollback, custom-definition refusal')
