"""Recover authored campaign starts and tutorial programs from supplied Lua.

Expressions are parsed to inert data. No source code is evaluated or executed.
The retained function bodies are consumed by the bounded simulation interpreter.
"""
import hashlib
import json
from pathlib import Path
import re
import struct

from tools.current_cards import decode_archive, rows, text
from tools.campaign import packed_map
from tools.voyage_lua import Compiler, CompileError
from tools.day_cycle import extract as day_cycle
from tools.map_objects import authored_rocks
from tools.abode_clumps import extract as clump_rules
from tools.native_scenery_oracle import NativeImage
from tools.meteor import extract as meteor_rules
from tools.original_assets import FOLLOWER_CLIPS, decode_animation, decode_skeleton, iw_hash, resource_group

ROOT = Path(__file__).resolve().parents[1]


def assignment(compiler, name, initial=False):
    tokens = name.split('.')
    pattern = []
    for token in tokens:
        if pattern: pattern.append('.')
        pattern.append(token)
    pattern.append('=')
    matches = [i for i in range(len(compiler.tokens)-len(pattern))
               if compiler.tokens[i:i+len(pattern)] == pattern]
    if not matches or (len(matches) != 1 and not initial): raise CompileError(f'Ambiguous authored assignment: {name}')
    compiler.cursor = matches[0] + len(pattern)
    return compiler.expression()


def literal(node, values):
    kind = node[0]
    if kind == 'literal': return node[1]
    if kind == 'var': return values.get(node[1], {'symbol': node[1]})
    if kind == 'function': return {'function': node[1], 'scope': {}}
    if kind == 'table': return {literal(key, values): literal(value, values) for key, value in node[1]}
    if kind == 'index': return literal(node[1], values)[literal(node[2], values)]
    if kind == 'unary' and node[1] == '-': return -literal(node[2], values)
    if kind == 'binary':
        a, b = literal(node[2], values), literal(node[3], values)
        if not isinstance(a, (float, int)) or not isinstance(b, (float, int)): raise CompileError('Non-numeric source constant')
        if node[1] == '+': return a+b
        if node[1] == '-': return a-b
        if node[1] == '*': return a*b
        if node[1] == '/': return a/b
    raise CompileError(f'Unsupported constant expression: {node}')


def named_function(compiler, name, initial=False):
    pattern = ['function', name, '(']
    matches = [i for i in range(len(compiler.tokens)-3) if compiler.tokens[i:i+3] == pattern]
    if not matches or (len(matches) != 1 and not initial): raise CompileError(f'Ambiguous authored function: {name}')
    compiler.cursor = matches[0]+2
    return compiler.function()


def nested_arrays(value):
    if isinstance(value,list):
        yield value
        for item in value: yield from nested_arrays(item)


def ark_progression(files, parser, localization):
    path = 'initialworldsetup6/scripts.lua'
    source = files[path].decode('utf-8-sig').split('--ARK TUTORIAL', 1)[1].split('--UPDATE 3 TUTORIAL', 1)[0]

    def unique(pattern):
        matches = re.findall(pattern, source)
        if len(matches)!=1: raise CompileError('Ambiguous source Ark rule: '+pattern)
        return matches[0]

    def coordinate(name):
        value = literal(assignment(parser,name),{})
        return [int(value[1]),int(value[2])]

    astari = list(map(int,unique(r'ProcessFollowersInRadius\((\d+),(\d+), (\d+), "tryConquerAstari"\)')))
    lead = int(unique(r'BEACON_BEFORE_ARK_BEACON_POS\[1\]\+(\d+), BEACON_BEFORE_ARK_BEACON_POS\[2\]'))
    scan = int(unique(r'After\((\d+), function\(\) currentTutorialStep\("Ark"\).checkIfFollowerInAstariConquerRange'))
    half = int(unique(r'After\((\d+), ClearUI, "Ark", 3\)'))
    poll = int(unique(r'NonPausingAfter\((\d+), fnTryShowTipAndAdvance\)'))
    if not re.search(r'if FollowerAllegiance\(context\) == 0 and FollowerJob\(context\) == JOB_BUILDER then',source):
        raise CompileError('Unexpected Astari conquest follower condition')
    festival = {name:int(value) for name,value in re.findall(r'Config\("([^"]+)",\s*(-?\d+)\)',source)}
    if festival.get('TriggerFestival')!=1 or festival.get('MaxFollowersToConvertPostFestival')!=1000:
        raise CompileError('Unexpected forced Astari festival')
    result = {'site_id':str(literal(assignment(parser,'ARK_ID'),{})), 'position':coordinate('ARK_POS'),
              'beacon':coordinate('ARK_BEACON_POS'), 'approach':coordinate('BEACON_BEFORE_ARK_BEACON_POS'),
              'approach_offset':lead, 'astari':astari, 'scan_seconds':scan, 'halfway_hint_seconds':half,
              'halfway_poll_seconds':poll, 'festival':festival, 'card':unique(r'GiveCard\("(Card_AstariConquered)"\)')}
    result['sail_labels'] = {key:text(source_key,localization) for key,source_key in {
        'button':'LOC_BUTTON_ARK_SAIL', 'title':'LOC_ARK_SAIL_TITLE', 'full':'LOC_F_ARK_SAIL_BLURB_FULL',
        'spaces_before':'LOC_F_ARK_SAIL_BLURB_INCOMPLETEA', 'spaces_after':'LOC_F_ARK_SAIL_BLURB_INCOMPLETEB'}.items()}
    messages = {}
    for index,(kind,key) in enumerate(re.findall(r'\{strType="([^"]+)"[^}]*?msg="([^"]+)"',source),1):
        messages[str(5700+index)] = {'group':'Ark','source_id':index,'strType':kind,'key':key,'text':text(key,localization)}
    if len(messages)!=8: raise CompileError('Unexpected Ark tutorial messages')
    return result,messages


