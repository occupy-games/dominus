"""Recover original target-reference validation and bookkeeping constants."""
import hashlib
import json
import struct

from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    image=NativeImage(raw)
    rules=dict(plot_distance_squared=struct.unpack('<d',image.read(0x104bb488,8))[0],
               invalid_identity=struct.unpack('<I',image.read(0x1016ad82,4))[0],
               home_action=image.read(0x100cb004,1)[0],settlement_action=image.read(0x100cb059,1)[0],
               conversion_profession=struct.unpack('<I',image.read(0x100cb066,4))[0],
               settlement_limit=image.read(0x100cb02d,1)[0])
    routines=[(0x10033cd0,0x10033cda),(0x10033d20,0x10033d56),(0x100caeb0,0x100caf60),(0x100caf60,0x100cb0a2),
              (0x1016ad70,0x1016adb0),(0x1016af00,0x1016b133),(0x10034160,0x1003421a),
              (0x1007e5b0,0x1007e60a),(0x100cadc0,0x100cae1a),(0x10043cd0,0x10043cf8)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),rules=rules,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in routines},
                settlement_membership_evidence=image.read(0x10124b74,0x10124ba5-0x10124b74).hex(),
                counter_offsets=dict(houses=dict(assigned=4,workers=struct.unpack('<I',image.read(0x10034184,4))[0],skill=struct.unpack('<I',image.read(0x100341a9,4))[0]),
                                     plots=dict(assigned=4,workers=struct.unpack('<I',image.read(0x1007e5d4,4))[0],skill=struct.unpack('<I',image.read(0x1007e5f9,4))[0])))


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/target-references.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original target-reference rules:',data['rules'])
