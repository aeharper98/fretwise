#!/usr/bin/env python3
"""App Store Connect API helper for the TestFlight workflow.

    asc.py icloud BUNDLE_ID     turn on iCloud (key-value storage) for the app's identifier
    asc.py macos BUNDLE_ID      say whether the app record has a macOS version yet

Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file). Standard library plus the
openssl command line, so the runner needs no packages.
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

API = 'https://api.appstoreconnect.apple.com/v1'


def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode()


def der_to_raw(der):
    """ECDSA signature from DER (SEQUENCE of two INTEGERs) to the 64-byte r||s form JWTs use."""
    if der[0] != 0x30:
        raise ValueError('not a DER signature')
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7f)
    out = b''
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError('bad DER integer')
        n = der[i + 1]
        out += der[i + 2:i + 2 + n].lstrip(b'\x00').rjust(32, b'\x00')
        i += 2 + n
    return out


def token():
    head = b64(json.dumps({'alg': 'ES256', 'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'}).encode())
    now = int(time.time())
    body = b64(json.dumps({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1100,
                           'aud': 'appstoreconnect-v1'}).encode())
    msg = f'{head}.{body}'.encode()
    der = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', os.environ['ASC_KEY_PATH']],
                         input=msg, capture_output=True, check=True).stdout
    return f'{head}.{body}.{b64(der_to_raw(der))}'


TOKEN = None


def call(method, path, body=None):
    global TOKEN
    TOKEN = TOKEN or token()
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': 'Bearer ' + TOKEN, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {'raw': raw.decode(errors='replace')}


def errors(r):
    return '; '.join(f"{e.get('title', '')}: {e.get('detail', '')}" for e in r.get('errors', [])) or json.dumps(r)[:400]


def bundle_id(identifier):
    q = urllib.parse.urlencode({'filter[identifier]': identifier, 'limit': 200})
    st, r = call('GET', f'/bundleIds?{q}')
    if st != 200:
        sys.exit(f'::error::Could not read app identifiers ({st}): {errors(r)}')
    for d in r.get('data', []):
        if d['attributes']['identifier'] == identifier:
            return d
    sys.exit(f'::error::No app identifier {identifier} in this team.')


def icloud(identifier):
    b = bundle_id(identifier)
    print(f"App ID {identifier}: platform {b['attributes'].get('platform')}")
    st, r = call('GET', f"/bundleIds/{b['id']}/bundleIdCapabilities")
    if st != 200:
        sys.exit(f'::error::Could not read capabilities ({st}): {errors(r)}')
    have = sorted(d['attributes']['capabilityType'] for d in r.get('data', []))
    print('Capabilities:', ', '.join(have) or 'none')
    if 'ICLOUD' in have:
        print('iCloud is already on.')
        return
    body = {'data': {'type': 'bundleIdCapabilities',
                     'attributes': {'capabilityType': 'ICLOUD',
                                    'settings': [{'key': 'ICLOUD_VERSION', 'options': [{'key': 'XCODE_6'}]}]},
                     'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': b['id']}}}}}
    st, r = call('POST', '/bundleIdCapabilities', body)
    if st not in (200, 201):
        # the iPhone and Mac jobs run at once; the other one may have just turned it on
        st2, r2 = call('GET', f"/bundleIds/{b['id']}/bundleIdCapabilities")
        if st2 == 200 and any(d['attributes']['capabilityType'] == 'ICLOUD' for d in r2.get('data', [])):
            print('iCloud is on.')
            return
        sys.exit(f'::error::Could not turn on iCloud for {identifier} ({st}): {errors(r)}. '
                 'Turn it on by hand: developer.apple.com > Certificates, Identifiers & Profiles > Identifiers > '
                 f'{identifier} > iCloud.')
    print('Turned on iCloud (key-value storage) for', identifier)


def macos(identifier):
    q = urllib.parse.urlencode({'filter[bundleId]': identifier})
    st, r = call('GET', f'/apps?{q}')
    apps = [a for a in r.get('data', []) if a['attributes'].get('bundleId') == identifier] if st == 200 else []
    if not apps:
        print(f'::warning::Could not find the app record for {identifier} ({st}).')
        return
    app = apps[0]
    q = urllib.parse.urlencode({'filter[platform]': 'MAC_OS', 'limit': 5})
    st, r = call('GET', f"/apps/{app['id']}/appStoreVersions?{q}")
    if st == 200 and r.get('data'):
        print(f"{app['attributes'].get('name')} has a macOS version:", r['data'][0]['attributes'].get('versionString'))
    else:
        print(f"::warning::{app['attributes'].get('name')} has no macOS platform yet, so App Store Connect will refuse "
              'the upload. In App Store Connect open the app, choose Add Platform (the + next to iOS App) and pick macOS, '
              'then run this workflow again.')


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('icloud', 'macos'):
        sys.exit(__doc__)
    {'icloud': icloud, 'macos': macos}[sys.argv[1]](sys.argv[2])