def belief_advances(files, image, levels, unlocks, powers, config, localization):
    modifier_path = 'balance/balanceunlockmodifier.csv'
    modifiers = [(r[0],[field.strip() for field in r[1].split(',')])
                 for r in rows(files,modifier_path)[1:] if len(r)>1 and r[1]]
    population = {row[1]:int(row[0]) for row in levels if row[0].isdigit()}
    rock_card = 'Card_RockBelief_1'
    rock_unlock = rock_card.removeprefix('Card_')
    if not any(row[:2]==[rock_unlock,rock_card+'_COMPLETED'] for row in unlocks):
        raise CompileError('Missing the original rock belief unlock')
    value_path = 'assets/map_object_values.csv'
    object_values = rows(files,value_path)
    column = object_values[0].index('belief')
    rock_modifiers = {}
    rock_amounts = {}
    for unlock, operation in modifiers:
        if unlock!=rock_unlock: continue
        if operation[:3]!=['Table','Map Object Values','belief'] or not operation[4].startswith('m'):
            raise CompileError('Unexpected rock belief modifier')
        row = object_values[int(operation[3])]
        rock_modifiers[row[0]] = float(operation[4][1:])
        rock_amounts[row[0]] = int(row[column])
    if set(rock_modifiers)!={str(kind) for kind in range(20,27)}:
        raise CompileError('Missing original rock type multipliers')
    collector_card = 'Card_Adv_BeliefCollection'
    collector_power = next(row for row in powers if row[0]=='GodPower_PlaceBeliefCollect')
    if collector_power[2:6]!=['PLACEBUILDING','1','STATUE','Monument_BeliefCollect'] or not any(
            row[:2]==[collector_power[0],collector_card+'_COMPLETED'] for row in unlocks):
        raise CompileError('Missing the original collection shrine power')
    temple_types = rows(files,'balance/templetypes.csv')
    temples = [r for r in temple_types[1:] if r[0] and not r[0].startswith('#')]
    temple_index, temple = next((i,r) for i,r in enumerate(temples,1) if r[0]==collector_power[5])
    shape = next(r for r in rows(files,'balance/templegenerictypes.csv') if r[0]==temple[1])
    native = {0x10047629:'d90520f95910',0x1013f1e5:'d9052c4c5d10',0x1013f21a:'d94010',
              0x1013f341:'d905584c5d10',0x100b9fdf:'83beec000000ff',0x1003cff1:'d84d24',
              0x101563bd:'d9804cbcfc10'}
    for address, opcode in native.items():
        expected = bytes.fromhex(opcode)
        if image.read(address,len(expected))!=expected:
            raise CompileError(f'Unexpected belief instruction at {address:#x}')
    def constant(key, address):
        default, = struct.unpack('<f',image.read(address,4))
        return config.get(key,default)
    upgrades = []
    strings = rows(files,'gui/localization.csv')
    for row in rows(files,'gui/powerupgradedata.csv'):
        if row[0]!='Card_Monument_BeliefCollect': continue
        if row[2:3]!=['AlwaysUnlocked'] or row[4:6]!=['GEMS','UPGRADE']:
            raise CompileError('Unexpected collection shrine upgrade currency')
        lock = next(r[0] for r in unlocks if r[1]==row[1])
        changes = [effect for unlock,effect in modifiers if unlock==lock]
        radius = next(op for op in changes if op[:3]==['Table','Temple Types','radius outside settlement'])
        amount = next(op for op in changes if op[:2]==['Config','Monument_BeliefCollect_CollectMultiplier'])
        if int(radius[3])!=temple_index or not radius[4].startswith('m'):
            raise CompileError('Collection shrine upgrade points at another temple')
        radius_factor, multiplier = float(radius[4][1:]), float(amount[2])
        percent = f'+{round((radius_factor-1)*100)}%'
        description = next(r[1] for r in strings if r[0]==row[8] and percent in r[1])
        upgrades.append({'id':row[1],'radius':float(temple[3])*radius_factor,'multiplier':multiplier,
                         'cost':int(row[3]),'currency':row[4].lower(),
                         'button':text(row[6],localization),'title':text(row[7],localization),
                         'description':text(description,localization)})
    rock = {'card':rock_card,'population':population[rock_card],'unlock':rock_unlock,'amounts':rock_amounts,
            'multipliers':rock_modifiers,'default_amount':int(constant('beliefPerRock',0x105d9214))}
    collector = {'card':collector_card,'population':population[collector_card],'power':collector_power[0],
                 'temple_type':temple[0],'model':shape[3]+'.group.bin:%08x'%iw_hash('rank1_loc1_var1_storey1'),
                 'width':int(shape[1]),'depth':int(shape[2]),'radius':float(temple[3]),
                 'prices':[int(price) for price in collector_power[10:16] if price],
                 'interval':constant('BeliefCollectTempleUpdateTime',0x1059f920),
                 'wait':constant('TempleBeliefCollectWait',0x105d4c2c),
                 'multiplier':constant('Monument_BeliefCollect_CollectMultiplier',0x105d4c58),
                 'title_key':temple[7],'description_key':temple[11],
                 'upgrades':upgrades,'native_instructions':list(native)}
    return rock,collector,[modifier_path,value_path]


def capacity_shrine(files, parser, values, localization, source):
    power_path = 'initialworldsetup/powerdata.csv'
    scope = 'initialworldsetup6'
    power = next(row for row in rows(files, power_path) if row[0] == 'GodPower_PlaceCapacity')
    card = 'Card_Capacity_1'
    level = next(row for row in rows(files, f'{scope}/populationlevels.csv') if row[1] == card)
    unlocks = rows(files, f'{scope}/unlocks.csv')
    if power[2:6] != ['PLACEBUILDING', '1', 'STATUE', 'Monument_Family'] or power[8] != 'INSTANT' or not any(
            row[:2] == [power[0], card + '_COMPLETED'] for row in unlocks):
        raise CompileError('Unexpected Shrine of Capacity power')
    type_path = 'balance/templetypes.csv'
    types = [row for row in rows(files, type_path)[1:] if row[0] and not row[0].startswith('#')]
    temple_index, temple = next((i, row) for i, row in enumerate(types, 1) if row[0] == power[5])
    shape_path = 'balance/templegenerictypes.csv'
    shape = next(row for row in rows(files, shape_path) if row[0] == temple[1])
    model_group = shape[3] + '.group.bin'
    effects_path = 'balance/templeupgrades.csv'
    effects = [row for row in rows(files, effects_path)[1:] if row[0] and not row[0].startswith('#')]
    family = {i: row for i, row in enumerate(effects, 1) if row[0] == temple[0]}
    if len(family) != 2 or any(row[1] != 'AlwaysUnlocked' or row[4:6] != ['0', '0'] for row in family.values()):
        raise CompileError('Unexpected Shrine of Capacity effects')
    bonuses = {}
    for index, row in family.items():
        prefix = 'table,House Values,Capacity, +'
        if not row[2].startswith(prefix):
            raise CompileError('Unexpected Shrine of Capacity stat')
        bonuses[index] = int(row[2].removeprefix(prefix))
    modifier_path = 'balance/balanceunlockmodifier.csv'
    modifiers = [(row[0], [part.strip() for part in row[1].split(',')])
                 for row in rows(files, modifier_path)[1:] if len(row) > 1 and row[1]]
    upgrade_path = 'gui/powerupgradedata.csv'
    base_radius = float(temple[3])
    base_flags = {i: int(row[3]) for i, row in family.items()}
    bonus = sum(bonuses[i] for i in base_flags if base_flags[i])
    upgrades = []
    for row in rows(files, upgrade_path)[1:]:
        if row[0] != 'Card_Monument_Capacity':
            continue
        if row[2] != 'AlwaysUnlocked' or row[4] not in ('WHEAT', 'GEMS') or row[5] != 'UPGRADE':
            raise CompileError('Unexpected Shrine of Capacity upgrade')
        unlock = next(item[0] for item in unlocks if item[1] == row[1])
        radius = base_radius
        abode_flags = base_flags.copy()
        for condition, operation in modifiers:
            if condition != unlock:
                continue
            if operation[:3] == ['Table', 'Temple Types', 'radius outside settlement']:
                if int(operation[3]) != temple_index or not operation[4].startswith('m'):
                    raise CompileError('Capacity radius upgrade points at another temple')
                radius *= float(operation[4][1:])
            elif operation[:3] == ['Table', 'Temple Upgrades', 'abode']:
                index = int(operation[3])
                if index not in abode_flags:
                    raise CompileError('Capacity stat upgrade points at another temple')
                abode_flags[index] = int(operation[4])
        upgrade = {'id': row[1], 'cost': int(row[3]), 'currency': row[4].lower(),
                   'button': text(row[6], localization), 'title': text(row[7], localization),
                   'description': text(row[8], localization)}
        if radius != base_radius:
            upgrade['radius'] = radius
        if abode_flags != base_flags:
            upgrade['bonus'] = sum(bonuses[i] for i in abode_flags if abode_flags[i])
        upgrades.append(upgrade)
    if len(upgrades) != 2:
        raise CompileError('Missing Shrine of Capacity upgrades')
    messages = {}
    for index, entry in assignment(parser, 'uiTable.Monuments')[1]:
        source_id = literal(index, values)
        item = {'group': 'Monuments', 'source_id': source_id}
        for key, value in entry[1]:
            if key[1] in ('strType', 'pos2d'):
                item[key[1]] = literal(value, values)
            elif key[1] == 'msg':
                name = literal(value, values)
                item.update(key=name, text=text(name, localization))
        messages[str(6000 + source_id)] = item
    return ({'card': card, 'population': int(level[0]), 'power': power[0], 'temple_type': temple[0],
             'model': model_group + ':%08x' % iw_hash('rank1_loc1_var1_storey1'),
             'model_sha256': hashlib.sha256((source / model_group).read_bytes()).hexdigest(),
             'width': int(shape[1]), 'depth': int(shape[2]), 'radius': base_radius, 'bonus': bonus,
             'prices': [int(price) for price in power[10:16] if price], 'upgrades': upgrades,
             'title_key': temple[8], 'description_key': temple[11]},
            messages, [type_path, shape_path, effects_path, modifier_path, upgrade_path])


