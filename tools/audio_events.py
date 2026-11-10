#!/usr/bin/env python3
"""Recover named Wwise v88 event links and original animation sound markers."""
import hashlib
import json
from pathlib import Path
import re
import struct

try:
    from .original_assets import ROOT, package_media
except ImportError:
    from original_assets import ROOT, package_media


def event_hash(name):
    value = 2166136261
    for byte in name.lower().encode():
        value = ((value * 16777619) & 0xffffffff) ^ byte
    return value


def children(objects, key):
    """Locate a counted child list, verified by each child's parent reference.

    NodeBase parameter lengths vary. Switch case lists repeat child IDs; require
    the largest unique counted list and reject conflicting interpretations.
    """
    kind, body = objects[key]
    if kind not in (5, 6): raise ValueError(f"Unsupported audio container {kind}")
    candidates = []
    for offset in range(10, len(body) - 7):
        count, = struct.unpack_from('<I', body, offset)
        if not 1 <= count <= 128 or offset + 4 + count * 4 > len(body): continue
        ids = struct.unpack_from('<' + 'I' * count, body, offset + 4)
        if len(set(ids)) != count: continue
        if all(child in objects and objects[child][0] in (2, 5, 6)
               and struct.pack('<I', key) in objects[child][1][:80] for child in ids):
            candidates.append((count, offset, ids))
    if not candidates: raise ValueError(f"No verified child list for {key}")
    maximum = max(c[0] for c in candidates)
    candidates = [c for c in candidates if c[0] == maximum]
    if len({c[2] for c in candidates}) != 1: raise ValueError("Ambiguous child list")
    _, offset, ids = candidates[0]
    defaults = ids
    if kind == 6:
        default, = struct.unpack_from('<I', body, offset - 5)
        cursor = offset + 4 + len(ids) * 4
        count, = struct.unpack_from('<I', body, cursor)
        cursor += 4
        for _ in range(count):
            value, number = struct.unpack_from('<II', body, cursor)
            cursor += 8
            selected = struct.unpack_from('<' + 'I' * number, body, cursor)
            cursor += number * 4
            if not set(selected) <= set(ids): raise ValueError("Switch references nonchild")
            if value == default: defaults = selected
    return ids, defaults


def media_for(objects, media, key, default=True, visiting=None):
    visiting = set() if visiting is None else visiting
    if key in visiting: raise ValueError("Cyclic audio graph")
    visiting = visiting | {key}
    kind, body = objects[key]
    if kind == 2:
        if len(body) < 16: raise ValueError("Truncated sound")
        plugin, storage, source, file_id = struct.unpack_from('<4I', body)
        if plugin not in (0x00010001, 0x00040001) or storage not in (0, 1) or source not in media:
            raise ValueError("Unsupported sound source")
        if storage == 1 and source != file_id: raise ValueError("Unresolved streamed file")
        if storage == 0 and file_id != event_hash('GodusMain'): raise ValueError("Unresolved embedded bank")
        return [source]
    if kind == 4:
        count, = struct.unpack_from('<I', body)
        if len(body) != 4 + count * 4: raise ValueError("Invalid event actions")
        refs = struct.unpack_from('<' + 'I' * count, body, 4)
    elif kind == 3:
        # Play actions only; a Stop event may also contain a release-tail Play.
        if len(body) < 6 or body[1] != 4: return []
        refs = [struct.unpack_from('<I', body, 2)[0]]
    else:
        all_children, default_children = children(objects, key)
        refs = default_children if default else all_children
    return sorted({file_id for child in refs for file_id in media_for(objects, media, child, default, visiting)})


def extract(source, output):
    source = Path(source)
    package = source / 'SoundBanks/Mac/GodusMain.pck'
    bank = package.read_bytes()
    media, records = package_media(bank)
    objects = {key: (kind, body) for kind, key, body in records}
    catalog = json.loads((output / 'audio_catalog.json').read_text())
    files = {r['id']: r for r in catalog['assets'] if r['package'] == 'GodusMain'}
    cues, names = {}, {'PLAYSOUND_SCULPTLOOP', 'STOPSOUND_SCULPTLOOP',
                         'PLAYSOUND_FOLLOWERSTATEBUILD', 'PLAYSOUND_FOLLOWERSTATEFINISHBUILDING',
                         'PLAYSOUND_FOLLOWERSTATEREACTTOCHEST', 'PLAYSOUND_FOLLOWERSTATECELEBRATECARD'}
    for path in sorted((source / 'VFX/Scripts/anim').glob('*.txt')):
        markers = []
        for time, name in re.findall(r'@([\d.]+):PLAYSOUND=([A-Za-z_0-9]+)', path.read_text(errors='replace')):
            event = 'PLAYSOUND_' + name.upper()
            names.add(event)
            markers.append({'time': float(time), 'event': event})
        if markers:
            cues[path.stem.lower().strip()] = {'markers': markers, 'source': path.relative_to(source).as_posix(),
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    events, unsupported = {}, []
    for name in sorted(names):
        key = event_hash(name)
        try:
            if objects.get(key, (0,))[0] != 4: raise ValueError('Named event absent from bank')
            all_ids = media_for(objects, media, key, False)
            default_ids = media_for(objects, media, key)
            events[name] = {'id': key, 'media': [files[i]['path'] for i in all_ids],
                'default_media': [files[i]['path'] for i in default_ids]}
        except (ValueError, KeyError, struct.error) as error:
            unsupported.append({'name': name, 'reason': str(error)})
    for cue in cues.values():
        cue['markers'] = [m for m in cue['markers'] if m['event'] in events]
    result = {'source': package.relative_to(source).as_posix(), 'source_sha256': hashlib.sha256(bank).hexdigest(),
              'event_name_source': 'godus.s86', 'event_name_source_sha256': hashlib.sha256((source / 'godus.s86').read_bytes()).hexdigest(),
              'events': events, 'animation_cues': cues, 'unsupported': unsupported,
              'note': 'Original event/media links and VFX marker times. Default switch branches are used; full Wwise mixing is not emulated.'}
    (output / 'audio_events.json').write_text(json.dumps(result, indent=2))
    print(f"Source audio events: {len(events)}, animation cue tracks: {len(cues)}, unavailable: {len(unsupported)}")
    return result


if __name__ == '__main__':
    extract(ROOT / 'data/godus2_4', ROOT / 'game/assets/original')
