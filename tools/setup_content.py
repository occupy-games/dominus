#!/usr/bin/env python3
"""Download, verify and convert external content into a private runtime folder."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import traceback
import urllib.request

ROOT=Path(__file__).resolve().parents[1]


def status(path,stage,progress,message):
    if not path:return
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_suffix('.tmp')
    temporary.write_text(json.dumps(dict(stage=stage,progress=progress,message=message)))
    temporary.replace(path)


def download(spec,target,report):
    target.parent.mkdir(parents=True,exist_ok=True)
    def verified(path):
        if not path.is_file() or path.stat().st_size!=spec['bytes']:return False
        digest=hashlib.sha1()
        with path.open('rb') as stream:
            for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
        return digest.hexdigest()==spec['sha1']
    if verified(target):return
    temporary=target.with_suffix('.partial')
    if verified(temporary):temporary.replace(target);return
    if temporary.exists() and temporary.stat().st_size>=spec['bytes']:temporary.unlink()
    # Resume only when the server confirms the requested byte range.
    offset=temporary.stat().st_size if temporary.exists() else 0
    request=urllib.request.Request(spec['url'],headers={'Range':f'bytes={offset}-'} if offset else {})
    with urllib.request.urlopen(request,timeout=90) as response:
        if offset and response.status!=206:offset=0
        with temporary.open('ab' if offset else 'wb') as stream:
            while block:=response.read(1024*1024):
                stream.write(block);offset+=len(block)
                report('download',offset/spec['bytes']*.3,f'Downloading content: {offset//1048576} / {spec["bytes"]//1048576} MB')
    if not verified(temporary):
        if temporary.stat().st_size>=spec['bytes']:temporary.unlink()
        raise ValueError('Downloaded content failed its size or checksum check. Retry setup.')
    temporary.replace(target)


def run(command,root,environment,log):
    with log.open('a') as stream:
        stream.write('\n'+str(command[0])+' '+' '.join(map(str,command[1:]))+'\n');stream.flush()
        process=subprocess.Popen(list(map(str,command)),cwd=root,env=environment,stdout=stream,stderr=subprocess.STDOUT)
        try:
            if process.wait():raise subprocess.CalledProcessError(process.returncode,command)
        except BaseException:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:process.kill();process.wait()
            raise


def prepare(root,bundle,report,archive=None,source=None,engine=None):
    spec=json.loads((root/'config/asset_source.json').read_text())
    environment=dict(os.environ)
    environment['PYTHONPATH']=str(root)+os.pathsep+str(root/'tools')
    dependencies=bundle/'dependencies'
    environment['PATH']=str(dependencies/'bin')+os.pathsep+environment.get('PATH','')
    if (dependencies/'etc/ImageMagick-7').is_dir():environment['MAGICK_CONFIGURE_PATH']=str(dependencies/'etc/ImageMagick-7')
    if (dependencies/'modules/coders').is_dir():environment['MAGICK_CODER_MODULE_PATH']=str(dependencies/'modules/coders')
    if (dependencies/'share/cacert.pem').is_file():
        environment['SSL_CERT_FILE']=str(dependencies/'share/cacert.pem')
        os.environ['SSL_CERT_FILE']=environment['SSL_CERT_FILE']
    log=root/'setup.log'
    source=Path(source) if source else root/'data/godus2_4'
    if source.resolve()!=(root/'data/godus2_4').resolve() and not all((source/name).is_file() for name in spec['required']):raise ValueError('The selected content folder is incomplete.')
    if not all((source/name).is_file() for name in spec['required']):
        archive=Path(archive).resolve() if archive else root/'downloads/original.7z'
        download(spec,archive,report)
        report('extract',.32,'Extracting content')
        unpack=root/'data/unpacking'
        if unpack.exists():shutil.rmtree(unpack)
        unpack.mkdir(parents=True)
        seven=dependencies/'bin/7z'
        if not seven.exists():seven=Path(shutil.which('7z') or shutil.which('7zz') or '')
        listing=subprocess.check_output([str(seven),'l','-slt',str(archive)],text=True)
        for line in listing.splitlines():
            if line.startswith('Path = '):
                path=Path(line[7:])
                if line[7:]!=str(archive) and (path.is_absolute() or '..' in path.parts):raise ValueError('Unsafe content path')
            if line.startswith(('Symbolic Link = ','Hard Link = ')):raise ValueError('Linked archive entries are unsupported')
        run([seven,'x','-y',f'-o{unpack}',archive],root,environment,log)
        candidates=[p.parent for p in unpack.rglob(spec['required'][0]) if all((p.parent/name).is_file() for name in spec['required'])]
        if len(candidates)!=1:raise ValueError('The downloaded archive does not contain the expected content files')
        if source.exists():shutil.rmtree(source)
        source.parent.mkdir(parents=True,exist_ok=True);shutil.move(str(candidates[0]),str(source))
        shutil.rmtree(unpack,ignore_errors=True)
    installed=root/'data/godus2_4'
    if source.resolve()!=installed.resolve():
        installed.parent.mkdir(parents=True,exist_ok=True)
        if not installed.exists():installed.symlink_to(source.resolve(),target_is_directory=True)
    ww2ogg=dependencies/'bin/ww2ogg' if (dependencies/'bin/ww2ogg').is_file() else root/'build/reference/ww2ogg-master/ww2ogg'
    revorb=dependencies/'bin/revorb' if (dependencies/'bin/revorb').is_file() else root/'build/reference/revorb'
    codebooks=dependencies/'share/packed_codebooks.bin' if (dependencies/'share/packed_codebooks.bin').is_file() else root/'build/reference/ww2ogg-master/packed_codebooks_aoTuV_603.bin'
    if not ww2ogg.is_file() or not revorb.is_file() or not codebooks.is_file():raise ValueError('Audio conversion tools are missing. Use the macOS installer, or build the tools described in docs/ORIGINAL_ASSETS.md.')
    if not shutil.which('magick',path=environment['PATH']):raise ValueError('ImageMagick is required to prepare card artwork. Use the macOS installer or install the development conversion tools.')
    steps=[('assets.py',['inventory']),('assets.py',['extract']),('assets.py',['library']),
           ('original_assets.py',['--ww2ogg',str(ww2ogg),'--revorb',str(revorb),'--codebooks',str(codebooks)]),
           ('models.py',[]),('campaign.py',[]),('current_cards.py',[]),('campaign_rules.py',[]),
           ('building_info.py',[]),('tree_imposters.py',[]),('adventures.py',[])]
    for index,(script,args) in enumerate(steps):
        report('convert',.4+.48*index/len(steps),f'Preparing content ({index+1}/{len(steps)})')
        run([sys.executable,root/'tools'/script,*args],root,environment,log)
    # Pure metadata recoveries read source tables/instructions; no original
    # executable is ever launched by content setup.
    for module in ['temple_repair','temple_sites','temple_terrain','temple_membership','storm_chests']:
        run([sys.executable,'-m','tools.'+module],root,environment,log)
    report('import',.9,'Preparing graphics and audio for first launch')
    engine=Path(engine) if engine else (bundle/'engine' if (bundle/'engine').is_file() else Path(shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'))
    run([engine,'--headless','--path',root/'game','--editor','--import','--log-file',root/'import.log'],root,environment,log)
    imported=(root/'import.log').read_text(errors='replace')
    # A fresh Godot project initializes its custom editor font before its
    # first import. That one pre-import lookup is transient; the subsequent
    # real game startup below must load every resource without any such error.
    imported=imported.replace('ERROR: No loader found for resource: res://assets/fonts/RobotoCondensed-Regular.ttf (expected type: unknown)','')
    if any(s in imported for s in ['SCRIPT ERROR:','ERROR: Failed to load','ERROR: No loader found']):raise ValueError('Content import failed. See import.log.')
    report('validate',.98,'Checking the prepared game')
    checked=dict(environment,DOMINUS_SAVE_DIRECTORY=str(root/'setup-check-profile'),DOMINUS_PYTHON=sys.executable)
    run([engine,'--headless','--path',root/'game','--quit-after','8','--log-file',root/'content-check.log','--','--play'],root,checked,log)
    verified=(root/'content-check.log').read_text(errors='replace')
    if any(s in verified for s in ['SCRIPT ERROR:','ERROR: Failed to load','ERROR: No loader found']):raise ValueError('Prepared game could not start. See content-check.log.')
    recipe=json.loads((bundle/'content-recipe.json').read_text()).get('sha256','') if (bundle/'content-recipe.json').exists() else ''
    (root/'content-ready.json').write_text(json.dumps({'version':1,'source_sha1':spec['sha1'],'recipe_sha256':recipe}))
    report('ready',1,'Ready')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=ROOT);parser.add_argument('--bundle',type=Path,default=ROOT)
    parser.add_argument('--status',type=Path);parser.add_argument('--archive',type=Path);parser.add_argument('--source',type=Path);parser.add_argument('--engine',type=Path)
    parser.add_argument('--stop',type=int)
    args=parser.parse_args()
    if args.stop:
        try:os.kill(args.stop,signal.SIGTERM)
        except ProcessLookupError:pass
        return
    def interrupted(_signal,_frame):raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM,interrupted)
    report=lambda stage,progress,message:status(args.status,stage,progress,message)
    try:
        args.root.mkdir(parents=True,exist_ok=True)
        with (args.root/'setup.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            prepare(args.root.resolve(),args.bundle.resolve(),report,args.archive,args.source,args.engine)
    except KeyboardInterrupt:
        report('error',0,'Setup interrupted. Retry to resume the download and prepare content.');raise SystemExit(130)
    except Exception as error:
        with (args.root/'setup.log').open('a') as stream:traceback.print_exc(file=stream)
        message=str(error) if isinstance(error,ValueError) else 'Content setup stopped. Retry setup; details are in setup.log.'
        report('error',0,message);raise


if __name__=='__main__':main()
