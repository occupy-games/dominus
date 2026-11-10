#!/usr/bin/env python3
"""Recover the supplied 2.4 card catalog, localization and exact image references."""
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def decode_archive(raw):
    # godus.s86:1017339e..101733ae, followed by its gzip decoder.
    decoded = bytes(value ^ ((0x6c + index * 0x4d) & 255) for index, value in enumerate(raw))
    if not decoded.startswith(b'\x1f\x8b\x08'):
        raise ValueError('Unknown the original source download encoding')
    body = gzip.decompress(decoded)  # Includes gzip CRC and length validation.
    count, = struct.unpack_from('<I', body)
    if count > 10000:
        raise ValueError('Invalid archive count')
    cursor, files = 4, {}
    for _ in range(count):
        if cursor + 260 > len(body):
            raise ValueError('Truncated archive header')
        length, = struct.unpack_from('<I', body, cursor)
        name = body[cursor + 4:cursor + 260].split(b'\0')[0].decode('utf-8')
        if not name or Path(name).is_absolute() or '..' in Path(name).parts:
            raise ValueError('Invalid archive path')
        payload = body[cursor + 260:cursor + 260 + length]
        if len(payload) != length:
            raise ValueError('Truncated archive payload')
        if name.lower().endswith(('.csv', '.lua', '.txt')):
            payload = payload.rstrip(b'\0')
        if name in files and files[name] != payload:
            raise ValueError('Conflicting duplicate archive member')
        files[name] = payload
        cursor += 260 + ((length + 3) // 4) * 4
    if cursor != len(body):
        raise ValueError('Trailing archive data')
    return files


def rows(files, name):
    return list(csv.reader(io.StringIO(files[name].decode('utf-8-sig'))))


def text(value, localization):
    value = localization.get(value, '') if value.startswith('LOC_') else value
    value = re.sub(r'</?s(?::[^>]+)?>', '', value)
    return value.replace('\\n', '\n').strip()


def extract(source=ROOT / 'data/godus2_4', output=ROOT / 'game/assets/original'):
    archive = source / 'received/godussteamrel/balance.datz'
    files = decode_archive(archive.read_bytes())
    localization = {r[0]: r[1] for r in rows(files, 'gui/localization.csv') if len(r) > 1 and r[0].startswith('LOC_')}
    paths = {str(p.relative_to(source)).lower(): p for p in source.rglob('*.png')}
    targets = output / 'cards_24'
    targets.mkdir(parents=True, exist_ok=True)
    entries, section, duplicates = {}, '', []
    raw_types = {}
    for name in files:
        if re.fullmatch(r'initialworldsetup\d*/carddata.csv', name):
            for row in rows(files, name):
                if len(row) > 4 and row[0].startswith('Card_'):
                    raw_types.setdefault(row[0], {'type': row[2], 'power': row[4]})
    rewards = {}
    for row in rows(files, 'balance/specialcards.csv'):
        if not row or not row[0].startswith('Card_'): continue
        rewards[row[0]] = {key.lower(): int(float(row[index])) for index, key in enumerate(['Name','Gems','Belief','Wheat','Ore','Followers']) if index and len(row) > index and row[index] and row[index].replace('.', '', 1).isdigit()}
    for filename, prefix, image_column in [('gui/carddetails.csv', 'Card_', 9), ('gui/stickerdetails.csv', 'Sticker_', 3)]:
        section = ''
        for line, row in enumerate(rows(files, filename), 1):
            if row and row[0].startswith('#'):
                if not row[0].startswith(('#Card_', '#Sticker_')): section = row[0].lstrip('# ').strip()
                continue
            if len(row) <= image_column or not row[0].startswith(prefix): continue
            card_id = row[0]
            if card_id in entries:
                duplicates.append({'id': card_id, 'line': line, 'table': filename})
                if not row[image_column]: continue
            logical = row[image_column]
            original = next((paths[name + '/' + logical.lower()] for name in ['scaleform', 'scaleform_compiled'] if name + '/' + logical.lower() in paths), None)
            sticker = prefix == 'Sticker_'
            legacy = 'LEGACY' in section or (not sticker and '/cards/' in logical.lower())
            definition = raw_types.get(card_id, {})
            kind = 'resources' if sticker or rewards.get(card_id) or card_id.startswith(('Card_Gems_', 'Card_Belief_', 'Card_Wheat_', 'Card_Ore_')) else 'powers' if card_id.startswith('Card_GodPower_') or definition.get('type') == 'POWER' else 'advances'
            title_key = row[1]
            title = text(title_key, localization) if title_key else text(row[3], localization) if not sticker and row[3] else card_id
            missing_text_keys = [key for key in [title_key] if key.startswith('LOC_') and key not in localization]
            if missing_text_keys: title = card_id
            description_keys = [row[index] for index in [18,17,3] if len(row) > index and row[index]] if not sticker else []
            missing_text_keys += [key for key in description_keys if key.startswith('LOC_') and key not in localization]
            descriptions = list(dict.fromkeys(text(key, localization) for key in description_keys))
            source_path = original.relative_to(source).as_posix() if original else ''
            available = original is not None and not legacy
            entry = {'id':card_id,'canonical_id':card_id,'title':title,'description':'\n\n'.join(descriptions),
                     'kind':kind,'sticker':sticker,'number':int(row[2] or 0) if sticker else int(row[4] or 0),
                     'section':section,'archived':legacy,'internal':title == 'INTERNAL' or card_id in ['Card_STICKER','Card_RANDOM','Sticker_RANDOM'],
                     'available':available,'illustration_source':source_path,'image_reference':logical,
                     'image_sha256':hashlib.sha256(original.read_bytes()).hexdigest() if original else '',
                     'text_source':f'received/godussteamrel/balance.datz:{filename}:{line}',
                     'title_key':title_key,'description_keys':description_keys,'reward':rewards.get(card_id,{}),
                     'missing_text_keys':missing_text_keys,
                     'power':definition.get('power',''),'texture_path':'','thumbnail_path':''}
            if sticker:
                # Sticker details give names, not prose. Their actual typed
                # contributions are retained from stickerdata, without invention.
                for record in rows(files, 'initialworldsetup/stickerdata.csv'):
                    if len(record) > 7 and record[0] == card_id:
                        entry['contributions'] = {record[i]:int(record[i+1]) for i in [4,6] if record[i] and record[i+1]}
                entry['description_keys'] = ['LOC_TUT_219']
                entry['description'] = text('LOC_TUT_219', localization)
            if available:
                entry['texture_path'] = 'res://assets/extracted/' + source_path
                thumb = targets / (card_id + '.png')
                crop = [] if sticker else ['-crop', '256x390+0+61', '+repage']
                subprocess.run(['magick', str(original), *crop, '-resize', '96x146', str(thumb)], check=True, capture_output=True)
                entry['thumbnail_path'] = 'res://assets/original/cards_24/' + thumb.name
                entry['thumbnail_sha256'] = hashlib.sha256(thumb.read_bytes()).hexdigest()
            else:
                entry['unavailable_reason'] = 'Legacy record: no original 2.4 portrait artwork.' if legacy else 'Artwork is absent from the supplied source data.'
            entries[card_id] = entry
    manifest = {'version':1,'source':archive.relative_to(source).as_posix(),'source_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
                'decoder_evidence':'godus.s86:0x1017339e-0x101733c0 (rolling XOR then gzip)',
                'thumbnail_conversion':{'card_crop':[0,61,256,390],'maximum_size':[96,146],'sticker_keep_aspect':True,'converter':'ImageMagick'},
                'tables':{name:hashlib.sha256(files[name]).hexdigest() for name in ['gui/carddetails.csv','gui/stickerdetails.csv','gui/localization.csv','initialworldsetup/stickerdata.csv','balance/specialcards.csv']},
                'duplicates':duplicates,'cards':entries}
    (targets / 'catalog.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f"original 2.4 catalog: {len(entries)} records, {sum(e['available'] for e in entries.values())} source illustrations; no square legacy fallback")
    return manifest


if __name__ == '__main__': extract()
