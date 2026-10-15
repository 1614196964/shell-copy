#!/usr/bin/env python3
"""Validate the generated feed and archive with Sparkle's own signature verifier."""
import base64
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def verify(feed, app, archive):
    root = Path(__file__).resolve().parent.parent
    tools = root / '.build/artifacts/sparkle/Sparkle/bin'
    with (app / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    key = info['SUPublicEDKey']
    account = 'local.shell-copy.app.sparkle'
    signing_key = subprocess.check_output(
        [str(tools / 'generate_keys'), '--account', account, '-p'], text=True).strip()
    assert signing_key == key, 'Signing key must match the public key embedded in the app'
    subprocess.run([str(tools / 'sign_update'), '--account', account, '--verify', str(feed)], check=True)
    ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    items = ET.parse(feed).findall('channel/item')
    assert len(items) == 1, 'Expected one release per feed'
    item = items[0]
    assert item.findtext('s:version', namespaces=ns) == info['CFBundleVersion']
    version = info['CFBundleShortVersionString']
    assert item.findtext('s:shortVersionString', namespaces=ns) == version
    enclosure = item.find('enclosure')
    assert enclosure is not None, 'Feed must install an archive, not just open a website'
    expected = f'https://github.com/doriansu/shell-copy/releases/download/v{version}/{archive.name}'
    assert enclosure.attrib['url'] == expected
    assert int(enclosure.attrib['length']) == archive.stat().st_size
    signature = enclosure.attrib['{' + ns['s'] + '}edSignature']
    assert len(base64.b64decode(signature, validate=True)) == 64
    subprocess.run([str(tools / 'sign_update'), '--account', account, '--verify', str(archive), signature], check=True)
    print('Verified signed feed, version, download URL, archive size and archive signature.')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit('Usage: verify-release.py appcast.xml App.app App.zip')
    verify(*(Path(p).resolve() for p in sys.argv[1:]))
