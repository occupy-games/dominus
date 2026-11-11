"""Extract the original mission-3 terrain, actors, timers and tutorial copy."""
import hashlib
import json

from tools.campaign import packed_map
from tools.campaign_scenarios import ROOT, assignment, literal, named_function, nested_arrays
from tools.current_cards import decode_archive, rows, text
from tools.voyage_lua import Compiler, CompileError

SCOPE = 'tutoriallevels/tut02_leashtutorial'
WIDTH = 64
ORIGIN = (104, 88)


def extract(source=ROOT/'data/godus2_4'):
    archive = (source/'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    script = files[SCOPE+'/scripts.lua']
    compiler = Compiler(script.decode('utf-8-sig'))
    values = {}
    for key in ('INITIAL_ABODE', 'TARGET_ABODE', 'INITIAL_FOLLOWER_CAMERA', 'ABODE_CAMERA',
                'GROUP_CAMERA', 'GROUP_CENTER', 'INITIAL_FOLLOWER', 'TEMPLE', 'BUILD_TIME_OVERRIDE'):
        values[key] = literal(assignment(compiler, key), values)

    def point(x, z):
        return [x-ORIGIN[0], z-ORIGIN[1]]

    def position(key):
        item = values[key]
        return point(item['x'], item['y'])

    post_load = compiler.functions[named_function(compiler, 'onPostLoad')[1]]['body']
    followers = []
    for node in nested_arrays(post_load):
        if node[:2] != ['call', ['var', 'SpawnFollower']]:
            continue
        args = [literal(arg, values) for arg in node[2]]
        followers.append({'position':point(args[1], args[2]), 'rotation':args[3], 'female':args[5]})
    if len(followers) != 5:
        raise CompileError('Expected five authored mission-3 follower spawns')
    temple, = [row for row in rows(files,SCOPE+'/templepositions.csv') if len(row)>9 and row[6].isdigit()]
    info = {row[0]:row[1] for row in rows(files,SCOPE+'/info.csv') if len(row)>1}
    belief, = [int(row[2]) for row in rows(files,SCOPE+'/info.csv') if row[:2]==['Config','InitialBelief']]
    pack = source/'stream'/f"{info['Map Prefix']}.pack"
    fields, _, _, _ = packed_map(pack)
    crop = b''.join(fields['terrain'][z*1024+ORIGIN[0]:z*1024+ORIGIN[0]+WIDTH]
                    for z in range(ORIGIN[1],ORIGIN[1]+WIDTH))
    config = {row[0]:row[1] for row in rows(files,'config.csv') if len(row)>1}
    loc = {row[0]:row[1] for row in rows(files,'gui/localization.csv') if len(row)>1}
    message_keys = [
        '078_6', '079', '080_6', '081', '082_6', '083', '099_6a', '100_6',
        '084', '085_6', '086', '086_6', '087', '086_6a', '089', '090_6',
        '091', '092', '093_6', '094', '095_6', '096', '149_6',
    ]
    messages = {'LOC_TUT_'+suffix:text('LOC_TUT_'+suffix, loc) for suffix in message_keys}
    return crop, {
        'scope':SCOPE, 'mission':3, 'map':info['Map Prefix'], 'origin':ORIGIN, 'width':WIDTH,
        'source_sha256':hashlib.sha256(archive).hexdigest(),
        'script_sha256':hashlib.sha256(script).hexdigest(),
        'pack_sha256':hashlib.sha256(pack.read_bytes()).hexdigest(),
        'terrain_sha256':hashlib.sha256(crop).hexdigest(),
        'followers':followers, 'belief':belief, 'messages':messages,
        'initial_home':position('INITIAL_ABODE'), 'target':position('TARGET_ABODE'),
        'group_center':position('GROUP_CENTER'),
        'temple_hint':position('TEMPLE'),
        'temple':{'id':temple[6], 'type':temple[0], 'position':point(int(temple[1]), int(temple[2])),
                  'source_height':int(temple[3]), 'rotation':int(temple[4]),
                  'build_ticks':int(temple[8])*10, 'build_capacity':int(temple[9])},
        'camera':[position(key)+[values[key]['z']] for key in ['INITIAL_FOLLOWER_CAMERA','ABODE_CAMERA','GROUP_CAMERA']],
        'build_ticks':values['BUILD_TIME_OVERRIDE']*10,
        'hold_seconds':float(config['LeashFirstHoldTime']),
        'max_length':float(config['LeashMaxLength']),
        'follower_cost':int(config['LeashBeliefPerFollower']),
        'home_cost':int(config['LeashBeliefPerHouse']),
        'temple_falloff':float(config['templeFixerFalloff']),
        'leash_color':[float(config['LeashColour.'+axis]) for axis in 'xyz']+[float(config['LeashOpacity'])],
        'leash_size':float(config['LeashSize']),
    }


def write(source, output):
    crop, data = extract(source)
    output.mkdir(parents=True, exist_ok=True)
    (output/'leash-lesson.bin').write_bytes(crop)
    (output/'leash-lesson.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')


if __name__ == '__main__':
    write(ROOT/'data/godus2_4', ROOT/'game/assets/original/campaign')
