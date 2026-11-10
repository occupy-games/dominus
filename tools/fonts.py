#!/usr/bin/env python3
"""Install the explicitly requested Roboto Condensed from a supplied local copy."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path.home() / 'Library/Fonts')
    args = parser.parse_args()
    target = ROOT / 'game/assets/fonts'
    names = [f'RobotoCondensed-{style}.ttf' for style in ['Regular', 'Bold', 'Italic']]
    originals = [(args.source / name).resolve() for name in names]
    for source in originals:
        if not source.is_file() or source.read_bytes()[:4] not in (b'\0\1\0\0', b'OTTO'):
            parser.error(f'Missing or unsupported font: {source}')
    target.mkdir(parents=True, exist_ok=True)
    records = []
    for source in originals:
        shutil.copyfile(source, target / source.name)
        records.append({'source': str(source), 'path': source.name,
                        'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
    (target / 'provenance.json').write_text(json.dumps({
        'authorization': 'User explicitly requested Roboto Condensed everywhere. This is the font exception to source-only artwork.',
        'files': records}, indent=2))
    print('Installed supplied Roboto Condensed: Regular, Bold, Italic')


if __name__ == '__main__':
    main()
