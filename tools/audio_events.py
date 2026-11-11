#!/usr/bin/env python3
"""Recover named Wwise v88 event links and original animation sound markers."""
import hashlib
import json
from pathlib import Path
import re
import struct

try:
    from .original_assets import ROOT, chunks, package_media
except ImportError:
    from original_assets import ROOT, chunks, package_media


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


def beautify_loop(objects, media):
    """Read the two v88 actions and the shared embedded PCM sound they control."""
    transitions, actions, targets = {}, {}, set()
    for phase, name, opcode in [('attack', 'PLAYSOUND_BEAUTIFY', 0x0403),
                                 ('release', 'STOPSOUND_BEAUTIFY', 0x0102)]:
        kind, event = objects[event_hash(name)]
        if kind != 4 or len(event) != 8 or struct.unpack_from('<I', event)[0] != 1:
            raise ValueError('Expected one Beautify action')
        action_id, = struct.unpack_from('<I', event, 4)
        kind, body = objects[action_id]
        tail = event_hash('GodusMain') if phase == 'attack' else 0
        if (kind != 3 or len(body) != 19 or struct.unpack_from('<H', body)[0] != opcode
                or body[6:9] != bytes([0, 1, 0x0F]) or body[13:15] != bytes([0, 4])
                or struct.unpack_from('<I', body, 15)[0] != tail):
            raise ValueError('Unsupported Beautify transition properties')
        targets.add(struct.unpack_from('<I', body, 2)[0])
        transitions[phase + '_ms'], = struct.unpack_from('<I', body, 9)
        actions[phase] = action_id
    if len(targets) != 1:
        raise ValueError('Beautify actions must target the same sound')
    target, = targets
    kind, body = objects[target]
    plugin, storage, media_id, bank_id = struct.unpack_from('<4I', body)
    if (kind != 2 or plugin != 0x00010001 or storage != 0 or bank_id != event_hash('GodusMain')
            or len(body) < 43 or body[26] != 0 or body[31:35] != bytes(4)):
        raise ValueError('Expected embedded PCM with no local effects or parent')
    # The 25-byte source header precedes the empty FX list, bus, parent and
    # priority flags. The v88 property bundle stores IDs before their values.
    count = body[37]
    keys = body[38:38 + count]
    values_offset = 38 + count
    if count != 2 or set(keys) != {0x00, 0x07} or body[values_offset + 8:values_offset + 13] != bytes([0, 1, 1, 0, 0]):
        raise ValueError('Expected volume, loop and unpanned 2D positioning')
    volume_db, = struct.unpack_from('<f', body, values_offset + 4 * keys.index(0x00))
    loops, = struct.unpack_from('<I', body, values_offset + 4 * keys.index(0x07))
    payload = media[media_id]
    riff = chunks(payload, 12, True)
    if payload[:4] != b'RIFF' or payload[8:12] != b'WAVE' or loops != 0 or b'smpl' in riff:
        raise ValueError('Expected an infinite full-sample Beautify loop')
    rate, _, block_align = struct.unpack_from('<IIH', riff[b'fmt '], 4)
    frames, trailing = divmod(len(riff[b'data']), block_align)
    if trailing or frames == 0 or rate == 0:
        raise ValueError('Invalid Beautify PCM dimensions')
    return {**transitions, 'target': target, 'actions': actions, 'media_id': media_id,
            'volume_db': volume_db, 'loop_frames': frames, 'sample_rate': rate}


