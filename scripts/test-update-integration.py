#!/usr/bin/env python3
"""Exercise the real Sparkle installer using disposable apps and loopback HTTP."""
import functools
import http.server
import plistlib
import re
import subprocess
import sys
import tempfile
import threading
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'


def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def main():
    app = ROOT / 'build/Shell Copy.app'
    assert app.exists(), 'Build the app first'
    # A Documents directory can trigger TCC prompts in Sparkle's separate installer process.
    work = Path(tempfile.mkdtemp(prefix='shell-copy-update-test-'))
    driver_app = work / 'Test Driver.app'
    (driver_app / 'Contents/MacOS').mkdir(parents=True)
    driver = driver_app / 'Contents/MacOS/driver'
    with (driver_app / 'Contents/Info.plist').open('wb') as f:
        plistlib.dump(dict(CFBundleIdentifier='local.shell-copy.update-driver.' + uuid.uuid4().hex,
                          CFBundleExecutable='driver', CFBundleName='Update Integration Driver',
                          CFBundleVersion='1', CFBundlePackageType='APPL', LSUIElement=True), f)
    run('swiftc', ROOT / 'Tests/UpdateIntegration/main.swift', '-module-cache-path', ROOT / '.build/module-cache',
        '-F', app / 'Contents/Frameworks', '-framework', 'Sparkle', '-Xlinker', '-rpath',
        '-Xlinker', app / 'Contents/Frameworks', '-o', driver)
    run('codesign', '--force', '--sign', '-', driver_app)
    key = work / 'test-key.txt'
    public_key = subprocess.check_output([str(driver), '--generate-test-key', str(key)], text=True).strip()
    downloads = work / 'downloads'
    downloads.mkdir()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(downloads))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f'http://127.0.0.1:{server.server_port}/'
    identifier = 'local.shell-copy.update-test.' + uuid.uuid4().hex

    def make_app(destination, build):
        run('ditto', app, destination)
        path = destination / 'Contents/Info.plist'
        with path.open('rb') as f:
            info = plistlib.load(f)
        info.update(CFBundleIdentifier=identifier, CFBundleName='Shell Copy Update Test',
                    CFBundleDisplayName='Shell Copy Update Test', CFBundleVersion=str(build),
                    CFBundleShortVersionString=f'0.0.{build}', SUFeedURL=url + 'appcast.xml',
                    SUPublicEDKey=public_key, SUEnableAutomaticChecks=build == 1,
                    NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
        with path.open('wb') as f:
            plistlib.dump(info, f)
        run('codesign', '--force', '--sign', '-', destination)

    try:
        old = work / 'installed/Shell Copy Update Test.app'
        new = work / 'new/Shell Copy Update Test.app'
        make_app(old, 1)
        make_app(new, 2)
        archive = downloads / 'ShellCopy-0.0.2.zip'
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', new, archive)
        run(TOOLS / 'generate_appcast', '--ed-key-file', key, '--download-url-prefix', url,
            '--maximum-deltas', '0', downloads)
        feed = downloads / 'appcast.xml'
        signed_feed = feed.read_bytes()
        signed_archive = archive.read_bytes()
        if '--ui' in sys.argv:
            run('open', '-n', old)
            print(f'UI test app: {old}\nBundle ID: {identifier}\nStop with Ctrl-C.', flush=True)
            threading.Event().wait()

        def check(mode, expected_version):
            result = work / f'{mode}.result'
            log = work / f'{mode}.log'
            run('open', '-W', '-n', '--stdout', log, '--stderr', log, driver_app,
                '--args', old, mode, result, timeout=75)
            print(log.read_text() if log.exists() else 'No driver log')
            assert result.exists() and result.read_text() == '0', f'{mode} failed: {work}'
            with (old / 'Contents/Info.plist').open('rb') as f:
                assert plistlib.load(f)['CFBundleVersion'] == expected_version

        check('auto-dismiss', '1')
        check('dismiss', '1')
        check('cancel-download', '1')
        feed.write_bytes(signed_feed.replace(b'<title>', b'<title>TAMPERED ', 1))
        check('bad-feed', '1')
        feed.write_bytes(signed_feed)
        archive.write_bytes(signed_archive[:-1] + bytes([signed_archive[-1] ^ 1]))
        check('bad-archive', '1')
        archive.write_bytes(signed_archive)
        # Launch the isolated copy so the real installer must terminate and relaunch it.
        run('open', '-n', old)
        check('install', '2')
        check('current', '2')
        feed.rename(downloads / 'unavailable.xml')
        check('error', '2')
        print('PASS: automatic check, dismiss, download cancellation, signed-feed rejection, archive rejection, '
              'install/relaunch, current-version and unavailable-feed paths.')
        print(f'Test artifacts: {work}')
    finally:
        server.shutdown()
        server.server_close()
        # Only terminate the uniquely identified test instance, never the real Shell Copy.
        subprocess.run(['pkill', '-f', re.escape(str(work / 'installed')) + '/'], check=False)
        subprocess.run(['pkill', '-f', re.escape(str(driver))], check=False)
        key.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
