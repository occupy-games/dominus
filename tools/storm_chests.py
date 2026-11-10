"""Recover the original storm chest limits, source areas and sampling constants."""
import hashlib
import json
import struct

from tools.current_cards import decode_archive, rows
from tools.native_config import recover
from tools.native_scenery_oracle import NativeImage, ROOT


ROUTINES = [(0x10168d00, 0x10168f19), (0x10257530, 0x10257565),
            (0x10153030, 0x101531e5), (0x1019f2c0, 0x1019f40a),
            (0x101521e0, 0x101523b7), (0x101455f0, 0x10145662),
            (0x10145670, 0x101456e1), (0x100b64b0, 0x100b65cf),
            (0x1013d3c0, 0x1013d503), (0x1013ca10, 0x1013ca98),
            (0x10152ed0, 0x10153026), (0x101523c0, 0x10152875),
            (0x100f1a00, 0x100f1a93), (0x101520c0, 0x10152155),
            (0x10152a30, 0x10152b48), (0x10153370, 0x101536e9),
            (0x101521b0, 0x101521da), (0x10001480, 0x1000153c),
            (0x100015b0, 0x10001661)]


def extract():
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive = (ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image = NativeImage(raw)
    files = decode_archive(archive)
    native = recover(raw, ['storm', 'chest', 'maxrandposchecks', 'deepwatersculptlevel', 'highmountainsculptlevel', 'mintemplesizeblockssculpting', 'storyspawnodds', 'timebetweenburiedtreasurevfx'])
    # These two compiled defaults are in the PE section's zero-filled tail,
    # which has no backing file bytes and is skipped by the generic scanner.
    for name,initializer in [('DebugNumChestSpawnInArea',0x1042d450),('StormsSpawnChests',0x1042d4b0)]:
        code=image.read(initializer,12)
        if code[:2]!=b'\xd9\x05' or code[6:8]!=b'\xd9\x15': raise ValueError('Unexpected chest config initializer')
        pointer,=struct.unpack('<I',code[2:6])
        slot,=struct.unpack('<I',code[8:12])
        section=next((address,start,length,size) for address,start,length,size in image.sections
                     if address+length<=pointer and pointer+4<=address+size)
        native[name]=dict(value=0.,initializer=hex(initializer),data=hex(pointer),slot=hex(slot),
                          storage='PE zero-filled section tail',section=hex(section[0]),bytes='00000000')
    configuration = {key: entry['value'] for key, entry in native.items()}
    used = {}
    for name in ['config.csv', 'balance/config.csv']:
        used[name] = hashlib.sha256(files[name]).hexdigest()
        for row in rows(files, name):
            if len(row)>1 and row[0] and not row[0].startswith('#'):
                try: configuration[row[0]] = float(row[1])
                except ValueError: pass
    constants = {}
    for key, address in [('random_divisor',0x104a0c10), ('angle_scale',0x104d6000), ('reflection',0x104a0d00), ('round_offset',0x104a0c30),
                         ('inverse_height_scale',0x104ae0f0), ('height_origin',0x104aa228), ('footprint_inset',0x104a0d60)]:
        value = image.read(address,8)
        constants[key] = dict(address=hex(address), bytes=value.hex(), value=struct.unpack('<d',value)[0])
    scopes = {}
    for prefix in ['initialworldsetup']+[f'initialworldsetup{i}' for i in range(2,8)]:
        name = prefix+'/influence_areas.csv'
        used[name] = hashlib.sha256(files[name]).hexdigest()
        table = rows(files,name)
        header = table[0]
        required = ['Unlock','x','y','radius','forceOn','maxStormChests','maxDepth','maxTotalChests']
        available = all(key in header for key in required)
        areas = []
        if available:
            for row in table[1:]:
                if not row or row[0].startswith('#') or len(row)<=header.index('maxTotalChests'): continue
                values = {key:row[header.index(key)] for key in required}
                if not values['x']: continue
                areas.append(dict(unlock=values['Unlock'],x=float(values['x']),z=float(values['y']),radius=float(values['radius']),
                                  force=bool(int(values['forceOn'])),max_spawn=int(values['maxStormChests']),
                                  max_depth=int(values['maxDepth']),max_total=int(values['maxTotalChests'])))
        scopes[prefix] = dict(available=available,areas=areas,
                             reason='' if available else 'Original table predates explicit storm chest columns; loader defaults not recovered.')
    rules = dict(enabled=configuration['StormsSpawnChests']!=0,
                 influence_padding=configuration['StormChestsInfluencePadding'],
                 # Native DebugNumChestSpawnInArea lives in zero-initialized BSS.
                 debug_count=configuration.get('DebugNumChestSpawnInArea',0.),
                 attempts=int(configuration['MaxRandPosChecks']),
                 **{key:constants[key]['value'] for key in ['random_divisor','angle_scale','reflection','round_offset']})
    placement_rules=dict(spawn_padding=configuration['ChestSpawnPadding'],deep_level=configuration['DeepWaterSculptLevel'],
                         high_level=configuration['HighMountainSculptLevel'],min_building_half=configuration['MinTempleSizeBlocksSculpting'],
                         **{key:constants[key]['value'] for key in ['round_offset','inverse_height_scale','height_origin','footprint_inset']})
    for key,address in [('deep_unlock',0x104bd8b4),('high_unlock',0x104bd8a0)]:
        text=image.read(address,80).split(b'\0')[0]
        constants[key]=dict(address=hex(address),bytes=(text+b'\0').hex(),value=text.decode())
        placement_rules[key]=text.decode()
    factory_rules=dict(second_level=configuration['ChestLev2'],third_level=configuration['ChestLev3'],rotation=configuration['ChestRot'],
                       story_odds=configuration['StorySpawnOdds'],random_divisor=constants['random_divisor']['value'],
                       inverse_height_scale=constants['inverse_height_scale']['value'])
    for key,address,size,format in [('sea_level',0x104acfb8,4,'<f'),('story_reward',0x104ac154,0,None),('normal_reward',0x104ac920,0,None)]:
        value=image.read(address,size) if size else image.read(address,80).split(b'\0')[0]+b'\0'
        decoded=struct.unpack(format,value)[0] if size else value[:-1].decode()
        constants[key]=dict(address=hex(address),bytes=value.hex(),value=decoded)
        factory_rules[key]=decoded
    core_rules=dict(glint_min=configuration['TimeBetweenBuriedTreasureVFXMin'],glint_max=configuration['TimeBetweenBuriedTreasureVFXMax'],
                    random_divisor=constants['random_divisor']['value'])
    for key,address,size,format in [('height_scale',0x104a0c78,8,'<d'),('minimum_height',0x104a3310,4,'<f')]:
        value=image.read(address,size)
        decoded=struct.unpack(format,value)[0]
        constants[key]=dict(address=hex(address),bytes=value.hex(),value=decoded)
        core_rules[key]=decoded
    id_table='initialworldsetup6/rewardchests.csv'
    used[id_table]=hashlib.sha256(files[id_table]).hexdigest()
    field_layout=dict(source_id=dict(offset=4,table=id_table,column='ID',loader=hex(0x102617a1),bytes=image.read(0x102617a1,6).hex()),
                      phase=dict(offset=0x60,opening=hex(0x10152adc),bytes=image.read(0x10152adc,8).hex()),
                      elapsed=dict(offset=0x58,reset=hex(0x10152b3c),bytes=image.read(0x10152b3c,6).hex()))
    lifetime_rules=dict(open_seconds=configuration['timeToOpenChest'],disappear_seconds=configuration['timeToDisappearChest'],
                        mission_score=configuration['MissionScoreExpedChest'],height_scale=core_rules['height_scale'])
    for key,address in [('exposure_margin',0x104a0d10),('old_height_weight',0x104cc038),('ground_weight',0x104a0c40)]:
        value=image.read(address,8)
        decoded=struct.unpack('<d',value)[0]
        constants[key]=dict(address=hex(address),bytes=value.hex(),value=decoded)
        lifetime_rules[key]=decoded
    for key,address in [('fallback_reward',0x104acc28),('bonus_reward',0x104acc3c),('bonus_unlock',0x104cc00c)]:
        value=image.read(address,80).split(b'\0')[0]
        constants[key]=dict(address=hex(address),bytes=(value+b'\0').hex(),value=value.decode())
        lifetime_rules[key]=value.decode()
    baseline=image.read(0x101536c2,3)
    if baseline[:2]!=b'\x83\xc0':raise ValueError('Unexpected chest total baseline instruction')
    lifetime_rules['count_baseline']=baseline[2]
    lifetime_rules['open_animation']=10 # Original resource selector at 0x10152a9a.
    defaults=[]
    for address in [0x100014c6,0x10001526]:
        code=image.read(address,6)
        if code[:2]!=b'\xc7\x00':raise ValueError('Unexpected unregistered source limit store')
        defaults.append(struct.unpack('<I',code[2:])[0])
    if defaults[0]!=defaults[1]:raise ValueError('Source implicit stock/acquisition limits differ')
    availability_rules=dict(unregistered_limit=defaults[0])
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                tables_sha256=used,native_configuration=native,configuration=configuration,constants=constants,
                rules=rules,placement_rules=placement_rules,factory_rules=factory_rules,core_rules=core_rules,lifetime_rules=lifetime_rules,availability_rules=availability_rules,field_layout=field_layout,scopes=scopes,native_routines={hex(a):image.read(a,b-a).hex() for a,b in ROUTINES})


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/storm-chests.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original storm chest tables:',sum(scope['available'] for scope in content['scopes'].values()),'supported schemas')
