"""Recover current the original source campaign research and economy tables without assets or invented rules."""
import hashlib
import json
from pathlib import Path
import re

from tools.current_cards import decode_archive, rows, text as localized_text
from tools.native_config import recover

ROOT = Path(__file__).resolve().parents[1]


def weyworld_harvest(script):
    text = script.decode('utf-8-sig')
    plots = []
    for name, kind, role in [('FREE_FIELDS', 'farm', 1), ('FREE_MINES', 'mine', 2)]:
        block = re.search(rf'^{name}\s*=\s*\{{(.*?)^\}}', text, re.MULTILINE | re.DOTALL)
        constructor = (f'BuildAbode({name}[i].x, {name}[i].y, 0, false, {role}, 1, '
                       f'{name}[i].size and {name}[i].size or 4, 0, true)')
        if block is None or constructor not in text or f'AbodeFillFood({name}[i].id)' not in text:
            raise ValueError(f'Unrecognized Weyworld harvest setup for {name}')
        record = r'\{x=(\d+),\s*y=(\d+),\s*size=(\d+)\}'
        points = re.findall(record, block[1])
        if not points or re.sub(record, '', block[1]).strip(' ,\t\r\n'):
            raise ValueError(f'Unrecognized Weyworld coordinates for {name}')
        plots.extend({'kind': kind, 'x': int(x), 'z': int(z), 'size': int(size)} for x, z, size in points)
    return plots


def weyworld_arrival(script, house_values):
    text = script.decode('utf-8-sig')
    boat = re.search(r'^BOAT_POS\s*=\s*\{x=(\d+),\s*y=(\d+)\}', text, re.MULTILINE)
    build = re.search(r'BuildAbode\(BOAT_POS.x, BOAT_POS.y, 0, true, 0, 0, (\d+), 0, true\)', text)
    capacity = re.search(r'pop = PeopleInArk\(\)\s+Table\("House Values", "Capacity", (\d+), pop\)', text)
    if not (boat and build and capacity and 'AbodeLockBreed(boat)' in text):
        raise ValueError('Unrecognized Weyworld Ark arrival')
    header = [name.strip() for name in house_values[0]]
    index = int(capacity[1])
    house = dict(zip(header, [row for row in house_values if row and row[0].isdigit()][index-1]))
    if house['Name Hash'] != 'AbodeType_1_Rank_4' or house['Model Name'] != 'arkabode' or int(build[1]) < int(house['Base Size']):
        raise ValueError('Unrecognized Weyworld Ark abode row')
    arrival = text.split('--Place initial followers', 1)[1].split('--Place initial player owned fields', 1)[0]
    followers = re.findall(r'SpawnFollower\(0,(\d+),(\d+),0,0,(true|false),0\);', arrival)
    if len(followers) != 2:
        raise ValueError('Unrecognized Weyworld arrival followers')
    return {
        'ark': {'x': int(boat[1]), 'z': int(boat[2]), 'house_row': index,
                'size': int(house['Base Size']), 'model': house['Model Name'], 'title': house['House Name'],
                'build_ticks': max(1, round(float(house['Build Time'])*10))},
        'followers': [{'x': int(x), 'z': int(z), 'female': sex == 'true'} for x, z, sex in followers],
    }


def weyworld_tutorial(script, localization):
    source = script.decode('utf-8-sig')
    section = source.split('--WEYWORLD TUTORIALS',1)[1].split('uiTable.WeyworldStory',1)[0]
    point = r'\{(\d+),\s*(\d+),\s*(\d+)\s*\*\s*\.3\}'

    def positions(name, group=False):
        if group:
            block = re.search(rf'^{name}\s*=\s*\{{(.*?)^\}}',section,re.MULTILINE|re.DOTALL)
            matches = re.findall(point,block[1]) if block else []
        else:
            matches = re.findall(rf'^{name}\s*=\s*'+point,section,re.MULTILINE)
        if len(matches)!=(2 if group else 1): raise ValueError(f'Unrecognized Weyworld position {name}')
        points = [list(map(int,match)) for match in matches]
        return points if group else points[0]

    messages = {}
    for kind,key in re.findall(r'\{strType="([^"]+)"[^}]*?msg="([^"]+)"',section):
        message_id = 5800+int(key.removeprefix('LOC_WeyTut_'))
        messages[str(message_id)]={'strType':kind,'text':localized_text(key,localization),'key':key}
    if len(messages)!=6 or any(not record['text'] for record in messages.values()):
        raise ValueError('Incomplete Weyworld tutorial')
    angle = re.search(r'SetCameraBaseRotation\((-?\d+),\s*1\)',source)
    if angle is None: raise ValueError('Missing Weyworld camera rotation')
    return {'camera_degrees':int(angle[1]),'messages':messages,
            'verdant':positions('FIRST_VERDANT_LAND_POS'),'rugged':positions('FIRST_RUGGED_LAND_POS'),
            'hallowed':positions('HALLOWED_GROUND_POSITIONS',True),'granite':positions('FIRST_GRANITE_POS'),
            'biome_messages':{kind:localized_text(key,localization) for kind,key in {
                'home':'LOC_Weyworld_NeedMonasteries','farm':'LOC_WeyWorld_BadBiome_Farmer','mine':'LOC_WeyWorld_BadBiome_Miner'}.items()}}