def speed_shrine(files, tables, power_path, localization, source):
    card = 'Card_Speed_1'
    level = next(row for row in tables['initialworldsetup6/grainlevels.csv'] if row[1] == card)
    unlocks = tables['initialworldsetup6/unlocks.csv']
    power = next(row for row in rows(files, power_path) if row[0] == 'GodPower_PlaceSpeed')
    if power[2:6] != ['PLACEBUILDING', '1', 'STATUE', 'Monument_Speed'] or power[8] != 'INSTANT' or not any(
            row[:2] == [power[0], card + '_COMPLETED'] for row in unlocks):
        raise CompileError('Unexpected Shrine of Speed unlock or placement')
    type_path = 'balance/templetypes.csv'
    types = [row for row in rows(files, type_path)[1:] if row[0] and not row[0].startswith('#')]
    temple_index, temple = next((i, row) for i, row in enumerate(types, 1) if row[0] == power[5])
    shape_path = 'balance/templegenerictypes.csv'
    shape = next(row for row in rows(files, shape_path) if row[0] == temple[1])
    model_group = shape[3] + '.group.bin'
    effect_path = 'balance/templeupgrades.csv'
    effects = []
    for row in rows(files, effect_path)[1:]:
        if row[0] != temple[0]:
            continue
        table, family, stat, multiplier = [part.strip() for part in row[2].split(',')]
        if (table, family, stat) != ('table', 'race', 'RouteSpeed') or not multiplier.startswith('m'):
            raise CompileError('Unexpected Shrine of Speed stat effect')
        effects.append({'unlock': row[1], 'multiplier': float(multiplier[1:])})
    modifier_path = 'balance/balanceunlockmodifier.csv'
    upgrade_path = 'gui/powerupgradedata.csv'
    modifiers = rows(files, modifier_path)
    base_radius = float(temple[3])
    upgrades = []
    for row in rows(files, upgrade_path)[1:]:
        if row[0] != 'Card_Monument_Speed':
            continue
        if row[2] != 'AlwaysUnlocked' or row[4] not in ('WHEAT', 'ORE') or row[5] != 'UPGRADE':
            raise CompileError('Unexpected Shrine of Speed upgrade')
        unlock = next(entry[0] for entry in unlocks if entry[1] == row[1])
        upgrade = {'id': row[1], 'unlock': unlock, 'cost': int(row[3]), 'currency': row[4].lower(),
                   'button': text(row[6], localization), 'title': text(row[7], localization),
                   'description': text(row[8], localization)}
        for modifier in modifiers:
            if modifier[0] != unlock:
                continue
            operation = [part.strip() for part in modifier[1].split(',')]
            if operation[:4] != ['Table', 'Temple Types', 'radius outside settlement', str(temple_index)] or not operation[4].startswith('m'):
                raise CompileError('Unexpected Shrine of Speed radius modifier')
            upgrade['radius'] = base_radius * float(operation[4][1:])
        upgrades.append(upgrade)
    if len(effects) != 2 or len(upgrades) != 2:
        raise CompileError('Incomplete Shrine of Speed effects or upgrades')
    authored = [row[8] for row in tables['initialworldsetup6/templepositions.csv'] if row[0] == temple[0]]
    return {'card': card, 'fields': int(level[0]), 'power': power[0], 'temple_type': temple[0],
            'model': model_group + ':%08x' % iw_hash('rank1_loc1_var1_storey1'),
            'model_sha256': hashlib.sha256((source / model_group).read_bytes()).hexdigest(),
            'width': int(shape[1]), 'depth': int(shape[2]), 'radius': base_radius,
            'prices': [int(price) for price in power[10:16] if price], 'effects': effects,
            'upgrades': upgrades, 'authored_sites': authored, 'title_key': temple[7], 'description_key': temple[11]}, [
                type_path, shape_path, effect_path, modifier_path, upgrade_path]


def settlement_upgrades(files, unlocks, config, localization):
    """Recover the three Homeworld settlement upgrade sequences and their effects."""
    upgrade_path = 'gui/powerupgradedata.csv'
    modifier_path = 'balance/balanceunlockmodifier.csv'
    upgrade_rows = rows(files, upgrade_path)
    modifiers = [(row[0], [part.strip() for part in row[1].split(',')])
                 for row in rows(files, modifier_path) if len(row) > 1 and row[1]]
    result = {}
    for number, role, radius_slot in [(1, 'Builder', 2), (2, 'Farmer', 1), (3, 'Miner', 3)]:
        radius_key = f'SettCompRadius{radius_slot}'
        population_key = f'Settlement{role}MaxPop'
        base_population = int(config[population_key])
        population = base_population
        workers = None
        base_workers = None
        offers = []
        card = f'Card_GodPower_Settlement_{number}'
        for rank, row in enumerate((row for row in upgrade_rows if row and row[0] == card), 2):
            if row[2] != 'AlwaysUnlocked' or row[4] not in ('GEMS', 'WHEAT', 'ORE') or row[5] != 'UPGRADE':
                raise CompileError('Unexpected settlement upgrade')
            keys = [entry[0] for entry in unlocks if entry[1] == row[1]]
            if len(keys) != 1:
                raise CompileError('Missing settlement upgrade unlock')
            unlock = keys[0]
            effects = {parts[1]: int(parts[2][1:]) for key, parts in modifiers
                       if key == unlock and len(parts) == 3 and parts[0] == 'Config' and parts[2].startswith('p')}
            if set(effects) != {radius_key, population_key}:
                raise CompileError('Missing settlement population or compression radius modifier')
            population += effects[population_key]
            if population != int(config[f'{population_key}_Lv{rank}']):
                raise CompileError('Settlement upgrade disagrees with original population limit')
            description = text(row[8], localization).replace('\\n', '\n')
            limit = re.search(rf'Max {role}s:\s*(\d+)(?:\(\+(\d+)\))?', description)
            if limit is None or (workers is None and limit[2] is None):
                raise CompileError('Missing original worker limit')
            worker_limit = int(limit[1])
            if workers is None:
                workers = base_workers = worker_limit - int(limit[2])
            if worker_limit <= workers or (limit[2] is not None and worker_limit - workers != int(limit[2])):
                raise CompileError('Unexpected settlement worker increment')
            offers.append({'id': row[1], 'unlock': unlock, 'cost': int(row[3]), 'currency': row[4].lower(),
                           'button': text(row[6], localization), 'title': text(row[7], localization),
                           'description': description, 'radius': effects[radius_key],
                           'population': effects[population_key], 'workers': worker_limit - workers})
            workers = worker_limit
        if len(offers) != 4 or base_workers is None or base_workers < 1:
            raise CompileError('Incomplete settlement upgrade sequence')
        result[f'GodPower_PlaceSettlement_{number}'] = {
            'radius': int(config[radius_key]), 'population': base_population, 'workers': base_workers, 'upgrades': offers}
    return result, [upgrade_path, modifier_path]


