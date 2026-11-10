"""Recover authored campaign starts and tutorial programs from supplied Lua.

Expressions are parsed to inert data. No source code is evaluated or executed.
The retained function bodies are consumed by the bounded simulation interpreter.
"""
import hashlib
import json
from pathlib import Path

from tools.current_cards import decode_archive, rows, text
from tools.campaign import packed_map
from tools.voyage_lua import Compiler, CompileError
from tools.day_cycle import extract as day_cycle
from tools.map_objects import authored_rocks

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


def named_function(compiler, name):
    pattern = ['function', name, '(']
    matches = [i for i in range(len(compiler.tokens)-3) if compiler.tokens[i:i+3] == pattern]
    if len(matches) != 1: raise CompileError(f'Ambiguous authored function: {name}')
    compiler.cursor = matches[0]+2
    return compiler.function()


def nested_arrays(value):
    if isinstance(value,list):
        yield value
        for item in value: yield from nested_arrays(item)


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
        'gatherInitialFollowers','triggerBirdVFX','freezeTimeOfDay','getFirstRock','gotoRock']}
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
    config = {}
    for path in ['config.csv','balance/config.csv']:
        for row in rows(files,path):
            if len(row)<2 or not row[0] or row[0].startswith('#'): continue
            try: config[row[0]]=float(row[1])
            except ValueError: pass
        used.append(path)
    clock = day_cycle((source/'godus.s86').read_bytes(),config)
    sculpt_hook=named_function(global_parser,'onSculptFailed')
    free_band={}
    for node in nested_arrays(global_parser.functions[sculpt_hook[1]]['body']):
        if len(node)==4 and node[0]=='binary' and node[1] in ['<','>'] and node[2][:1]==['call'] and node[3][:1]==['literal']:
            if node[2][1]==['var','min'] and node[1]=='<': free_band['min']=node[3][1]
            if node[2][1]==['var','max'] and node[1]=='>': free_band['max']=node[3][1]
    if set(free_band)!={'min','max'}: raise CompileError('Missing authored coastal sculpting band')
    rocks = authored_rocks(files, (source/'godus.s86').read_bytes(),
                           (source/'GeneratedDataFiles/Models.csv').read_bytes(), 'initialworldsetup6')
    result = {'version':6, 'scope':'initialworldsetup6', 'map':'Homeworld6',
              'source':archive.relative_to(source).as_posix(), 'source_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
              'files_sha256':{name:hashlib.sha256(files[name]).hexdigest() for name in used},
              'starts':starts, 'constants':values, 'helpers':helpers, 'trail_hooks':trail_hooks, 'waiting_hooks':waiting_hooks,
              'arrival_hooks':arrival_hooks, 'day_cycle':clock,
              'promised_steps':promised_steps,'authored_rocks':rocks,
              'object_config':{'taps_to_destroy_rock':int(config['tapsToDestroyRock'])},
              'route':[{'index':i,'entry':entry} for i,entry in sorted(route.items())],
              'program':{'body':[], 'functions':local_parser.functions,
                         'builtins':sorted(local_parser.calls | {'startScrollingTutorial'})},
              'messages':messages, 'tip_text':{'LOC_TUT_210':text('LOC_TUT_210',localization)},
              'tables':tables, 'coastal_free_band':free_band}
    output.mkdir(parents=True,exist_ok=True)
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
               'story_definition':'campaign/homeworld6-story.json',
               'pack_source':pack.relative_to(source).as_posix(), 'pack_sha256':hashlib.sha256(pack.read_bytes()).hexdigest(),
               'decoder_sources':evidence, 'packed_start_record':start_record}
    (output/'homeworld6-opening.json').write_text(json.dumps(runtime,indent=2)+'\n')
    return result


if __name__=='__main__':
    data=extract()
    print(f"Authored Homeworld6: {len(data['starts'])} starts, {len(data['route'])} trail checkpoints")
