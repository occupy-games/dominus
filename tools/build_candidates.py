"""Recover the native builder's plot-candidate inputs from resolved house rows."""
import hashlib
import json
import struct

from tools.current_cards import decode_archive, rows
from tools.house_values import ROOT, native_fields, resolve
from tools.native_scenery_oracle import NativeImage


def extract():
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive = (ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    native = native_fields(raw)
    records = resolve(rows(files, 'balance/housevalues.csv'), native)
    image = NativeImage(raw)
    return dict(
        version=1, source='received/godussteamrel/balance.datz',table='balance/housevalues.csv',
        source_sha256=hashlib.sha256(archive).hexdigest(),
        table_sha256=hashlib.sha256(files['balance/housevalues.csv']).hexdigest(),
        executable_sha256=hashlib.sha256(raw).hexdigest(),
        values={key:{field:record['values'][field] for field in ['build capacity', 'buildplotpriority']}
                for key, record in records.items()},
        fields={field:native['fields'][field] for field in ['build capacity', 'buildplotpriority']},
        # Immediate action codes in the original plot-candidate branch/default.
        actions=dict(plot=struct.unpack('<I',image.read(0x100cda1e,4))[0],
                     none=struct.unpack('<I',image.read(0x100cd7a1,4))[0]),
        native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
            (0x100cd790,0x100cda27), (0x100ce0e9,0x100ce15c),
            (0x100ca310,0x100ca398), (0x102d5a70,0x102d5a77),
            (0x100791e0,0x1007920e), (0x101539c0,0x10153a0f),
            (0x1016adb0,0x1016aefc)]})


if __name__ == '__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/build-candidates.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original builder candidate values:',len(data['values']),'source rows')
