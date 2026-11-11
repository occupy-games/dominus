"""Recover Homeworld6 raid scheduling and archer rules from the desktop release."""
import hashlib
import json
import re
import struct
from pathlib import Path

from tools.current_cards import decode_archive, rows, text
from tools.native_config import recover
from tools.native_scenery_oracle import ROOT, NativeImage
from tools.original_assets import iw_hash


def extract(source, models, output):
    source = Path(source)
    executable = (source / 'godus.s86').read_bytes()
    archive = (source / 'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    image = NativeImage(executable)
    scope = 'initialworldsetup6/scripts.lua'
    lua = files[scope].decode('utf-8-sig', errors='replace')
    common = files['scripts.lua'].decode('utf-8-sig', errors='replace')
    interval, precision = map(int, re.search(r'beginAstariRaids\((\d+),(\d+)\)', lua).groups())
    festival_delay = int(re.search(r"After\((\d+),'sendAstariRaid'\)", lua)[1])
    search_radius = int(re.search(r'local searchRad = (\d+)', common)[1])
    search_limit = int(re.search(r'while searchRad < (\d+) do', common)[1])
    search_factor = int(re.search(r'searchRad = searchRad \* (\d+)', common)[1])
    radii = []
    while search_radius < search_limit:
        radii.append(search_radius)
        search_radius *= search_factor
    homeworld, = re.findall(r'GetHomeworldId\(\) == 0 then\s+x0\s*= Persist\("AstariAttackFromX"\)\s+y0\s*= Persist\("AstariAttackFromY"\)\s+z0 = (\d+)', common)
    tip_step, tip_height, tip = re.search(r'TriggerTip3D\(x1, y1, (\d+)\*(\.\d+),\s*"(LOC_\w+)", 0\)', common).groups()
    alert, duration = re.search(r'RaidAlert = TriggerAlert\("(LOC_\w+)",false,(\d+)\)', common).groups()
    if 'Persist(persistName, interval+1)' not in common or 'After(precision, tickAstariRaids)\n\tsendAstariRaid()' not in common:
        raise ValueError('Unexpected native raid timer')
    beacons = dict(re.findall(r'^\s*(EXPANSION_\d+_ID) = (\d+)', lua, re.M))
    taunts = {name: [int(x), int(z)] for name, x, z in re.findall(r'(TAUNT_LOC_\d+) = \{x = (\d+), y = (\d+)\}', lua)}
    origins = {beacons[beacon]: taunts[taunt] for beacon, taunt in re.findall(
        r'TempleUID\(context\) == (EXPANSION_\d+_ID) then(?:(?!elseif)[\s\S])*?Persist\("AstariAttackFromX",(TAUNT_LOC_\d+)\.x\)', lua)}
    if len(origins) != 8:
        raise ValueError('Missing authored raid origin')

    races = rows(files, 'balance/race.csv')
    jobs = rows(files, 'balance/jobs.csv')
    base = dict(zip(races[0], next(row for row in races if row[:1] == ['Base'])))
    astari = dict(zip(races[0], next(row for row in races if row[:1] == ['AstariRace'])))
    archer = dict(zip(jobs[0], next(row for row in jobs if row[:1] == ['LOC_JOB_ARCHER'])))
    stats = {key: float(base[key]) * float(astari[key]) for key in (
        'MaxHealth', 'RouteSpeed', 'Vision', 'Strength', 'JobSkill', 'AnimSpeedMult', 'Scale', 'StepHeightDistanceMult')}
    if races[2:][4][0] != astari['Name'] or jobs[1:][9][0] != archer['Name']:
        raise ValueError('Unexpected Astari race or archer job index')
    parameters = {
        'follower_limit': 'ArcherMaxFollowerAttack',
        'follower_priority': 'ArcherFollowerTargetPri',
        'damage': 'ArcherDamageStrengthMult',
        'damage_min': 'ArcherDamageRandMinMult',
        'damage_max': 'ArcherDamageRandMaxMult',
        'max_steps': 'FollowerMaxStepsPerUnit',
        'nav_range': 'NavAgentFollowerMaxDist',
    }
    native = recover(executable, ['archer', 'followermaxstepsperunit', 'navagentfollowermaxdist'])
    configuration = {row[0]: row[1] for name in ('config.csv', 'balance/config.csv')
                     for row in rows(files, name) if len(row) > 1 and row[1]}
    rules = {key: float(configuration.get(name, native[name]['value'])) for key, name in parameters.items()}

    actions = rows(files, 'balance/actionstates.csv')
    attack = [dict(zip(actions[0], row)) for row in actions[1:] if row[:1] == ['AttackTarget']]
    scout = [dict(zip(actions[0], row)) for row in actions[1:] if row[:1] == ['ScoutLocation']]
    if [row['Name'] for row in attack] != ['Move', 'ReadyStart', 'ReadyEnd', 'Aim', 'Fire', 'Reload', 'End']:
        raise ValueError('Unexpected AttackTarget states')
    death, = [dict(zip(actions[0], row)) for row in actions[1:] if row[:2] == ['Die', '0']]
    group = 'follower.group.bin'
    def model_id(name):
        return f'{group}:{iw_hash(name):08x}'

    roster = [model_id(name) for name in ('male_LOD1', 'female_LOD1')]
    parts = {name: model_id(name) for name in ('male_AstariMask', 'bow', 'bow_pull', 'arrow', 'arrow_front', 'arrow_rear')}
    catalog = {record['id']: record for record in json.loads(Path(models).read_text())['models']}
    clips = {clip['name']: clip['duration'] for clip in catalog[roster[0]]['motion']['clips']}
    enemy_clips = dict(idle='default_stand_1', walking='default_walk_1')
    shot_durations = {}
    attachments = {key: [] for key in ['bow', 'bow_pull', 'arrow']}
    for index, row in enumerate(attack[1:], 1):
        for distance, slot in [('near', 'Anim (0/left/low)'), ('far', 'Anim (1/right/med)')]:
            clip = 'archer_' + row[slot].lower()
            role = distance + '_' + str(index)
            enemy_clips[role] = clip
            shot_durations[role] = clips[clip]
            if row['Attach'] == 'Bow':
                attachments['bow'].append(role)
            if row['Attach'] == 'BowPull':
                attachments['bow_pull'].append(role)
            if row['AttachArcher'] == 'Arrow':
                attachments['arrow'].append(role)
    if attack[4]['TriggerAction'] != 'FiredArrow' or attack[5]['NextState'] != '3':
        raise ValueError('Unexpected arrow trigger or reload branch')
    for body in roster:
        names = {clip['name'] for clip in catalog[body]['motion']['clips']}
        if not names.issuperset(enemy_clips.values()):
            raise ValueError('Missing source Astari animation')
    localization = {row[0]: row[1] for row in rows(files, 'gui/localization.csv') if len(row) > 1}
    hit_reactions = {'front': [], 'rear': []}
    for side in hit_reactions:
        name = 'TakeArrowHit' + side.title()
        for row in actions[1:]:
            if row[:1] == [name]:
                hit_reactions[side].append('default_' + dict(zip(actions[0], row))['Anim (0/left/low)'].lower())
        hit_reactions[side].append('default_stand_die_arrow_' + side)
    if not all(clip in clips for pair in hit_reactions.values() for clip in pair):
        raise ValueError('Missing source arrow reactions')
    rules.update(interval=interval, precision=precision, festival_delay=festival_delay, radii=radii,
                 count=int(homeworld), origins=origins, tip_height=int(tip_step) * float(tip_height),
                 duration=int(duration), tip=text(tip, localization), alert=text(alert, localization),
                 random_max=int(struct.unpack('<d', image.read(0x104a0c10, 8))[0]),
                 spread=struct.unpack('<d', image.read(0x104a0d00, 8))[0],
                 flight_per_unit=struct.unpack('<d', image.read(0x104b3688, 8))[0],
                 follower_radius=struct.unpack('<f', image.read(0x1056b73c, 4))[0] * 0.5,
                 near_distance=struct.unpack('<f', image.read(0x104a0c5c, 4))[0],
                 stats=stats, vision_multiplier=float(archer['VisionMult']), speed_multiplier=float(archer['RouteSpeedMult']),
                 roster=roster, parts=parts, clips=enemy_clips, attachments=attachments, shot_durations=shot_durations,
                 fire_progress=float(attack[4]['TriggerProgress']), aim_time=[float(attack[3]['UpdateP1']), float(attack[3]['UpdateP2'])],
                 advance_range=[float(attack[0]['UpdateP1']), float(attack[0]['UpdateP2'])],
                 scout_range=[float(scout[0]['UpdateP1']), float(scout[0]['UpdateP2'])],
                 scout_wait=[float(scout[1]['UpdateP1']), float(scout[1]['UpdateP2'])],
                 death_time=float(death['UpdateP1']), hit_reactions=hit_reactions,
                 hit_durations={clip: clips[clip] for pair in hit_reactions.values() for clip in pair})
    inputs = ('scripts.lua', scope, 'balance/race.csv', 'balance/jobs.csv', 'balance/actions.csv',
              'balance/actionstates.csv', 'config.csv', 'balance/config.csv', 'gui/localization.csv')
    result = dict(rules=rules, source_sha256=hashlib.sha256(archive).hexdigest(),
                  executable_sha256=hashlib.sha256(executable).hexdigest(),
                  model_sha256=hashlib.sha256((source / group).read_bytes()).hexdigest(),
                  tables_sha256={name: hashlib.sha256(files[name]).hexdigest() for name in inputs},
                  native_configuration={name: native[name] for name in parameters.values()},
                  native_routines=dict(lua='0x1023dde0', spawn='0x1007d3f0', archer='0x100cc3f0',
                                       score='0x100ca310', pose='0x100023ca', fire='0x1000396d',
                                       resolve='0x100f9160', flight='0x100f9430'))
    Path(output).write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    assets = ROOT / 'game/assets/original'
    data = extract(ROOT / 'data/godus2_4', assets / 'models/catalog.json', assets / 'campaign/astari-raids.json')
    print('Homeworld6 Astari raids:', len(data['rules']['origins']), 'beacon origins')
