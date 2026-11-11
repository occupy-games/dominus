#!/usr/bin/env python3
"""Build a self-contained, external-content-free macOS application and installer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
MAGIC={b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'}


def execute(*args):subprocess.run(list(map(str,args)),check=True,stdout=subprocess.DEVNULL)


def macho(path):
    try:
        with path.open('rb') as stream:return stream.read(4) in MAGIC
    except OSError:return False


def minimum_macos(resources):
    versions=[(14,0)]
    for binary in resources.rglob('*'):
        if not binary.is_file() or not macho(binary):continue
        metadata=subprocess.check_output(['otool','-l',str(binary)],text=True)
        for command in metadata.split('Load command '):
            if 'cmd LC_BUILD_VERSION\n' in command:
                match=re.search(r'\bminos\s+(\d+(?:\.\d+)+)',command)
            elif 'cmd LC_VERSION_MIN_MACOSX\n' in command:
                match=re.search(r'\bversion\s+(\d+(?:\.\d+)+)',command)
            else:continue
            if match:versions.append(tuple(map(int,match[1].split('.'))))
    return '.'.join(map(str,max(versions)))


def relocate(resources,mapping):
    libraries=resources/'dependencies/lib';libraries.mkdir(parents=True,exist_ok=True)
    queue=[p for p in resources.rglob('*') if p.is_file() and macho(p)]
    visited=set()
    while queue:
        binary=queue.pop()
        if binary in visited:continue
        visited.add(binary)
        binary.chmod(binary.stat().st_mode|0o200)
        dependencies=subprocess.check_output(['otool','-L',str(binary)],text=True).splitlines()[1:]
        for line in dependencies:
            original=line.strip().split(' (',1)[0]
            if original.startswith(('/System/','/usr/lib/','@')):continue
            source=Path(original).resolve()
            if source not in mapping:
                if not source.is_file():raise ValueError('Missing runtime dependency: '+original)
                target=libraries/source.name
                if target.exists() and target.read_bytes()!=source.read_bytes():raise ValueError('Conflicting runtime library: '+source.name)
                shutil.copy2(source,target);mapping[source]=target;queue.append(target)
            target=mapping[source]
            relative='@loader_path/'+os.path.relpath(target,binary.parent)
            execute('/usr/bin/install_name_tool','-change',original,relative,binary)
        identifiers=subprocess.check_output(['otool','-D',str(binary)],text=True).splitlines()[1:]
        if identifiers:execute('/usr/bin/install_name_tool','-id','@loader_path/'+binary.name,binary)
    for binary in sorted(visited):execute('/usr/bin/codesign','--force','--sign','-','--timestamp=none',binary)
    # No runtime binary may reach back into this development machine.
    for binary in visited:
        text='\n'.join(subprocess.check_output(['otool','-L',str(binary)],text=True).splitlines()[1:])
        if '/opt/' in text or '/Users/' in text:raise ValueError('Nonrelocatable runtime: '+str(binary))


def copy_project(source, resources):
    def ignores(folder, names):
        excluded = {name for name in names
                    if name in {'.DS_Store', '.godot', '__pycache__', 'tests'}
                    or name.endswith(('.pyc', '.import'))}
        if Path(folder) == source / 'game/assets':
            excluded.update({'extracted', 'library', 'original'})
        return excluded

    for name in ('game', 'tools', 'assets', 'config', 'bootstrap'):
        target = resources / name
        if target.exists():
            shutil.rmtree(target)
    for name in ('game', 'tools', 'assets'):
        shutil.copytree(source / name, resources / name, ignore=ignores)
    recipe = hashlib.sha256()
    for path in sorted((resources / 'tools').glob('*.py')):
        recipe.update(path.name.encode())
        recipe.update(path.read_bytes())
    recipe.update((resources / 'assets/selection.json').read_bytes())
    (resources / 'content-recipe.json').write_text(json.dumps({'sha256': recipe.hexdigest()}))
    (resources / 'config').mkdir()
    for name in ('settings.defaults.json', 'asset_source.json', 'Adobes.csv', 'Followers.csv', 'Update.csv'):
        shutil.copy2(source / 'config' / name, resources / 'config' / name)
    bootstrap = resources / 'bootstrap'
    shutil.copytree(source / 'packaging/bootstrap', bootstrap, ignore=ignores)
    shutil.copy2(source / 'game/presentation/menu/content_setup.gd', bootstrap / 'setup.gd')
    (bootstrap / 'infrastructure').mkdir(exist_ok=True)
    shutil.copy2(source / 'game/infrastructure/content_setup.gd', bootstrap / 'infrastructure/content_setup.gd')
    shutil.copy2(source / 'game/assets/fonts/RobotoCondensed-Regular.ttf', bootstrap / 'RobotoCondensed-Regular.ttf')
    shutil.copy2(source / 'game/assets/dominus.icns', resources / 'Dominus.icns')


def package_app(stage, app, output, version, commit=None):
    resources = app / 'Contents/Resources'
    minimum_system = minimum_macos(resources)
    info = dict(CFBundleName='Dominus', CFBundleDisplayName='Dominus', CFBundleIdentifier='com.dominus.game',
                CFBundleExecutable='Dominus', CFBundlePackageType='APPL', CFBundleShortVersionString=version,
                CFBundleVersion=version, CFBundleIconFile='Dominus.icns', LSMinimumSystemVersion=minimum_system,
                NSHighResolutionCapable=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    bootstrap = resources / 'bootstrap'
    execute(resources / 'engine', '--headless', '--path', bootstrap, '--editor', '--import',
            '--log-file', stage / 'bootstrap-import.log')
    check = subprocess.run([resources / 'engine', '--headless', '--path', bootstrap, '--script', 'res://setup.gd',
                            '--check-only', '--log-file', stage / 'bootstrap-check.log'],
                           check=True, text=True, capture_output=True)
    for error in ('SCRIPT ERROR:', 'No loader found', 'Failed to load'):
        if error in check.stdout + check.stderr:
            raise ValueError('Invalid setup project:\n' + check.stdout + check.stderr)
    execute('/usr/bin/codesign', '--force', '--deep', '--sign', '-', '--timestamp=none', app)
    execute('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    output.mkdir(parents=True, exist_ok=True)
    package = output / f'Dominus-{version}-arm64.pkg'
    execute('pkgbuild', '--root', stage / 'payload', '--identifier', 'com.dominus.game',
            '--version', version, '--install-location', '/', package)
    entries = subprocess.check_output(['pkgutil', '--payload-files', package], text=True).splitlines()
    external = ('game/assets/original', 'game/assets/extracted', 'game/assets/library', 'data', 'saves')
    for entry in entries:
        path = entry.partition('/Contents/Resources/')[2].rstrip('/')
        if entry.endswith(('.7z', '.sqlite3')) or any(path == name or path.startswith(name + '/') for name in external):
            raise ValueError('External data in installer: ' + entry)
    with package.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    manifest = dict(package=package.name, bytes=package.stat().st_size, sha256=digest, external_content_included=False,
                    architecture='arm64', minimum_macos=minimum_system, installer_signed=False,
                    application_signature='ad-hoc', version=version)
    if commit:
        manifest['source_commit'] = commit
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2), flush=True)
    return app, package


def build_from_runtime(runtime_package, source, output, version, commit):
    with tempfile.TemporaryDirectory(prefix='dominus-package-') as directory:
        stage = Path(directory)
        expanded = stage / 'runtime'
        execute('pkgutil', '--expand-full', runtime_package, expanded)
        applications = stage / 'payload/Applications'
        applications.mkdir(parents=True)
        app = applications / 'Dominus.app'
        shutil.move(expanded / 'Payload/Applications/Dominus.app', app)
        copy_project(source.resolve(), app / 'Contents/Resources')
        return package_app(stage, app, output, version, commit)[1]


def build(output,version):
    source_specs=json.loads((ROOT/'config/distribution_sources.json').read_text())
    source_cache=ROOT/'build/reference/sources';source_cache.mkdir(parents=True,exist_ok=True)
    for spec in source_specs['sources']:
        if Path(spec['name']).name!=spec['name']:raise ValueError('Invalid dependency source name')
        target=source_cache/spec['name']
        if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest()==spec['sha256']:continue
        data=urllib.request.urlopen(spec['url'],timeout=60).read()
        if hashlib.sha256(data).hexdigest()!=spec['sha256']:raise ValueError('Dependency source checksum mismatch')
        target.write_bytes(data)
    stage=ROOT/'build/distribution'
    if stage.exists():shutil.rmtree(stage,ignore_errors=True)
    app=stage/'payload/Applications/Dominus.app'
    resources=app/'Contents/Resources';macos=app/'Contents/MacOS'
    resources.mkdir(parents=True,exist_ok=True);macos.mkdir(exist_ok=True)
    copy_project(ROOT, resources)
    shutil.copy2('/Applications/Godot.app/Contents/MacOS/Godot',resources/'engine')
    dependencies=resources/'dependencies'
    (dependencies/'bin').mkdir(parents=True);(dependencies/'share').mkdir()
    mapping={}
    python_prefix=Path(subprocess.check_output(['/opt/homebrew/bin/python3','-c','import sys;print(sys.prefix)'],text=True).strip()).resolve()
    python=resources/'python'
    shutil.copytree(python_prefix,python,ignore=shutil.ignore_patterns('__pycache__','site-packages','test','tests','idlelib','tkinter','turtledemo','Headers','Resources','share','include','_tkinter*'))
    for source in python_prefix.rglob('*'):
        target=python/source.relative_to(python_prefix)
        if source.is_file() and target.is_file() and macho(source):mapping[source.resolve()]=target
    # The framework's bin entry is an app launcher with an absolute fallback.
    # Bundle the actual interpreter, so it never spawns a development path.
    executable=python_prefix/'Resources/Python.app/Contents/MacOS/Python'
    shutil.copy2(executable,python/'bin/python3')
    inputs={'7z':Path('/opt/local/lib/p7zip/7z'),'ww2ogg':ROOT/'build/reference/ww2ogg-master/ww2ogg',
            'revorb':ROOT/'build/reference/revorb','magick':Path('/opt/homebrew/bin/magick').resolve()}
    for name,source in inputs.items():
        target=dependencies/'bin'/name;shutil.copy2(source,target);mapping[source.resolve()]=target
    shutil.copy2('/opt/local/lib/p7zip/7z.so',dependencies/'bin/7z.so')
    shutil.copy2(ROOT/'build/reference/ww2ogg-master/packed_codebooks_aoTuV_603.bin',dependencies/'share/packed_codebooks.bin')
    shutil.copy2('/etc/ssl/cert.pem',dependencies/'share/cacert.pem')
    image_prefix=inputs['magick'].parents[1]
    shutil.copytree(image_prefix/'etc/ImageMagick-7',dependencies/'etc/ImageMagick-7')
    modules=next((image_prefix/'lib/ImageMagick').glob('modules-*/coders'))
    (dependencies/'modules/coders').mkdir(parents=True)
    for name in ['png.so','tga.so']:
        shutil.copy2(modules/name,dependencies/'modules/coders'/name)
    for name in ['png','tga']:
        (dependencies/'modules/coders'/(name+'.la')).write_text("# libtool library file\ndlname='%s.so'\nlibrary_names='%s.so'\nold_library=''\ndependency_libs=''\ninstalled=yes\nshouldnotlink=yes\ndlopen=''\ndlpreopen=''\nlibdir=''\n"%(name,name))
    relocate(resources,mapping)
    launcher=macos/'Dominus'
    launcher.write_text('#!/bin/sh\nset -eu\nunset PYTHONHOME PYTHONPATH\nexport PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1\nRES="$(CDPATH= cd -- "$(dirname -- "$0")/../Resources" && pwd)"\nexec "$RES/python/bin/python3" "$RES/tools/launch_distribution.py" "$@"\n')
    launcher.chmod(0o755)
    license_dir=resources/'licenses';license_dir.mkdir()
    license_sources=[Path('/Applications/Godot.app/Contents/Resources'),python_prefix, image_prefix,
                     ROOT/'build/reference/ww2ogg-master',ROOT/'build/reference/revorb-master',Path('/opt/local/share/doc/p7zip')]
    for index,folder in enumerate(license_sources):
        if not folder.exists():continue
        for pattern in ['*LICENSE*','*License*','*COPYING*','*copyright*']:
            for source in folder.glob(pattern):
                if source.is_file():shutil.copy2(source,license_dir/f'{index}-{source.name}')
    origins=[python_prefix, image_prefix,*mapping.keys()]
    prefixes=set()
    for origin in origins:
        for parent in [origin,*origin.parents]:
            if parent.parent.parent.name=='Cellar':prefixes.add(parent);break
    for prefix in prefixes:
        destination=license_dir/prefix.parent.name
        for path in prefix.rglob('*'):
            if not path.is_file() or not path.name.lower().startswith(('license','copying','copyright','notice')) or 'site-packages' in path.parts:continue
            target=destination/path.relative_to(prefix);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    shutil.copytree('/opt/local/share/doc/p7zip/DOC',license_dir/'archive-tool',ignore=shutil.ignore_patterns('MANUAL','*.css','*.htm'))
    for name in ['revorb.cpp','revorb_main.cpp']:
        source=ROOT/'build/reference'/name
        if source.exists():shutil.copy2(source,license_dir/name)
    sources=ROOT/'build/reference/sources'
    if sources.is_dir():shutil.copytree(sources,license_dir/'sources')
    shutil.copy2(ROOT/'config/distribution_sources.json',license_dir/'sources/manifest.json')
    formula=Path('/opt/homebrew/Cellar/libtool/2.6.2/.brew/libtool.rb')
    if formula.exists():shutil.copy2(formula,license_dir/'libtool-build-recipe.rb')
    execute(resources/'engine','--headless','--path',resources/'bootstrap','--script',ROOT/'tools/export_engine_licenses.gd','--check-only','--log-file',stage/'license-parse.log')
    execute(resources/'engine','--headless','--path',resources/'bootstrap','--script',ROOT/'tools/export_engine_licenses.gd','--log-file',stage/'license-export.log','--',license_dir/'engine')
    (license_dir/'COMPONENTS.txt').write_text('Dominus bundles the Godot engine, CPython, 7-Zip, ImageMagick, ww2ogg and revorb and their dynamically linked open-source runtime dependencies. External game content is downloaded separately and is not part of this installer.\n')
    return package_app(stage, app, output, version)


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--version', default='0.1.1')
    args = parser.parse_args()
    build(args.output, args.version)
