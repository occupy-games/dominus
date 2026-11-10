"""Recover current the original source campaign research and economy tables without assets or invented rules."""
import hashlib
import json
from pathlib import Path

from tools.current_cards import decode_archive, rows
from tools.native_config import recover

ROOT = Path(__file__).resolve().parents[1]


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
              'modifiers': modifiers, 'tables': tables}
    output.mkdir(parents=True, exist_ok=True)
    (output / 'research-rules.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


if __name__ == '__main__':
    result = extract()
    print(f"Original campaign research: {len(result['scopes'])} source scopes, {len(result['stickers'])} sticker definitions")