def extract(source=ROOT / 'data/godus2_4', output=ROOT / 'game/assets/original/campaign'):
    archive = source / 'received/godussteamrel/balance.datz'
    executable = source / 'godus.s86'
    files = decode_archive(archive.read_bytes())
    used = {}

    def table(name):
        used[name] = hashlib.sha256(files[name]).hexdigest()
        return rows(files, name)

    stickers = {}
    for row in table('initialworldsetup/stickerdata.csv'):
        if len(row) < 8 or not row[0].startswith('Sticker_'): continue
        stickers[row[0]] = {'era': int(row[2] or -1), 'internal': row[3] == '1',
                            'contributions': {row[i]: int(row[i+1]) for i in (4, 6) if row[i] and row[i+1]}}
    scopes = {}
    for prefix in ['initialworldsetup'] + [f'initialworldsetup{i}' for i in range(2, 8)]:
        cards = {}
        for row in table(prefix + '/carddata.csv'):
            if len(row) < 11 or not row[0].startswith('Card_'): continue
            cards[row[0]] = {'id': row[0], 'type': row[2], 'reward_type': row[3], 'power': row[4],
                            'era': int(row[6] or -1), 'research_type': row[7], 'research_needed': int(row[8] or 0),
                            'prerequisite': row[11] if len(row) > 11 else ''}
        unlocks = {}
        for row in table(prefix + '/unlocks.csv'):
            if len(row) > 1 and row[0] and not row[0].startswith('#'):
                unlocks.setdefault(row[0], []).append(row[1].strip())
        levels = [{'population': int(row[0]), 'card': row[1]} for row in table(prefix + '/populationlevels.csv')
                  if len(row) > 1 and row[0].isdigit()]
        currency_levels = {}
        for resource in ['grain', 'ore']:
            name = prefix + '/' + resource + 'levels.csv'
            currency_levels[resource] = [{'population': int(row[0]), 'card': row[1]}
                                         for row in table(name) if len(row)>1 and row[0].isdigit()] if name in files else []
        scopes[prefix] = {'cards': cards, 'unlocks': unlocks, 'population_levels': levels,
                          'currency_levels': currency_levels}
    modifiers = []
    for row in table('balance/balanceunlockmodifier.csv'):
        if len(row) < 2 or not row[0] or row[0].startswith('#') or not row[1]: continue
        fields = [part.strip() for part in row[1].split(',')]
        modifiers.append({'unlock': row[0], 'fields': fields})
    tables = {name: table(name) for name in ['balance/housevalues.csv', 'balance/jobs.csv', 'balance/templetypes.csv',
              'balance/templegenerictypes.csv', 'config.csv', 'balance/config.csv', 'balance/happiness.csv', 'assets/map_object_values.csv', 'balance/environmentbuffs.csv', 'initialworldsetup/grainlevels.csv',
              'initialworldsetup/orelevels.csv', 'initialworldsetup/initialmapobjects.csv',
              'initialworldsetup/rewardchests.csv', 'initialworldsetup/influence_areas.csv']}
    versions = dict(table('homeworldver.csv'))
    if versions.get('1') != '7':
        raise ValueError("Expected the supplied Weyworld terrain version")
    scope = 'initialworldsetup' + versions['1']
    weyworld = {name: table(f'{scope}/{name}.csv') for name in ('info', 'influence_areas', 'rewardchests', 'biomes')}
    weyworld['scope'] = scope
    script = f'{scope}/scripts.lua'
    weyworld['harvest_source'] = {'path': script, 'sha256': hashlib.sha256(files[script]).hexdigest()}
    weyworld['harvest_sites'] = weyworld_harvest(files[script])
    weyworld['arrival'] = weyworld_arrival(files[script], tables['balance/housevalues.csv'])
    localization = {row[0]:row[1] for row in table('gui/localization.csv') if len(row)>1 and row[0].startswith('LOC_')}
    weyworld['tutorial'] = weyworld_tutorial(files[script],localization)
    native = recover(executable.read_bytes(), ['settlement', 'settworker', 'settpop', 'setcap', 'farming', 'crop', 'mining', 'belief', 'speed', 'fertil'])
    config = {key: value['value'] for key, value in native.items()}
    for name in ['config.csv', 'balance/config.csv']:
        for row in tables[name]:
            if len(row) > 1 and row[0] and not row[0].startswith('#'):
                try: config[row[0]] = float(row[1])
                except ValueError: pass
    result = {'version': 1, 'source': archive.relative_to(source).as_posix(), 'source_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
              'executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(), 'tables_sha256': used,
              'native_configuration': native, 'configuration': config, 'scopes': scopes, 'stickers': stickers,
              'modifiers': modifiers, 'tables': tables, 'world_registrations': {'homeworld7': weyworld}}
    output.mkdir(parents=True, exist_ok=True)
    (output / 'research-rules.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


if __name__ == '__main__':
    result = extract()
    print(f"Original campaign research: {len(result['scopes'])} source scopes, {len(result['stickers'])} sticker definitions")