def extract(source=ROOT/'data/godus2_4', output=ROOT/'game/assets/original/campaign'):
    archive = source/'received/godussteamrel/balance.datz'
    files = decode_archive(archive.read_bytes())
    global_parser = Compiler(files['scripts.lua'].decode('utf-8-sig'))
    local_parser = Compiler(files['initialworldsetup6/scripts.lua'].decode('utf-8-sig'))
    values = {}
    for name in ['DEFAULT_CAM_HEIGHT', 'TUTORIALGOTO_IN_TABLE', 'INITIAL_FOLLOWERS','INITIAL_LAND','CARD_TIP_POS']:
        values[name] = literal(assignment(global_parser, name), values)
    for name in ['PROMISED_LAND','PROMISED_LAND_CAM','INITIAL_ROCK','ROCKS_2','BIRD_EXPLOSIONS','FIRST_CHEST',
                 'gTrailSculptLockX0','gTrailSculptLockY0','gTrailSculptLockX1','gTrailSculptLockY1']:
        values[name] = literal(assignment(local_parser, name), values)
    route = literal(assignment(local_parser, 'BLOCKAGES'), values)
    # Verify the explicit reset and manual spawn hook instead of inventing starts
    # from a camera or influence-area position when the pack has no p1Start.
    reset = named_function(local_parser, 'onPreLoad')
    reset_body = local_parser.functions[reset[1]]['body']
    if reset_body != [['expr', ['call', ['var', 'ResetStartPositions'], []]]]:
        raise CompileError('Unexpected authored start reset')
    spawn = named_function(local_parser, 'onAllFollowersDead')
    starts = []
    for statement in local_parser.functions[spawn[1]]['body']:
        if statement[:1] != ['expr'] or statement[1][:2] != ['call',['var','SpawnFollower']]:
            raise CompileError('Unexpected authored respawn operation')
        args = [literal(arg, values) for arg in statement[1][2]]
        starts.append({'x':args[1], 'z':args[2], 'source_args':args})
    if len(starts) != 2: raise CompileError('Expected the authored pair of followers')
    ui = assignment(local_parser, 'uiTable.Trail')
    localization = {r[0]:r[1] for r in rows(files,'gui/localization.csv') if len(r)>1 and r[0].startswith('LOC_')}
    messages = {}
    for index, entry in ui[1]:
        item = {}
        for key,value in entry[1]:
            if key[0]=='literal' and key[1] in ['strType','pos2d','pos3d']:
                item[key[1]]=literal(value,dict(values,BLOCKAGES=route))
        for key, value in entry[1]:
            if key == ['literal', 'msg']:
                name = literal(value, values)
                if name not in localization: raise CompileError(f'Missing tutorial localization: {name}')
                messages[str(literal(index, values))] = dict(item,key=name,text=text(name,localization))
    messages['29'] = {'options':[{'key':f'LOC_TUT_BLOCKED_{i:03d}', 'text':text(f'LOC_TUT_BLOCKED_{i:03d}',localization)} for i in range(5)]}
    # Separate groups keep Trail 1 and PromisedLand 1 distinct in plain commands.
    promised_ui=assignment(local_parser,'uiTable.PromisedLand')
    for index,entry in promised_ui[1]:
        item={'group':'PromisedLand','source_id':literal(index,values)}
        for key,value in entry[1]:
            if key[1] in ['strType','pos2d','pos3d','object_get','pos3d_get']:
                item[key[1]]=literal(value,values)
            elif key==['literal','msg']:
                name=literal(value,values)
                if name not in localization: raise CompileError(f'Missing tutorial localization: {name}')
                item.update(key=name,text=text(name,localization))
        if 'text' in item: messages[str(1000+literal(index,values))]=item
    used = ['scripts.lua','initialworldsetup6/scripts.lua','gui/localization.csv']
    tables = {}
    for name in files:
        if name.startswith('initialworldsetup6/') and name.endswith('.csv'):
            tables[name] = rows(files,name)
            used.append(name)
    used.append('balance/reactions.csv')
    reactions = rows(files,'balance/reactions.csv')
    headers = reactions[0]
    reaction_rows = [r for r in reactions[1:] if r and not r[0].startswith('#')]
    tutorial_reaction = next(r for r in reaction_rows if r[0]=='TutorialGoTo')
    values['origGotoSpeedMult'] = float(tutorial_reaction[headers.index('AgressiveSpeedMult')])
    race = rows(files,'balance/race.csv')
    base = next(row for row in race[1:] if row[0]=='Base')
    values['base_follower_speed'] = float(base[race[0].index('RouteSpeed')])
    used.append('balance/race.csv')
    for name in ['followerOffscreenCutoff','followerOnscreenCutoff','bFollowerOffscreen',
                 'bIgnoreFollowerBlocked','bIgnoreFollowerBlocked2']:
        values[name] = literal(assignment(local_parser,name,initial=True),values)
    helpers = {name:literal(named_function(local_parser,name),values) for name in [
        'getLeadingFollowerId','TeleportFollowerToBlockageTarget','startScrollingTutorial',
        'checkOnPreTutorialFollowers','cameraEndUpdate','defaultFollowerBlockedBehaviour',
        'defaultFollowerBlockedBehaviour2','setInitialFollowersTarget','clearInitialFollowersTarget',
        'gatherInitialFollowers','triggerBirdVFX','freezeTimeOfDay','resetTimeOfDaySpeed','getFirstRock','gotoRock',
        'getFirstPlotPosition','getFirstAbode','getSecondRock','getSecondAbode','getFirstBuilder','countAbodes',
        'getSproggableAbode','countPlots','countBuilders']}
    trail = assignment(local_parser,'tutorialTable.Trail')
    searching = next(entry for index,entry in trail[1] if index==['literal',2])
    trail_hooks = {key[1]:literal(value,values) for key,value in searching[1]
                   if key[1] in ['onListening','onFollowerBlocked','onSculptComplete']}
    waiting = next(entry for index,entry in trail[1] if index==['literal',3])
    waiting_hooks = {key[1]:literal(value,values) for key,value in waiting[1] if value[0]=='function'}
    arrival = next(entry for index,entry in trail[1] if index==['literal',4])
    arrival_hooks = {key[1]:literal(value,values) for key,value in arrival[1] if value[0]=='function'}
    promised=assignment(local_parser,'tutorialTable.PromisedLand')
    promised_steps=[]
    for index,entry in promised[1]:
        name=next(literal(value,values) for key,value in entry[1] if key==['literal','name'])
        promised_steps.append({'index':literal(index,values)-1,'name':name,
                               'hooks':{key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}})
        if name=='PromisedLandStep02_BuildAbode1':
            overrides=next(value for key,value in entry[1] if key==['literal','overrides'])
            table=next(value for key,value in overrides[1] if key==['literal','tableOverride'])
            fields=literal(table,values)
            promised_steps[-1]['build_capacity']=next(row['val'] for row in fields.values() if row['key']=='BuildCapacity')
    # Append these functions after the existing program so pending callbacks in
    # older opening saves keep their original function identifiers.
    timeline_ui=assignment(local_parser,'uiTable.Timeline')
    for index,entry in timeline_ui[1]:
        item={'group':'Timeline','source_id':literal(index,values)}
        for key,value in entry[1]:
            if key[1] in ['strType','pos2d','offset','gui_info','object_get']:
                item[key[1]]=literal(value,values)
            elif key[1]=='gui':
                if value[:2]!=['index',['var','en_GuiTip']]: raise CompileError('Unexpected Timeline GUI target')
                item['gui']=literal(value[2],values)
            elif key[1]=='msg':
                name=literal(value,values)
                if name not in localization: raise CompileError(f'Missing Timeline localization: {name}')
                item.update(key=name,text=text(name,localization))
        if 'text' in item: messages[str(2000+literal(index,values))]=item
    timeline=assignment(local_parser,'tutorialTable.Timeline')
    timeline_steps=[]
    for index,entry in timeline[1]:
        name=next(literal(value,values) for key,value in entry[1] if key==['literal','name'])
        timeline_steps.append({'index':literal(index,values)-1,'name':name,
                               'hooks':{key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}})
    complete_hook=timeline_steps[4]['hooks']['onAbodeComplete']['function']
    timeline_steps[4]['abode_type']=next(literal(node[3],values) for node in nested_arrays(local_parser.functions[complete_hook]['body'])
                                         if len(node)==4 and node[:2]==['binary','=='] and node[2][:2]==['call',['var','AbodeType']])
    hud=assignment(global_parser,'en_HudComponent')
    if any(value!=['call',['var','AutoEnum'],[]] for _,value in hud[1]): raise CompileError('Unexpected HUD enum')
    values['en_HudComponent']={literal(key,values):index for index,(key,_) in enumerate(hud[1])}
    for name in ['FIRST_SHRINE','DISCOVERY']:
        values[name]=literal(assignment(local_parser,name),values)
    for name in ['getShrineOfExpansion','getTempleOfDiscovery']:
        helpers[name]=literal(named_function(local_parser,name),values)
    shrine_ui=assignment(local_parser,'uiTable.ShrineOfExpansion')
    for index,entry in shrine_ui[1]:
        item={'group':'ShrineOfExpansion','source_id':literal(index,values)}
        for key,value in entry[1]:
            if key[1] in ['strType','pos2d','offset','gui_info','object_get','pos3d_get']:
                item[key[1]]=literal(value,values)
            elif key[1]=='gui':
                if value[:2]!=['index',['var','en_GuiTip']]: raise CompileError('Unexpected shrine GUI target')
                item['gui']=literal(value[2],values)
            elif key[1]=='msg':
                name=literal(value,values)
                if name not in localization: raise CompileError(f'Missing shrine localization: {name}')
                item.update(key=name,text=text(name,localization))
        if 'text' in item: messages[str(3000+literal(index,values))]=item
    shrine=assignment(local_parser,'tutorialTable.ShrineOfExpansion')
    shrine_steps=[]
    for index,entry in shrine[1]:
        name=next(literal(value,values) for key,value in entry[1] if key==['literal','name'])
        shrine_steps.append({'index':literal(index,values)-1,'name':name,
                             'hooks':{key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}})
    # New source functions remain after every previously emitted callback ID.
    values['SCULPT_GRASS_POS']=literal(assignment(local_parser,'SCULPT_GRASS_POS'),values)
    belief_ui=assignment(local_parser,'uiTable.Belief')
    for index,entry in belief_ui[1]:
        item={'group':'Belief','source_id':literal(index,values)}
        for key,value in entry[1]:
            if key[1] in ['strType','pos2d','offset','gui_info','object_get','pos3d','hintDelay']:
                item[key[1]]=literal(value,values)
            elif key[1]=='gui':
                if value[:2]!=['index',['var','en_GuiTip']]: raise CompileError('Unexpected belief GUI target')
                item['gui']=literal(value[2],values)
            elif key[1]=='msg':
                name=literal(value,values)
                if name not in localization: raise CompileError(f'Missing belief localization: {name}')
                item.update(key=name,text=text(name,localization))
        if 'text' in item: messages[str(4000+literal(index,values))]=item
    belief=assignment(local_parser,'tutorialTable.Belief')
    belief_steps=[]
    for index,entry in belief[1]:
        name=next(literal(value,values) for key,value in entry[1] if key==['literal','name'])
        belief_steps.append({'index':literal(index,values)-1,'name':name,
                             'hooks':{key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}})
    for name in ['nrOfStartedSculpts','nrOfCompletedSculpts','nrOfFailedSculpts',
                 'needBeliefToSculptTipCounter','currentSculptPos','currentSculptPosAlt']:
        values[name]=literal(assignment(local_parser,name,initial=True),values)
    for name in ['onSculptStarted','onSculptComplete','onSculptFailed']:
        helpers[name]=literal(named_function(local_parser,name),values)
    belief_rules=clump_rules(source)
    values['DESKTOP_MODE'] = True
    discovery_card = assignment(local_parser, 'CARD_DISCOVERY')
    if discovery_card[:2] != ['binary', 'or'] or discovery_card[2][:3] != ['binary', 'and', ['var', 'DESKTOP_MODE']]:
        raise CompileError('Unexpected desktop Discovery card expression')
    values['CARD_DISCOVERY'] = literal(discovery_card[2][3], values)
    values['ClientVersion'] = literal(assignment(global_parser, 'ClientVersion'), values)
    image = NativeImage((source/'godus.s86').read_bytes())
    name_address, routine_address = struct.unpack('<II', image.read(0x1060dcb8, 8))
    if image.read(name_address, 17) != b'GetClientVersion\0' or routine_address != 0x10242820:
        raise CompileError('Unexpected native GetClientVersion binding')
    # The native function uses this constant when the version override is zero.
    values['CLIENT_VERSION'], = struct.unpack('<d', image.read(0x104ecd50, 8))
    for name in ['getPlotNearTempleOfDiscovery', 'getAbodeNearTempleOfDiscovery']:
        helpers[name] = literal(named_function(local_parser, name), values)
    values['EVENT_TEMPLE'] = literal(assignment(local_parser, 'EVENT_TEMPLE'), values)
    values['leashCount'] = literal(assignment(local_parser, 'leashCount', initial=True), values)
    discovery = {}
    for group, offset in [('Discovery', 5000), ('PitOfDoom', 5100), ('Leash', 5200)]:
        for index, entry in assignment(local_parser, 'uiTable.'+group)[1]:
            item = {'group': group, 'source_id': literal(index, values)}
            for key, value in entry[1]:
                if key[1] in ['strType','pos2d','offset','gui_info','object_get','hintDelay']:
                    item[key[1]] = literal(value, values)
                elif key[1] == 'gui':
                    item['gui'] = literal(value[2], values)
                elif key[1] == 'msg':
                    # Desktop selects the first localization key in these alternatives.
                    if value[:2] == ['binary','or'] and value[2][:3] == ['binary','and',['var','DESKTOP_MODE']]:
                        value = value[2][3]
                    name = literal(value, values)
                    if name not in localization: raise CompileError(f'Missing Discovery localization: {name}')
                    item.update(key=name,text=text(name,localization))
            messages[str(offset+literal(index,values))] = item
        discovery[group] = [
            {'name': next(literal(value,values) for key,value in entry[1] if key==['literal','name']),
             'hooks': {key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}}
            for _,entry in assignment(local_parser,'tutorialTable.'+group)[1]]
    helpers['getDock'] = literal(named_function(local_parser, 'getDock'), values)
    for index, entry in assignment(local_parser, 'uiTable.Events')[1]:
        item = {'group':'Events','source_id':literal(index,values)}
        for key, value in entry[1]:
            if key[1] in ['strType','pos2d','object_get']:
                item[key[1]] = literal(value, values)
            elif key[1] in ['gui','gui_info']:
                item[key[1]] = literal(value[2], values)
            elif key[1] == 'msg':
                name = literal(value, values)
                item.update(key=name,text=text(name,localization))
        messages[str(5300+item['source_id'])] = item
    discovery['Events'] = [
        {'hooks':{key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}}
        for _,entry in assignment(local_parser,'tutorialTable.Events')[1]]
    event_controller = 'expeditionmode/event_01/eventctrl_01/scripts.lua'
    event_results = {int(stage):int(value) for stage,value in re.findall(
        r'GetEventStage\(\) == (\d+) and Persist\("EventVoyageProgress"\)[^\n]*\n\s*Persist\("EventVoyageProgress", (\d+)\)',
        files[event_controller].decode('utf-8-sig'))}
    if set(event_results)!={1,2}: raise CompileError('Missing first-voyage return branches')
    values['FIRST_VOYAGE_RETURN'] = event_results
    used.append(event_controller)
    for name in ['storeFirstSettlement', 'getFirstSettlement']:
        helpers[name] = literal(named_function(local_parser, name), values)
    for name in ['FIELD_TYPE', 'JOB_BUILDER', 'JOB_FARMER']:
        values[name] = literal(assignment(local_parser, name), values)
    power_table = 'initialworldsetup/powerdata.csv'
    powers = rows(files,power_table)
    cost = assignment(local_parser, 'FARM_BELIEF_COST')
    if cost[:2]!=['call',['var','Table']]:
        raise CompileError('Unexpected Farming power cost expression')
    table_name, column, index = [literal(arg, values) for arg in cost[2]]
    if table_name!='Power Data' or powers[index][0]!='GodPower_PlaceSettlement_2':
        raise CompileError('Farming lesson references the wrong power row')
    values['FARM_BELIEF_COST'] = int(powers[index][powers[0].index(column)])
    builder = dict(zip(powers[0], next(row for row in powers if row[0]=='GodPower_PlaceSettlement_1')))
    if (builder['Code Hook'],builder['Temple Hash'],builder['Cast Type'])!=('SETTLEMENTCOMPRESS_2','Settlement_Builder','CONFIRM'):
        raise CompileError('Unexpected Builder Settlement power')
    builder_settlement = {'power':builder['Power Hash'], 'cost':int(builder['Cost 1']),
                          'radius_setting':'SettCompRadius2'}
    miner = dict(zip(powers[0], next(row for row in powers if row[0]=='GodPower_PlaceSettlement_3')))
    if (miner['Code Hook'],miner['Temple Hash'],miner['Cast Type'])!=('SETTLEMENTCOMPRESS_3','Settlement_Gem','CONFIRM'):
        raise CompileError('Unexpected Mining Settlement power')
    mining_settlement = {'power':miner['Power Hash'], 'cost':int(miner['Cost 1']),
                         'radius_setting':'SettCompRadius3'}
    used.append(power_table)
    for index, entry in assignment(local_parser, 'uiTable.Farming')[1]:
        item = {'group':'Farming','source_id':literal(index,values)}
        for key, value in entry[1]:
            if key[1] in ['strType','pos2d','object_get','gui_info']:
                item[key[1]] = literal(value, values)
            elif key[1] == 'gui':
                item['gui'] = literal(value[2], values)
            elif key[1] == 'msg':
                name = literal(value, values)
                item.update(key=name,text=text(name,localization))
        messages[str(5400+item['source_id'])] = item
    discovery['Farming'] = [
        {'hooks':{key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}}
        for _,entry in assignment(local_parser,'tutorialTable.Farming')[1]]
    helpers['checkFreeWheatCollected'] = literal(named_function(local_parser, 'checkFreeWheatCollected'), values)
    for index, entry in assignment(local_parser, 'uiTable.SuperFast')[1]:
        item = {'group':'SuperFast','source_id':literal(index,values)}
        for key, value in entry[1]:
            if key[1] in ['strType','pos2d','pos3d','offset','object_get','gui_info']:
                item[key[1]] = literal(value, values)
            elif key[1] == 'gui':
                item['gui'] = literal(value[2], values)
            elif key[1] == 'msg':
                name = literal(value, values)
                item.update(key=name,text=text(name,localization))
        messages[str(5500+item['source_id'])] = item
    discovery['SuperFast'] = [
        {'hooks':{key[1]:literal(value,values) for key,value in entry[1] if value[0]=='function'}}
        for _,entry in assignment(local_parser,'tutorialTable.SuperFast')[1]]
    farms = literal(assignment(local_parser,'FARMS'), values)
    post_load = local_parser.functions[named_function(local_parser,'onPostLoad',initial=True)[1]]['body']
    if not any(node[:2]==['call',['var','BuildAbode']] and node[2][2:6]==
               [['literal',0],['literal',False],['literal',1],['literal',1]] for node in nested_arrays(post_load)):
        raise CompileError('Missing Homeworld6 native field construction')
    fields = [{'x':row['x'],'z':row['y'],'size':row['size']} for row in farms.values()]
    follower_bytes = (source/'follower.group.bin').read_bytes()
    follower = resource_group(follower_bytes)
    bone_count = len(decode_skeleton(next(iter(follower[iw_hash('CIwAnimSkel')].values()))))
    sacrifice_clips = {'source':'follower.group.bin','sha256':hashlib.sha256(follower_bytes).hexdigest(),
                       'clips':{role:decode_animation(follower[iw_hash('CIwAnim')][iw_hash(name)],bone_count)['duration']
                                for role,name in FOLLOWER_CLIPS.items() if role.startswith('sacrifice_')}}
    # The Pit update compares the batch clock with both native float globals.
    if image.read(0x100f2ddb,6)!=bytes.fromhex('d905c4fb5b10') or image.read(0x100f2f86,6)!=bytes.fromhex('d905c8fb5b10'):
        raise CompileError('Missing Pit audio and gem timing bindings')
    sacrifice_clips['audio_delay'], = struct.unpack('<f',image.read(0x105bfbc4,4))
    sacrifice_clips['roll_divisor'], = struct.unpack('<d',image.read(0x104a0c10,8))
    if image.read(0x10026a9a,6)!=bytes.fromhex('d90568b45710') or image.read(0x10026aa2,6)!=bytes.fromhex('d9056cb45710'):
        raise CompileError('Missing source sacrifice birth-rate bindings')
    sacrifice_clips['birth_factor'], = struct.unpack('<f',image.read(0x1057b468,4))
    sacrifice_clips['settlement_birth_factor'], = struct.unpack('<f',image.read(0x1057b46c,4))
    beam_source = 'VFX/Scripts/MSC_TempleOfDoom.txt'
    beam_bytes = (source/beam_source).read_bytes()
    beam_text = beam_bytes.decode('ascii').replace('\r\n','\n')
    beam_model = re.search(r'^GEO=.*?/([^/]+)\.geo$',beam_text,re.MULTILINE)
    beam_texture = re.search(r'^TEX=.*?VFX\\Textures\\([^\\\r\n]+)$',beam_text,re.MULTILINE)
    beam_keys = re.search(r'^SETSP=LightShaft:Alpha=(.+)$',beam_text,re.MULTILINE)
    trigger = re.search(r'^@([\d.]+):LABEL=TriggerSacrifice$',beam_text,re.MULTILINE)
    scale = re.search(r'GEO=.*?\nSCALE=([\d.]+)',beam_text)
    if not all([beam_model,beam_texture,beam_keys,trigger,scale]): raise CompileError('Missing original Pit beam parameters')
    trigger_time = float(trigger[1])
    curve = [[float(t)-trigger_time,float(alpha)] for t,alpha in re.findall(r'@([\d.]+):([\d.]+);',beam_keys[1]) if float(t)>=trigger_time]
    beam = {'source':beam_source,'sha256':hashlib.sha256(beam_bytes).hexdigest(),
            'model':'vfx.group.bin:%08x'%iw_hash(beam_model[1]),'texture':'VFX/Textures/'+beam_texture[1],
            'scale':float(scale[1]),'curve':curve}

    config = {}
    for path in ['config.csv','balance/config.csv']:
        for row in rows(files,path):
            if len(row)<2 or not row[0] or row[0].startswith('#'): continue
            try: config[row[0]]=float(row[1])
            except ValueError: pass
        used.append(path)
    clock = day_cycle((source/'godus.s86').read_bytes(),config)
    rain_card = next(row for row in tables['initialworldsetup6/grainlevels.csv'] if row[1]=='Card_Adv_RainOfPurity_1')
    rain_power = next(row[0] for row in tables['initialworldsetup6/unlocks.csv']
                      if row[:2]==['GodPower_RainOfPurity',rain_card[1]])
    rain_native = {'cost_per_second':(0x100fa9b7,'d80d04395c10'),
                   'radius':(0x100faa48,'d9050c355c10'),
                   'growth_bonus':(0x100b8204,'d905e82d5b10')}
    for address, opcode in rain_native.values():
        if image.read(address,6)!=bytes.fromhex(opcode):
            raise CompileError(f'Unexpected Rain of Purity instruction at {address:#x}')
    rain = {'card':rain_card[1],'power':rain_power,'fields':int(rain_card[0]),
            'cost_per_second':config['RainOfPurityCostPerSecond'],'radius':config['PURIFY_RADIUS'],
            'growth_bonus':config['EncouragementMultiplier'],
            'native_instructions':{name:address for name,(address,_) in rain_native.items()}}
    cliff_card = next(row for row in tables['initialworldsetup6/populationlevels.csv'] if row[1]=='Card_CliffSculptingLevel1')
    cliff_power = next(row for row in rows(files,power_table) if row[0]=='GodPower_CliffSculpt')
    cliff_unlocks = {row[0] for row in tables['initialworldsetup6/unlocks.csv']
                     if row[1]==cliff_card[1]+'_COMPLETED'}
    if cliff_power[2]!='CLIFFSCULPT' or not {cliff_power[0],'CliffSculptingLevel1'}<=cliff_unlocks:
        raise CompileError('Unexpected Cliff Sculpting unlocks')
    cliff_opcodes = {0x10167af7:'837968187411', 0x10167b6a:'d905d8da5d10',
                     0x10167b51:'d905dcda5d10', 0x10167b38:'d905e0da5d10', 0x10167b1f:'d905e4da5d10',
                     0x101119f2:'db05ecd4fc10', 0x10111a8f:'da25ecd4fc10',
                     0x100372bd:'d80dbcdf5910dc05e80b4a10'}
    for address, opcode in cliff_opcodes.items():
        if image.read(address,len(bytes.fromhex(opcode)))!=bytes.fromhex(opcode):
            raise CompileError(f'Unexpected Cliff Sculpting instruction at {address:#x}')
    upgrade_table = 'gui/powerupgradedata.csv'
    used.append(upgrade_table)
    cliff_upgrades = []
    for rank, row in enumerate((r for r in rows(files,upgrade_table) if r[0]=='Card_GodPower_CliffSculpt'),2):
        if row[2]!='AlwaysUnlocked' or row[5]!='UPGRADE' or not any(
                r[:2]==[f'CliffSculptingLevel{rank}',row[1]] for r in tables['initialworldsetup6/unlocks.csv']):
            raise CompileError(f'Unexpected Cliff Sculpting upgrade at rank {rank}')
        cliff_upgrades.append({'id':row[1],'layers':int(config[f'CLIFF_SCULPTING_LEVEL_{rank}']),
                              'cost':int(row[3]),'currency':row[4].lower(),
                              'button':text(row[6],localization),'title':text(row[7],localization),
                              'description':text(row[8],localization)})
    cliff = {'card':cliff_card[1],'population':int(cliff_card[0]),'power':cliff_power[0],
             'layers':int(config['CLIFF_SCULPTING_LEVEL_1']),'belief_multiplier':config['CliffBeliefMult'],
             'belief_threshold':struct.unpack('<f',image.read(0x104a0c58,4))[0],
             'layers_label':text('LOC_INFO_STATDESC_SculptLay',localization),
             'native_instructions':list(cliff_opcodes),'upgrades':cliff_upgrades}
    underwater_card = next(row for row in tables['initialworldsetup6/populationlevels.csv'] if row[1]=='Card_UnderWaterSculpt')
    if not any(row[:2]==['DeepWaterSculpt',underwater_card[1]+'_COMPLETED'] for row in tables['initialworldsetup6/unlocks.csv']):
        raise CompileError('Missing the original deep-water unlock')
    water_instructions = {
        0x100d3c95:'d90524745b10dc0528a24a10',
        0x100d3e4b:'d90524745b10dc0528a24a10',
        0x10036154:'d9052cdf5910dd0528a24a10',
        0x10036ef0:'558becd90504107d10',
        0x10037255:'d90520107d10',
    }
    for address, opcode in water_instructions.items():
        expected = bytes.fromhex(opcode)
        if image.read(address,len(expected))!=expected:
            raise CompileError(f'Unexpected underwater sculpt instruction at {address:#x}')
    sea_level = int(struct.unpack('<d',image.read(0x104aa228,8))[0])
    underwater = {'card':underwater_card[1],'population':int(underwater_card[0]),'unlock':'DeepWaterSculpt',
                  'sea_level':sea_level,'shallow_level':sea_level+int(config['DeepWaterSculptLevel']),
                  'cost_curve':[[sea_level+int(config[f'BeliefStep{i}']),config[f'BeliefCost{i}']] for i in range(8)],
                  'belief_threshold':cliff['belief_threshold'],'belief_multiplier':cliff['belief_multiplier'],
                  'native_instructions':list(water_instructions)}
    swamp_card = next(row for row in tables['initialworldsetup6/populationlevels.csv'] if row[1]=='Card_Adv_Swamp_1')
    swamp_power = next(row for row in rows(files,power_table) if row[0]=='GodPower_Swamp')
    if swamp_power[2]!='SWAMP' or swamp_power[4]!='MIRACLE' or swamp_power[8]!='INSTANT' or not any(
            row[:2]==[swamp_power[0],swamp_card[1]] for row in tables['initialworldsetup6/unlocks.csv']):
        raise CompileError('Unexpected original Swamp power or discovery condition')
    swamp_instructions = {
        'player_cast':(0x1008b19e,'e8ed0e0b00'),
        'script_cast':(0x1008f019,'e872d00a00'),
        'spread_frame_cap':(0x1013bb3d,'d905c0165d10'),
        'spread_seconds':(0x1013bb68,'d835a0165d10'),
        'spread_elevation':(0x1013bc67,'dc1d400c4a10'),
        'spread_limit':(0x1013bd14,'d905bc125d10'),
        'spread_strength':(0x1013bdf7,'d80dbc165d10'),
        'spread_increment':(0x1013beb5,'d80db4165d10'),
        'puddle_size':(0x1013b418,'d905a4165d10'),
        'cast_sound':(0x1013c383,'6829fb3532'),
        'follower_drown_threshold':(0x1006d841,'d905bc415a10'),
    }
    for name, (address, opcode) in swamp_instructions.items():
        expected = bytes.fromhex(opcode)
        if image.read(address,len(expected))!=expected:
            raise CompileError(f'Unexpected Swamp instruction for {name} at {address:#x}')
    def swamp_value(name, address):
        return config.get(name,struct.unpack('<f',image.read(address,4))[0])
    race_table = 'balance/race.csv'
    used.append(race_table)
    race_rows = rows(files,race_table)
    swamp_column = race_rows[0].index('SwampDamage')
    swamp_damage = {row[0]:float(row[swamp_column] or '1') for row in race_rows[1:] if row and not row[0].startswith('#')}
    swamp_races = {'Brown Head':'BrownHead','Red Head':'RedHead','Champion':'Champion','Astari':'AstariRace','NakedRace':'NakedRace'}
    swamp = {
        'card':swamp_card[1],'power':swamp_power[0],'population':int(swamp_card[0]),'belief':int(swamp_power[10]),
        'initial':[[point['x'],point['y']] for point in literal(assignment(local_parser,'SWAMPS'),values).values()],
        'min_radius':swamp_value('SWAMP_MIN_BLIGHT_RADIUS',0x105d1698),
        'max_radius':swamp_value('SWAMP_MAX_BLIGHT_RADIUS',0x105d169c),
        'seconds':swamp_value('SWAMP_SECS_TILL_MAX_RADIUS',0x105d16a0),
        'max_tiles':int(swamp_value('SWAMP_MAX_TILES',0x105d12bc)),
        'min_puddle_size':0 if config.get('SwampSizeZeroPuddles',0) else 1,
        'max_puddle_size':int(swamp_value('SWAMP_MAX_PUDDLE_SIZE',0x105d16a4)),
        'max_delta':swamp_value('SWAMP_MAX_DELTATIME',0x105d16c0),
        'expansion':swamp_value('SWAMP_RADIUS_EXTRA_EXPAND_FAC',0x105d16ac),
        'min_blight':swamp_value('SWAMP_BLIGHT_MIN_THRESH',0x105d16a8),
        'max_blight':swamp_value('SWAMP_MAX_BLIGHT_VAL',0x105d16bc),
        'blight_per_second':swamp_value('SWAMP_BLIGHT_VALUE_INCREASE_SPEED',0x105d16b4),
        'sculpt_clear_chance':swamp_value('SWAMP_PROB_REMOVE_BLIGHT_ON_SCULPT',0x105d16b8),
        'elevation_tolerance':struct.unpack('<d',image.read(0x104a0c40,8))[0],
        'bounds_margin':struct.unpack('<d',image.read(0x104aae40,8))[0],
        'drown_threshold':swamp_value('FollowerSwampProgressToCauseDrown',0x105a41bc),
        'timeout':config['SWAMP_TIMEOUT'],
        'damage':{race:swamp_damage['Base']*swamp_damage[source_race] for race,source_race in swamp_races.items()},
        'clear_hint':text('LOC_EX09M01_T02',localization),
        'clips':{role:decode_animation(follower[iw_hash('CIwAnim')][iw_hash(name)],bone_count)['duration']
                 for role,name in FOLLOWER_CLIPS.items() if role.startswith('swamp_')},
        'native_instructions':{name:address for name,(address,_) in swamp_instructions.items()},
    }
    fountain_card = next(row for row in tables['initialworldsetup6/populationlevels.csv'] if row[1]=='Card_Adv_Fountain')
    fountain_power = next(row for row in rows(files,power_table) if row[0]=='GodPower_PlaceGiftFountain')
    fountain_type = next(row for row in rows(files,'balance/templetypes.csv') if row[0]==fountain_power[5])
    fountain_model = next(row for row in rows(files,'balance/templegenerictypes.csv') if row[0]==fountain_type[1])
    fountain_reaction = next(row for row in reactions if row[0]==fountain_type[12])
    fountain_tap = next(row for row in rows(files,'balance/happiness.csv') if row[1]=='Fountain tapped')
    used.extend(['balance/templetypes.csv','balance/templegenerictypes.csv','balance/happiness.csv'])
    rock_belief, collector, belief_tables = belief_advances(
        files,image,tables['initialworldsetup6/populationlevels.csv'],tables['initialworldsetup6/unlocks.csv'],
        rows(files,power_table),config,localization)
    used.extend(belief_tables)
    if image.read(0x1060d2e8,8)!=struct.pack('<II',0x104ed318,0x102463d0) or image.read(0x104ed318,11)!=b'GetGemCost\0':
        raise CompileError('Missing native gem cost binding')
    if image.read(0x10025fdf,6)!=bytes.fromhex('d9055cb45710') or image.read(0x10025ff0,2)!=bytes.fromhex('d839'):
        raise CompileError('Missing native gem divisor')
    tap_name = b'Fountain tapped\0'
    if image.read(0x1013e958,5)!=b'\x68'+struct.pack('<I',0x104ca798) or image.read(0x104ca798,len(tap_name))!=tap_name:
        raise CompileError('Missing native Fountain happiness event')
    f32 = lambda value: struct.unpack('<f',struct.pack('<f',float(value)))[0]
    gem_divisor, = struct.unpack('<f',image.read(0x1057b45c,4))
    gems = int(round(f32(f32(fountain_power[10])/gem_divisor)))
    if gems!=10 or not any(row[:2]==[fountain_power[0],fountain_card[1]+'_COMPLETED']
                           for row in tables['initialworldsetup6/unlocks.csv']):
        raise CompileError('Unexpected original Fountain cost or unlock')
    fountain = {'card':fountain_card[1],'population':int(fountain_card[0]),'power':fountain_power[0],
                'model':fountain_model[3]+'.group.bin:%08x'%iw_hash('rank1_loc1_var1_storey1'),
                'width':int(fountain_model[1]),'depth':int(fountain_model[2]),'radius':float(fountain_type[3]),
                'gems':gems,'reaction_seconds':float(fountain_reaction[4]),'happiness':float(fountain_tap[2]),
                'native_price':{'binding':0x1060d2e8,'function':0x10025fd0,'divisor_address':0x1057b45c},
                'native_happiness_instruction':0x1013e958}
    for index, entry in assignment(local_parser,'uiTable.Happiness')[1]:
        source_id=literal(index,values)
        if source_id not in [2,3,4,6]: continue
        item={'group':'Happiness','source_id':source_id}
        for key,value in entry[1]:
            if key[1] in ['strType','pos2d','gui_info']:
                item[key[1]]=literal(value,values)
            elif key[1]=='gui':
                item['gui']=literal(value[2],values)
            elif key[1]=='msg':
                name=literal(value,values)
                item.update(key=name,text=text(name,localization))
        messages[str(5600+source_id)]=item
    sculpt_hook=named_function(global_parser,'onSculptFailed')
    free_band={}
    for node in nested_arrays(global_parser.functions[sculpt_hook[1]]['body']):
        if len(node)==4 and node[0]=='binary' and node[1] in ['<','>'] and node[2][:1]==['call'] and node[3][:1]==['literal']:
            if node[2][1]==['var','min'] and node[1]=='<': free_band['min']=node[3][1]
            if node[2][1]==['var','max'] and node[1]=='>': free_band['max']=node[3][1]
    if set(free_band)!={'min','max'}: raise CompileError('Missing authored coastal sculpting band')
    rocks = authored_rocks(files, (source/'godus.s86').read_bytes(),
                           (source/'GeneratedDataFiles/Models.csv').read_bytes(), 'initialworldsetup6')
    leash_rules = {'hold_seconds':config['LeashFirstHoldTime'], 'max_length':config['LeashMaxLength'],
                   'follower_cost':int(config['LeashBeliefPerFollower']), 'home_cost':int(config['LeashBeliefPerHouse']),
                   'leash_size':config['LeashSize'],
                   'leash_color':[config['LeashColour.'+axis] for axis in 'xyz']+[config['LeashOpacity']]}
    ark,ark_messages = ark_progression(files,local_parser,localization)
    messages.update(ark_messages)
    capacity, capacity_messages, capacity_tables = capacity_shrine(files, local_parser, values, localization, source)
    messages.update(capacity_messages)
    used.extend(capacity_tables)
    speed, speed_tables = speed_shrine(files, tables, power_table, localization, source)
    used.extend(speed_tables)
    settlements, settlement_tables = settlement_upgrades(files, tables['initialworldsetup6/unlocks.csv'], config, localization)
    used.extend(settlement_tables)
    meteor, meteor_tables = meteor_rules(source, files, image, config, tables['initialworldsetup6/populationlevels.csv'],
                                         tables['initialworldsetup6/unlocks.csv'], power_table, localization)
    used.extend(meteor_tables)
    result = {'version':20, 'scope':'initialworldsetup6', 'map':'Homeworld6',
              'source':archive.relative_to(source).as_posix(), 'source_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
              'files_sha256':{name:hashlib.sha256(files[name]).hexdigest() for name in used},
              'starts':starts, 'constants':values, 'helpers':helpers, 'trail_hooks':trail_hooks, 'waiting_hooks':waiting_hooks,
              'arrival_hooks':arrival_hooks, 'day_cycle':clock,
              'promised_steps':promised_steps,'timeline_steps':timeline_steps,'shrine_steps':shrine_steps,
              'discovery':discovery,'authored_fields':fields,'pit_clips':sacrifice_clips,'pit_beam':beam,'leash_rules':leash_rules,'belief_steps':belief_steps,'belief_rules':belief_rules,'authored_rocks':rocks,
              'object_config':{'taps_to_destroy_rock':int(config['tapsToDestroyRock'])},'rain':rain,'fountain':fountain,'cliff_sculpt':cliff,
              'underwater_sculpt':underwater,
              'swamp':swamp,'meteor':meteor,
              'rock_belief':rock_belief,'belief_collector':collector,'builder_settlement':builder_settlement,
              'mining_settlement':mining_settlement,'ark':ark,'capacity_shrine':capacity,'speed_shrine':speed,
              'settlement_upgrades':settlements,
              'route':[{'index':i,'entry':entry} for i,entry in sorted(route.items())],
              'program':{'body':[], 'functions':local_parser.functions,
                         'local_function_names':local_parser.local_function_names,
                         'builtins':sorted(local_parser.calls | {'startScrollingTutorial'})},
              'messages':messages, 'tip_text':{key:text(key,localization) for key in ['LOC_TUT_210','LOC_TUT_134']},
              'tables':tables, 'coastal_free_band':free_band}
    output.mkdir(parents=True,exist_ok=True)
    from tools.leash_lesson import write as write_leash_lesson
    write_leash_lesson(source, output)
    (output/'homeworld6-story.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    pack = source/'stream/Homeworld6.pack'
    fields, starts, evidence, start_record = packed_map(pack)
    if starts != b'\0'*4: raise CompileError('Expected original manual-start map to have no packed starts')
    paths = {}
    for kind in ['terrain','tree','rock']:
        filename=f'homeworld6-{kind}.bin'
        (output/filename).write_bytes(fields[kind])
        paths[kind]={'path':'campaign/'+filename,'sha256':hashlib.sha256(fields[kind]).hexdigest()}
    runtime = {'id':'homeworld6', 'name':'Homeworld6', 'width':1024, 'sea_level':19, 'layer_height':0.3,
               'height_data':paths['terrain']['path'], 'height_sha256':paths['terrain']['sha256'],
               'fields':{kind:paths[kind] for kind in ['tree','rock']}, 'followers':result['starts'],
               'story_definition':'campaign/homeworld6-story.json', 'story_version':result['version'],
               'pack_source':pack.relative_to(source).as_posix(), 'pack_sha256':hashlib.sha256(pack.read_bytes()).hexdigest(),
               'decoder_sources':evidence, 'packed_start_record':start_record}
    (output/'homeworld6-opening.json').write_text(json.dumps(runtime,indent=2)+'\n')
    return result


if __name__=='__main__':
    data=extract()
    print(f"Authored Homeworld6: {len(data['starts'])} starts, {len(data['route'])} trail checkpoints")
