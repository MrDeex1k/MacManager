#!/usr/bin/env python3
"""Install a local build with a stable certificate identity, without touching user data."""
import argparse
import datetime
import os
import pathlib
import plistlib
import signal
import subprocess
import time
import uuid


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True)


def metadata(path):
    with (path / 'Contents/Info.plist').open('rb') as file:
        return plistlib.load(file)


def signature(path):
    result = run('/usr/bin/codesign', '-d', '-r-', '--verbose=4', str(path))
    details = result.stderr + result.stdout
    requirement = next((line for line in details.splitlines() if 'designated =>' in line), None)
    return details, requirement


def install(source, destination, identity, adopt_certificate=False, entitlements=None):
    if identity == '-':
        raise ValueError('Ad hoc signatures are not allowed for installed builds.')
    source = source.resolve(strict=True)
    source_info = metadata(source)
    old_signature = None
    if destination.exists():
        old_info = metadata(destination)
        if old_info['CFBundleIdentifier'] != source_info['CFBundleIdentifier']:
            raise ValueError('Bundle identifier differs; refusing to switch the preferences/TCC domain.')
        old_signature = signature(destination)
    staging = destination.parent / ('.MacManager-update-' + str(uuid.uuid4()) + '.app')
    backup = None
    try:
        run('/usr/bin/ditto', str(source), str(staging))
        # Preserve existing entitlements, but require a real certificate and Hardened Runtime.
        signing = ['/usr/bin/codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp=none']
        if entitlements is not None:
            entitlements = entitlements.resolve(strict=True)
            with entitlements.open('rb') as file:
                plistlib.load(file)  # Validate before closing the installed application.
            signing.extend(['--entitlements', str(entitlements)])
        else:
            signing.append('--preserve-metadata=entitlements')
        run(*signing, str(staging))
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(staging))
        new_details, new_requirement = signature(staging)
        if 'Authority=Developer ID Application:' not in new_details and 'Authority=Apple Development:' not in new_details:
            raise ValueError('A Developer ID or Apple Development certificate is required.')
        if not new_requirement or 'anchor apple' not in new_requirement:
            raise ValueError('Missing certificate-backed designated requirement.')
        if old_signature:
            old_details, old_requirement = old_signature
            if 'Signature=adhoc' in old_details:
                if not adopt_certificate:
                    raise ValueError('One-time ad hoc migration requires --adopt-certificate; TCC may require renewed consent.')
            elif old_requirement != new_requirement:
                raise ValueError('Signing identity differs from the installed app; refusing replacement.')

        executable = str(destination / 'Contents/MacOS' / source_info['CFBundleExecutable'])
        processes = run('/bin/ps', '-axo', 'pid=,command=').stdout.splitlines()
        for line in processes:
            parts = line.strip().split(None, 1)
            if len(parts) != 2 or parts[1] != executable:
                continue
            pid = int(parts[0])
            os.kill(pid, signal.SIGTERM)
            for _ in range(100):
                result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True)
                if result.stdout.strip() != executable:
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError('Installed app did not exit; refusing replacement.')

        if destination.exists():
            stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
            backup = pathlib.Path.home() / '.Trash' / ('MacManager-backup-' + stamp + '-' + uuid.uuid4().hex[:8] + '.app')
            destination.rename(backup)
        try:
            staging.rename(destination)
        except OSError:
            if backup is not None:
                backup.rename(destination)
            raise
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(destination))
        run('/usr/bin/open', '-n', str(destination))
        print('Installed and launched:', destination)
        print('Bundle ID:', source_info['CFBundleIdentifier'])
        print(new_requirement)
        if backup is not None:
            print('Recoverable previous app:', backup)
        print('UserDefaults, Keychain, Application Support and TCC were not modified.')
    finally:
        # Only remove our own failed staging copy, never a user installation or its data.
        if staging.exists():
            import shutil
            shutil.rmtree(staging)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=pathlib.Path)
    parser.add_argument('--identity', required=True, help='Same certificate name or hash for every installation.')
    parser.add_argument('--destination', type=pathlib.Path, default=pathlib.Path('/Applications/MacManager.app'))
    parser.add_argument('--adopt-certificate', action='store_true', help='One-time replacement of an ad hoc signature.')
    project_entitlements = pathlib.Path(__file__).resolve().parents[1] / 'MacManager/MacManager.entitlements'
    parser.add_argument('--entitlements', type=pathlib.Path, default=project_entitlements if project_entitlements.exists() else None,
                        help='Project entitlements, also used when Xcode built with CODE_SIGNING_ALLOWED=NO.')
    args = parser.parse_args()
    install(args.source, args.destination, args.identity, args.adopt_certificate, args.entitlements)
