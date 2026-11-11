"""Recover the original Homeworld6 village and festival parameters."""
import hashlib
import json
import re
import struct
from pathlib import Path

from tools.campaign_scenarios import assignment, literal
from tools.current_cards import decode_archive, rows, text
from tools.native_config import recover
from tools.native_scenery_oracle import ROOT, NativeImage
from tools.original_assets import iw_hash
from tools.voyage_lua import Compiler


def extract(source, models, output):
    source = Path(source)
    executable = (source / 'godus.s86').read_bytes()
    archive = (source / 'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    image = NativeImage(executable)
    scope = 'initialworldsetup6'
    script_path = f'{scope}/scripts.lua'
    lua = files[script_path].decode('utf-8-sig')
    parser = Compiler(lua)
    village = literal(assignment(parser, 'ASTARI_VILLAGE'), {})
    abodes = list(literal(assignment(parser, 'ASTARI_ABODE'), {}).values())
    setup = lua.split('-- Create the Astari Village', 1)[1].split('-- Create the Terraced Fields', 1)[0]
    create, = re.findall(r'CreateBespokeSettlement\(pos\.x,pos\.y,alleg,(\d+),(\d+),(\d+),\s*astariInitialAmount-\(astariAbodes\*(\d+)\),\s*(\d+),\s*(\d+),\s*"(LOC_\w+)",\s*\{([0-9, ]+)\}\)', setup)
    job, width, depth, residents, breed, race = map(int, create[:6])
    levels = [int(level) for level in create[7].split(',') if level.strip()]
    delay = int(re.search(r'After\((\d+), SetupVillageAI, alleg\)', setup)[1])
    if (job, width, depth, residents, breed, race) != (9, 6, 8, 5, 1, 4) or len(levels) != width * depth:
        raise ValueError('Unexpected original village layout')
    if setup.count('BuildAbode(') != 1 or 'alleg = 1' not in setup:
        raise ValueError('Missing original village population')

    parameters = {
        'population': 'AstariBasePopulation',
        'length': 'AstariFestivalLength',
        'interval': 'AstariFestivalInverval',
        'boost': 'AstariFestivalHappiness',
        'decay': 'AstariHappinessDecayPerFestivalInterval',
        'post_limit': 'MaxFollowersToConvertPostFestival',
        'catchup_limit': 'MaxFollowersToConvertOnFestivalCatchup',
        'post_fraction': 'MaxOwnFollowerPercentConvertPostFestival',
        'population_effect': 'AstariHappinessPopulationEffectScale',
        'population_adjust_max': 'AstariHappinessMaxAdjust',
        'max_steps': 'FollowerMaxStepsPerUnit',
    }
    native = recover(executable, ['astari', 'festival', 'convert', 'followermaxstepsperunit'])
    config = {row[0]: row[1] for name in ('config.csv', 'balance/config.csv')
              for row in rows(files, name) if len(row) > 1 and row[1]}
    rules = {key: float(config.get(name, native[name]['value'])) for key, name in parameters.items()}
    houses = [dict(x=row['x'], z=row['y'], span=row['size'], abode=row['name'], residents=residents)
              for row in abodes if row['job'] == 0]
    fields = [dict(x=row['x'], z=row['y'], span=row['size']) for row in abodes if row['job'] == 1 and row['factory'] == 1]
    if len(houses) != 4 or len(fields) != 2:
        raise ValueError('Unexpected Homeworld6 Astari abodes')
    reaction_table = rows(files, 'balance/reactions.csv')
    reaction, = [dict(zip(reaction_table[0], row)) for row in reaction_table[1:] if row[:1] == ['AstariFestival']]
    if reaction['AgressiveAction0'] != 'FountainCelebrate' or reaction['TeleportFollowers'] != '0':
        raise ValueError('Unexpected festival reaction')
    festival = lua.split('function playAstariFestival', 1)[1].split('function onEventFestivalStarted', 1)[0]
    if 'CreateReaction("AstariFestival", ASTARI_STATUE.x, ASTARI_STATUE.y, 1)' not in festival:
        raise ValueError('Missing original festival reaction position')
    positions = re.findall(r'ASTARI_STATUE\s*=\s*\{\["x"\]\s*=\s*(\d+),\s*\["y"\]\s*=\s*(\d+)\}', lua)
    statue, = [list(map(int, position)) for position in positions]
    center = [struct.unpack('<f', image.read(address, 4))[0] for address in (0x1056be44, 0x1056be48)]
    unlocks = rows(files, f'{scope}/unlocks.csv')
    unlock, = [row for row in unlocks if row[:1] == ['AstariFestivalsUnlock']]
    if unlock[1] != 'Card_Adv_Fountain_COMPLETED':
        raise ValueError('Unexpected festival availability')
    if image.read(0x1008013e, 6) != bytes.fromhex('dc0d300c4a10') or image.read(0x1007f6e0, 3) != bytes.fromhex('558bec'):
        raise ValueError('Unexpected native festival conversion')

    catalog = {model['id']: model for model in json.loads(Path(models).read_text())['models']}
    mask = f'follower.group.bin:{iw_hash("male_AstariMask"):08x}'
    bodies = [f'follower.group.bin:{iw_hash(name):08x}' for name in ('male_LOD1', 'female_LOD1')]
    clips = dict(idle='default_stand_1', walking='default_walk_1', dance1='dance_wallflower_1',
                 dance2='dance_wallflower_2', dance3='dance_wallflower_3')
    for body in bodies:
        names = {clip['name'] for clip in catalog[body]['motion']['clips']}
        for name in clips.values():
            if name not in names:
                raise ValueError(f'Missing original festival clip: {name}')
    action_table = rows(files, 'balance/actionstates.csv')
    idle, = [dict(zip(action_table[0], row)) for row in action_table[1:] if row[:3] == ['FountainCelebrate', '2', 'Idle']]
    dance, = [dict(zip(action_table[0], row)) for row in action_table[1:] if row[:3] == ['FountainCelebrate', '3', 'Dance']]
    localization = {row[0]: row[1] for row in rows(files, 'gui/localization.csv') if len(row) > 1}
    notices = {'start':text('LOC_FOLLOWER_ASTARI_FESTIVAL', localization)}
    for kind, number in [('lost', '01'), ('won', '02')]:
        prefix = text(f'LOC_AstTUT_{number}_01', localization)
        for case in ('SINGULAR', 'PLURAL'):
            suffix = text(f'LOC_AstTUT_{number}_02_{case}', localization)
            notices[kind+'_'+case.lower()] = prefix + ' %d ' + suffix
    races = rows(files, 'balance/race.csv')
    base = dict(zip(races[0], next(row for row in races if row[:1] == ['Base'])))
    astari = dict(zip(races[0], next(row for row in races if row[:1] == ['AstariRace'])))
    actor_stats = {key: float(base[key])*float(astari[key]) for key in ('MaxHealth','RouteSpeed','Scale','AnimSpeedMult')}
    rules.update(
        village=dict(x=village['x'], z=village['y'], width=width, depth=depth, levels=levels, title=text(create[6], localization),
                     residents=int(rules['population'])-sum(home['residents'] for home in houses), job=job, ai_delay=delay),
        houses=houses, fields=fields, conversion_center=center, festival_center=statue,
        unlock=unlock[0], conversion_scale=struct.unpack('<d', image.read(0x104a0c30, 8))[0],
        reaction=dict(radius=float(reaction['Radius']), spacing=float(reaction['SpacingDistance']),
                      limit=int(reaction['MaxFollowers']), initial_slots=2**int(reaction['FirstRingPower2Slots']),
                      resolve_radius=float(reaction['ResolveRadiusAddition']),
                      idle=[float(idle['UpdateP1']),float(idle['UpdateP2'])],
                      dance=[float(dance['UpdateP1']),float(dance['UpdateP2'])], skip=float(dance['SkipProbability'])),
        notices=notices, mask=mask, bodies=bodies, clips=clips, actor_stats=actor_stats)
    inputs = (script_path, f'{scope}/unlocks.csv', 'config.csv', 'balance/config.csv', 'balance/housevalues.csv',
              'balance/reactions.csv', 'balance/actionstates.csv', 'balance/race.csv', 'gui/localization.csv')
    result = dict(rules=rules, source_sha256=hashlib.sha256(archive).hexdigest(),
                  executable_sha256=hashlib.sha256(executable).hexdigest(),
                  tables_sha256={key: hashlib.sha256(files[key]).hexdigest() for key in inputs},
                  model_sha256=catalog[mask]['source_sha256'],
                  native_configuration={name: native[name] for name in parameters.values()},
                  native_routines=dict(settlement='0x10123c60', festival='0x1007fcf0', adjustment='0x100f6d76',
                                       decay='0x100f3c90', win='0x1007dce0', loss='0x1007de90', capture='0x1007f6e0'))
    Path(output).write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    assets = ROOT / 'game/assets/original'
    data = extract(ROOT / 'data/godus2_4', assets / 'models/catalog.json', assets / 'campaign/astari-village.json')
    print('Homeworld6 original Astari village:', int(data['rules']['population']), 'residents')
