"""Recover original house terrain/damage/work frame constants and protocol."""
import hashlib
import json
import struct

from tools.current_cards import ROOT
from tools.native_scenery_oracle import NativeImage


MODIFIER_DESTINATIONS = {
    0x10fcd814: 'follower_health', 0x10fcd818: 'birth_rate',
    0x10fcd81c: 'build_time', 0x10fcd820: 'multiplayer_rewards',
    0x10fcd824: 'walk_speed', 0x10fcd828: 'walk_range',
    0x10fcd82c: 'abode_belief', 0x10fcd830: 'tree_belief',
    0x10fcd838: 'influence', 0x10fcd83c: 'settlement_cost',
    0x10fcd840: 'settlement_belief', 0x10fcd844: 'farm_build_time',
    0x10fcd848: 'farmer_capacity', 0x10fcd84c: 'location_3_fertility',
}


def progression_modifiers(image):
    initialization = image.read(0x10437ec0, 0x59)
    stack = []
    defaults = {}
    offset = 0
    while initialization[offset] != 0xc3:
        opcode = initialization[offset:offset + 2]
        offset += 2
        if opcode in (b'\xd9\xee', b'\xd9\xe8'):
            stack.append(float(opcode == b'\xd9\xe8'))
        elif opcode in (b'\xd9\x15', b'\xd9\x1d'):
            address, = struct.unpack_from('<I', initialization, offset)
            defaults[MODIFIER_DESTINATIONS[address]] = stack[-1]
            offset += 4
            if opcode == b'\xd9\x1d':
                stack.pop()
        else:
            raise ValueError('Unexpected instruction in original modifier defaults')
    descriptors = []
    for address in range(0x105e4bf8, 0x105e4cac, 12):
        name, value, destination = struct.unpack('<III', image.read(address, 12))
        descriptors.append({
            'unlock': image.read(name, 80).split(b'\0')[0].decode(),
            'field': MODIFIER_DESTINATIONS[destination],
            'value': struct.unpack('<f', image.read(value, 4))[0],
            'record_address': hex(address),
            'value_address': hex(value),
            'destination_address': hex(destination),
        })
    return {'defaults': defaults, 'descriptors': descriptors}


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw);constants={}
    for name,address,fmt in [('ordinary_seconds',0x105b2d58,'f'),('attached_seconds',0x105b2d5c,'f'),
                             ('forced_rate',0x104ad750,'d'),('other_phase_rate',0x104a0d10,'d')]:
        data=image.read(address,struct.calcsize(fmt))
        constants[name]=dict(address=hex(address),bytes=data.hex(),value=struct.unpack('<'+fmt,data)[0])
    hook=image.read(0x104bb5d0,80).split(b'\0')[0].decode()
    rules={name:record['value'] for name,record in constants.items()}
    rules.update(complete_sound=0x33cbd896,complete_hook=hook,complete_handle_kind=0x04000000,damage_notice=12)
    ranges=[(0x100bb96b,0x100bbbdb),(0x10356fd0,0x10356ff5),
            (0x100b7e80,0x100b7ef5),(0x101b3181,0x101b31a5),(0x10437ec0,0x10437f19)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),rules=rules,constants=constants,
                modifiers=progression_modifiers(image),
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Original foundation, house damage and construction frame, build-time target calculation, and ordered progression modifier writes. Stat-row resolution, model/effect/economy services and the remaining house lifetime are explicit dependencies.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/house-terrain-frame.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original house terrain/work frame constants recovered')