def extract(source, output):
    source = Path(source)
    package = source / 'SoundBanks/Mac/GodusMain.pck'
    bank = package.read_bytes()
    media, records = package_media(bank)
    objects = {key: (kind, body) for kind, key, body in records}
    catalog = json.loads((output / 'audio_catalog.json').read_text())
    files = {r['id']: r for r in catalog['assets'] if r['package'] == 'GodusMain'}
    cues, names = {}, {'PLAYSOUND_SCULPTLOOP', 'STOPSOUND_SCULPTLOOP',
                         'PLAYSOUND_BEAUTIFY', 'STOPSOUND_BEAUTIFY',
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
    from tools.native_scenery_oracle import NativeImage
    executable = (source / 'godus.s86').read_bytes()
    image = NativeImage(executable)
    sacrifice_calls = [0x100f2e27, 0x100f2e46]
    sacrifice_id = 0x9402b4ea
    if any(image.read(address,5)!=b'\x68'+struct.pack('<I',sacrifice_id) for address in sacrifice_calls):
        raise ValueError('Missing native Pit sacrifice sound bindings')
    events['Pit of Doom sacrifice'] = {'id':sacrifice_id,
        'media':[files[i]['path'] for i in media_for(objects,media,sacrifice_id,False)],
        'default_media':[files[i]['path'] for i in media_for(objects,media,sacrifice_id)],
        'instructions':[hex(address) for address in sacrifice_calls]}
    fountain_address, fountain_event = 0x1013e920, 0x0cf86816
    if image.read(fountain_address,5)!=b'\x68'+struct.pack('<I',fountain_event):
        raise ValueError('Missing native Fountain celebration audio binding')
    events['Fountain celebration']={'id':fountain_event,'instructions':[hex(fountain_address)],
        'media':[files[i]['path'] for i in media_for(objects,media,fountain_event,False)],
        'default_media':[files[i]['path'] for i in media_for(objects,media,fountain_event)]}
    collection_address, collection_event = 0x1003d15a, 0x33a63352
    if image.read(collection_address,5)!=b'\x68'+struct.pack('<I',collection_event):
        raise ValueError('Missing native belief collection audio binding')
    bubble_path = 'SoundBanks/Mac/BubbleTunes.pck'
    bubble_bank = (source/bubble_path).read_bytes()
    bubble_media, bubble_records = package_media(bubble_bank)
    bubble_objects = {key:(kind,body) for kind,key,body in bubble_records}
    event_type, collection = bubble_objects[collection_event]
    count, = struct.unpack_from('<I',collection)
    if event_type!=4 or len(collection)!=4+count*4: raise ValueError('Invalid belief collection event')
    direct_sounds = []
    for action in struct.unpack_from('<'+'I'*count,collection,4):
        kind, body = bubble_objects[action]
        if kind!=3 or body[1]!=4: continue
        target, = struct.unpack_from('<I',body,2)
        target_type, sound = bubble_objects[target]
        if target_type!=2: continue
        plugin, storage, media_id, bank_id = struct.unpack_from('<4I',sound)
        if plugin!=0x10001 or storage!=0 or bank_id!=event_hash('BubbleTunes') or media_id not in bubble_media:
            raise ValueError('Unsupported direct belief collection sample')
        direct_sounds.append((action,target,media_id))
    if len(direct_sounds)!=1: raise ValueError('Expected the common belief collection sound layer')
    action, target, media_id = direct_sounds[0]
    sample = next(r['path'] for r in catalog['assets'] if r['package']=='BubbleTunes' and r['id']==media_id)
    events['Shrine belief collection']={'id':collection_event,'instructions':[hex(collection_address)],
        'source':bubble_path,'source_sha256':hashlib.sha256(bubble_bank).hexdigest(),
        'action':action,'target':target,'media':[sample],'default_media':[sample],
        'note':'Direct sound shared by the original event. Adaptive musical branches are separate.'}
    rain_events = [(0x100faa3e, 0xd7d664ed), (0x100faa9b, 0x3e9d0357)]
    rain_voices = {}
    for phase, (address, key) in zip(('attack', 'release'), rain_events):
        kind, event = objects[key]
        if image.read(address,5)!=b'\x68'+struct.pack('<I',key) or kind!=4 or len(event)!=12:
            raise ValueError('Missing original Rain of Purity audio event')
        for action_id in struct.unpack_from('<2I',event,4):
            kind, action = objects[action_id]
            opcode, target = struct.unpack_from('<HI',action)
            if kind!=3 or opcode!=(0x0403 if phase=='attack' else 0x0102):
                raise ValueError('Unexpected Rain of Purity audio action')
            transition = 0
            if action[7]==1 and action[8]==0x0f:
                transition, = struct.unpack_from('<I',action,9)
            elif action[7]!=0:
                raise ValueError('Unexpected Rain of Purity transition parameters')
            voice = rain_voices.setdefault(target,{})
            voice[phase+'_ms'] = transition
            voice[phase+'_action'] = action_id
            if phase!='attack': continue
            kind, sound = objects[target]
            count = sound[37]
            keys = sound[38:38+count]
            properties = 38+count
            if kind!=2 or not {0,7}<=set(keys) or struct.unpack_from('<I',sound,properties+4*keys.index(7))[0]!=0:
                raise ValueError('Expected Rain of Purity infinite loop')
            media_id, = struct.unpack_from('<I',sound,8)
            volume, = struct.unpack_from('<f',sound,properties+4*keys.index(0))
            wave = chunks(media[media_id],12,True)
            rate, _, align = struct.unpack_from('<IIH',wave[b'fmt '],4)
            if b'smpl' in wave or not align or len(wave[b'data'])%align:
                raise ValueError('Expected full Rain of Purity loop')
            voice.update(media=files[media_id]['path'],volume_db=volume,sample_rate=rate,
                         loop_frames=len(wave[b'data'])//align)
    if len(rain_voices)!=2 or any('media' not in v or 'release_action' not in v for v in rain_voices.values()):
        raise ValueError('Rain of Purity must start and stop both source sounds')
    try:
        beautify = beautify_loop(objects, media)
        beautify['media'] = files[beautify['media_id']]['path']
    except (ValueError, KeyError, struct.error, ZeroDivisionError) as error:
        beautify = {}
        unsupported.append({'name': 'Beautify loop', 'reason': str(error)})
    result = {'source': package.relative_to(source).as_posix(), 'source_sha256': hashlib.sha256(bank).hexdigest(),
              'event_name_source': 'godus.s86', 'event_name_source_sha256': hashlib.sha256(executable).hexdigest(),
              'events': events, 'animation_cues': cues, 'beautify_loop': beautify, 'unsupported': unsupported,
              'rain_loop': {'events':[{'id':key,'instruction':hex(address)} for address,key in rain_events],
                            'voices':list(rain_voices.values())},
              'note': 'Original event/media links and VFX marker times. Default switch branches are used; full Wwise mixing is not emulated.'}
    (output / 'audio_events.json').write_text(json.dumps(result, indent=2))
    print(f"Source audio events: {len(events)}, animation cue tracks: {len(cues)}, unavailable: {len(unsupported)}")
    return result


if __name__ == '__main__':
    extract(ROOT / 'data/godus2_4', ROOT / 'game/assets/original')
