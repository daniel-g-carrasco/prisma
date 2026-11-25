# SPDX-License-Identifier: GPL-3.0-or-later
"""R658 and R624 source guards. Exceptions match individual drawing statements."""
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


def violations(directory, exceptions=None):
    directory = Path(directory)
    if exceptions is None:
        exceptions = json.loads(Path(__file__).with_name('surface_exceptions.json').read_text(encoding='utf8'))
    found = []
    used = Counter()
    for path in sorted(directory.rglob('*.qml')):
        name = path.relative_to(directory).as_posix()
        code = '\n'.join(line.split('//', 1)[0] for line in path.read_text(encoding='utf8').splitlines())
        if name != 'Surface.qml':
            for line in code.splitlines():
                if re.search(r'\bradius\s*:', line):
                    key = name + ':' + line.strip()
                    if key not in exceptions:
                        found.append(f'{name}: local radius: {line.strip()}')
                    else:
                        used[key] += 1
            if re.search(r'\blayer\.(effect|enabled)\b|\b(ShaderEffect|MultiEffect|OpacityMask|Gradient)\s*\{', code):
                approved = json.loads(Path(__file__).with_name('compositors.json').read_text(encoding='utf8'))
                digest = hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
                if approved.get(name) != digest:
                    found.append(f'{name}: competing compositor, use Surface')
    for key, rule in exceptions.items():
        if not isinstance(rule, dict) or not rule.get('reason') or used[key] != rule.get('count'):
            found.append(f'obsolete or unexplained exception: {key}')
    return found
