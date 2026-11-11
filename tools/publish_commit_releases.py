#!/usr/bin/env python3
"""Build and publish an installer for each main-branch commit since Dominus 0.1.1."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

from package_macos import build_from_runtime


FIRST_RELEASE_COMMIT = 'b23d2689d472709312fb2a49bb50175fdfe7a582'
RUNTIME_TAG = 'v0.1.0'
RUNTIME_PACKAGE = 'Dominus-0.1.0-arm64.pkg'
RUNTIME_SHA256 = '679d3f2eb9687f4ecd1b77eaf43cf59dbd8b1cc91c3c4082f05bd5b6735d739c'


def capture(*command):
    return subprocess.check_output(command, text=True).strip()


def run(*command, cwd=None):
    subprocess.run(command, cwd=cwd, check=True)


def download_runtime(repository, directory):
    run('gh', 'release', 'download', RUNTIME_TAG, '--repo', repository,
        '--pattern', RUNTIME_PACKAGE, '--dir', directory)
    package = directory / RUNTIME_PACKAGE
    with package.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != RUNTIME_SHA256:
            raise ValueError(f'{RUNTIME_PACKAGE} failed its checksum check.')
    return package


def publish(repository, commit, version, draft, tag_exists, latest, directory, runtime):
    source = directory / 'source'
    source.mkdir()
    archive = directory / 'source.tar'
    run('git', 'archive', '--format=tar', '--output', archive, commit)
    run('tar', '-xf', archive, '-C', source)
    run(sys.executable, 'tools/check_architecture.py', cwd=source)
    run(sys.executable, '-m', 'unittest', 'tests.test_distribution', cwd=source)
    output = directory / 'installer'
    package = build_from_runtime(runtime, source, output, version, commit)
    manifest_file = output / 'manifest.json'
    manifest = json.loads(manifest_file.read_text())
    tag = 'v' + version
    if not draft:
        notes = directory / 'release-notes.md'
        notes.write_text(
            f'Built from commit `{commit}` by GitHub Actions.\n\n'
            f'Apple Silicon installer for macOS {manifest["minimum_macos"]} or later. '
            'The first launch downloads the original game assets separately. '
            'The installer is unsigned.\n'
        )
        target = ['--verify-tag'] if tag_exists else ['--target', commit]
        run('gh', 'release', 'create', tag, '--repo', repository, '--draft',
            '--title', f'Dominus {version}', '--notes-file', notes, *target)
    run('gh', 'release', 'upload', tag, package, manifest_file, '--repo', repository, '--clobber')
    run('gh', 'release', 'edit', tag, '--repo', repository, '--draft=false',
        '--latest=true' if latest else '--latest=false')


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    head = os.environ['GITHUB_SHA']
    commits = capture('git', 'rev-list', '--first-parent', '--reverse',
                      f'{FIRST_RELEASE_COMMIT}^..{head}').splitlines()
    if not commits or commits[0] != FIRST_RELEASE_COMMIT:
        raise ValueError('The main branch does not contain the Dominus 0.1.1 release commit.')
    pages = json.loads(capture('gh', 'api', '--paginate', '--slurp',
                               f'repos/{repository}/releases?per_page=100'))
    releases = {release['tag_name']: release for page in pages for release in page}
    tags = {}
    for line in capture('git', 'for-each-ref', '--format=%(refname:strip=2) %(objectname) %(*objectname)',
                        'refs/tags').splitlines():
        name, commit, *peeled = line.split()
        tags[name] = peeled[0] if peeled else commit

    published = [int(tag[5:]) for tag, release in releases.items()
                 if tag.startswith('v0.1.') and tag[5:].isdigit() and not release['draft']]
    latest = max(published, default=0)
    failures = []
    with TemporaryDirectory(prefix='dominus-releases-') as directory:
        directory = Path(directory)
        runtime = None
        for index, commit in enumerate(commits, 1):
            version = f'0.1.{index}'
            tag = 'v' + version
            release = releases.get(tag)
            tag_commit = tags.get(tag)
            try:
                if tag_commit and tag_commit != commit:
                    raise ValueError(f'{tag} points to {tag_commit}, expected {commit}.')
                if release and not release['draft']:
                    assets = {asset['name'] for asset in release['assets'] if asset['state'] == 'uploaded'}
                    if tag_commit != commit or not {f'Dominus-{version}-arm64.pkg', 'manifest.json'} <= assets:
                        raise ValueError(f'{tag} is missing the expected commit or release assets.')
                    continue
                if release and (f'Built from commit `{commit}` by GitHub Actions.' not in (release.get('body') or '')
                                or (not tag_commit and release['target_commitish'] != commit)):
                    raise ValueError(f'{tag} already has a draft for a different build.')
                if runtime is None:
                    runtime = download_runtime(repository, directory)
                print(f'Publishing {tag} from {commit}', flush=True)
                with TemporaryDirectory(prefix=f'{tag}-', dir=directory) as release_directory:
                    publish(repository, commit, version, bool(release), bool(tag_commit), index >= latest,
                            Path(release_directory), runtime)
                latest = max(latest, index)
            except (OSError, ValueError, subprocess.CalledProcessError) as error:
                print(f'{tag}: {error}', file=sys.stderr, flush=True)
                failures.append(tag)
    if failures:
        raise SystemExit('Failed to publish ' + ', '.join(failures))


if __name__ == '__main__':
    main()
