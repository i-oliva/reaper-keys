#!/usr/bin/env python3
"""Generate the fork's ReaPack feed from a committed tree, never untracked files.

Usage: python3 tools/build-fork-index.py [commit]
Commit code/docs first, then generate and commit fork-index.xml separately.
"""
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from urllib.parse import quote

root = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


ref = git('rev-parse', '--verify', '--end-of-options', (sys.argv[1] if len(sys.argv) > 1 else 'HEAD') + '^{commit}')
files = git('ls-tree', '-r', '--name-only', ref).splitlines()
installer = git('show', ref + ':Scripts/install-reaper-keys.lua')
version = re.search(r'^-- @version (\S+)', installer, re.MULTILINE).group(1)
index = ET.Element('index', version='1', name='reaper-keys-performance')
category = ET.SubElement(index, 'category', name='Scripts')
package = ET.SubElement(category, 'reapack', name='install-reaper-keys.lua', type='script',
                        desc='reaper-keys: performance fork and production coach')
metadata = ET.SubElement(package, 'metadata')
ET.SubElement(metadata, 'link', rel='website', href='https://github.com/i-oliva/reaper-keys').text = 'Fork repository'
release = ET.SubElement(package, 'version', name=version, author='gwatcha, i-oliva contributors', time=git('show', '-s', '--format=%cI', ref))
selected = [f for f in files if f.startswith(('internal/', 'vendor/', 'Scripts/')) or
            f in ('LICENSE', 'README.md', 'docs/architecture.md', 'docs/production-guide.md', 'docs/performance.md') or
            f.startswith('docs/assets/coach-')]
required = {'Scripts/install-reaper-keys.lua', 'Scripts/show-production-coach.lua', 'Scripts/create-practice-project.lua',
            'internal/coach/view.lua', 'internal/coach/lessons.lua', 'internal/dispatch.lua'}
assert required.issubset(selected), 'Commit the complete fork before generating the feed'
for path in selected:
    attrs = {}
    if path.startswith('Scripts/'):
        attrs['main'] = 'main'
        if path != 'Scripts/install-reaper-keys.lua':
            attrs['file'] = path[len('Scripts/'):]
    else:
        attrs['file'] = '../' + path
    ET.SubElement(release, 'source', **attrs).text = f'https://raw.githubusercontent.com/i-oliva/reaper-keys/{ref}/{quote(path)}'
ET.indent(index, space='  ')
ET.ElementTree(index).write(root / 'fork-index.xml', encoding='utf-8', xml_declaration=True)
print(f'fork-index.xml: {version}, {len(selected)} committed files pinned to {ref}')
