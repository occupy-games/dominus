"""Recover source influence-raster constants and current click threshold."""
import hashlib
import json
import struct

from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive = (ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image = NativeImage(raw)
    files = decode_archive(archive)
    configuration = {row[0]:row[1] for path in ['config.csv','balance/config.csv'] for row in rows(files,path) if len(row)>1}
    addresses = dict(half_cell=(0x104a0c30,8),feather=(0x104a0d00,8),maximum_weight=(0x104acfa8,8),
                     encode_scale=(0x104acff0,8),decode_scale=(0x104bd430,8),default_threshold=(0x1060f5e0,4))
    constants = {key:dict(address=hex(a),bytes=image.read(a,n).hex(),value=struct.unpack('<d' if n==8 else '<f',image.read(a,n))[0])
                 for key,(a,n) in addresses.items()}
    rules = {key:record['value'] for key,record in constants.items() if key!='default_threshold'}
    rules['threshold'] = float(configuration['INFLUENCE_CLICKABLE_SCALE'])
    hardware = rows(files,'hwlevelcontrols.csv')
    desktop = next(row for row in hardware[1:] if row[0]=='DesktopHigh')
    rules['expand'] = bool(int(desktop[hardware[0].index('influenceExpand')]))
    rules['expand_rate'] = constants['half_cell']['value'] # Native 0x1025ae86 reuses 0x104a0c30.
    rules['finish_event'] = image.read(0x104f0284,100).split(b'\0')[0].decode()
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                configuration=dict(INFLUENCE_CLICKABLE_SCALE=configuration['INFLUENCE_CLICKABLE_SCALE']),rules=rules,constants=constants,
                hardware_table_sha256=hashlib.sha256(files['hwlevelcontrols.csv']).hexdigest(),hardware_profile=desktop,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x100d0a10,0x100d0d3c),(0x100cfb40,0x100cfc2c),(0x100cfe30,0x100cff14),
                    (0x100cf550,0x100cf5ae),(0x10257570,0x10257602),(0x1025ab20,0x1025b23b),
                    (0x10025f10,0x10025f34),(0x1039e990,0x1039e9e4)]},
                scope='Native influence raster and authored-area timing constants, current click threshold and original DesktopHigh expansion flag. Dynamic building circles and source campaign coordination remain separate.')


if __name__ == '__main__':
    output = ROOT/'game/assets/original/campaign/influence-rules.json'
    output.write_text(json.dumps(extract(),indent=2)+'\n')
    print('Recovered original influence raster rules')
