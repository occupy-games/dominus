#!/usr/bin/env python3
"""Launch the private writable runtime without modifying the installed app."""
import json
import os
from pathlib import Path
import shutil
import sys

bundle=Path(__file__).resolve().parents[1]
root=Path(os.environ.get('DOMINUS_RUNTIME_DIRECTORY',Path.home()/'Library/Application Support/Dominus/runtime'))
root.mkdir(parents=True,exist_ok=True)
for name in ['tools','game','assets']:
    shutil.copytree(bundle/name,root/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','.godot'))
shutil.copytree(bundle/'bootstrap',root/'bootstrap',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
(root/'config').mkdir(exist_ok=True)
for path in (bundle/'config').iterdir():
    target=root/'config'/path.name
    if path.name in ['asset_source.json','settings.defaults.json'] or not target.exists():shutil.copy2(path,target)
python=bundle/'python/bin/python3'
os.environ['DOMINUS_PYTHON']=str(python)
os.environ['SSL_CERT_FILE']=str(bundle/'dependencies/share/cacert.pem')
os.environ['DOMINUS_BUNDLE']=str(bundle)
os.environ['DOMINUS_RUNTIME_DIRECTORY']=str(root)
os.environ['DOMINUS_LAUNCH_ARGUMENTS']=json.dumps(sys.argv[1:])
ready=root/'content-ready.json'
try:
    prepared=json.loads(ready.read_text())
    valid=prepared.get('source_sha1')==json.loads((root/'config/asset_source.json').read_text())['sha1']
    valid=valid and prepared.get('recipe_sha256')==json.loads((bundle/'content-recipe.json').read_text())['sha256']
    valid=valid and all((root/'game/assets'/name).is_file() for name in ['original/models/catalog.json','original/cards_24/catalog.json','original/campaign/homeworld-runtime.json','library/catalog.json'])
except (OSError,ValueError):valid=False
engine=bundle/'engine'
if valid:os.execv(str(engine),[str(engine),'--path',str(root/'game'),*sys.argv[1:]])
else:os.execv(str(engine),[str(engine),'--path',str(root/'bootstrap'),*(['--headless'] if '--headless' in sys.argv else [])])
