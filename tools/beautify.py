"""Recover the original Beautify terrain action constants."""
import hashlib
import json
import struct

from tools.current_cards import ROOT, decode_archive, rows
from tools.native_scenery_oracle import NativeImage


def extract():
    source = ROOT / 'data/godus2_4'
    raw = (source / 'godus.s86').read_bytes()
    archive = (source / 'received/godussteamrel/balance.datz').read_bytes()
    image = NativeImage(raw)
    files = decode_archive(archive)
    settings = {row[0]: row[1] for path in ['config.csv', 'balance/config.csv']
                for row in rows(files, path) if len(row) > 1}
    configuration = {}
    for address, expected in [
        (0x104b0aa8, 'BELIEF_PER_BEAUTIFY'), (0x104b0abc, 'BEAUTIFY_RADIUS'),
        (0x104b0ae4, 'BEAUTIFY_TIMEOUT'), (0x104bd534, 'LE_TIMER_TICK_LENGTH'),
    ]:
        name = image.read(address, 64).split(b'\0')[0].decode()
        if name != expected:
            raise ValueError('Unexpected Beautify configuration binding')
        configuration[name] = float(settings[name])
    constants = {}
    for name, address, fmt in [
        ('dry_threshold', 0x104acfb8, '<f'), ('water_deduction', 0x104a0be8, '<d'),
        ('clear_threshold', 0x104a0c0c, '<f'), ('encode_scale', 0x104acff0, '<d'),
    ]:
        data = image.read(address, struct.calcsize(fmt))
        constants[name] = dict(address=hex(address), bytes=data.hex(), value=struct.unpack(fmt, data)[0])
    timer_cap = image.read(0x100d07c6, 3)
    if timer_cap[:2] != b'\x83\xfb':
        raise ValueError('Unexpected land effect timer step limit')
    timer = dict(milliseconds_per_second=struct.unpack('<d', image.read(0x104a7518, 8))[0],
                 catch_up_limit=timer_cap[2])
    return dict(
        version=1, executable_sha256=hashlib.sha256(raw).hexdigest(),
        source_sha256=hashlib.sha256(archive).hexdigest(),
        rules=dict(configuration=configuration, timer=timer, **{name: row['value'] for name, row in constants.items()}),
        constants=constants,
        native_routines={hex(start): image.read(start, end-start).hex() for start, end in [
            (0x10086500, 0x1008652b), (0x10086780, 0x1008688e), (0x10086890, 0x10086cb6),
            (0x100cf5b0, 0x100cf9d0), (0x100d0020, 0x100d01d2), (0x100d0590, 0x100d0722),
        ]},
        timer_routines={hex(start): image.read(start, end-start).hex() for start, end in [
            (0x100d0730, 0x100d0a04), (0x1035f876, 0x1035f8eb),
            (0x10362d20, 0x10362d54), (0x10362d60, 0x10362e0a),
        ]},
    )


if __name__ == '__main__':
    path = ROOT / 'game/assets/original/campaign/beautify.json'
    path.write_text(json.dumps(extract(), indent=2) + '\n')
    print('Original Beautify terrain action recovered')
