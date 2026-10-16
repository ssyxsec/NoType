#!/usr/bin/env python3
"""Stable private development identity; never changes system trust or TCC."""
import os
import pathlib
import secrets
import subprocess
import sys
import tempfile

directory = pathlib.Path.home() / 'Library/Application Support/NoType/Signing'
directory.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(directory, 0o700)
password_file = directory / 'keychain-password'
keychain = directory / 'notype-signing.keychain-db'
certificate = directory / 'certificate.pem'
def run(args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout
try:
    if not password_file.exists():
        password_file.write_text(secrets.token_urlsafe(32))
        os.chmod(password_file, 0o600)
    password = password_file.read_text()
    if not keychain.exists():
        run(['/usr/bin/security', 'create-keychain', '-p', password, str(keychain)])
        run(['/usr/bin/security', 'set-keychain-settings', '-lut', '21600', str(keychain)])
    run(['/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain)])
    if not certificate.exists():
        with tempfile.TemporaryDirectory(dir=directory) as temp:
            folder = pathlib.Path(temp)
            config = folder / 'openssl.cnf'
            config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=NoType Local Development\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n')
            key = folder/'key.pem'; cert = folder/'cert.pem'; p12 = folder/'identity.p12'
            run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '3650', '-config', str(config), '-keyout', str(key), '-out', str(cert)])
            env = dict(os.environ, NOTYPE_SIGNING_PASSWORD=password)
            subprocess.run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(cert), '-out', str(p12), '-passout', 'env:NOTYPE_SIGNING_PASSWORD'], env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            run(['/usr/bin/security', 'import', str(p12), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign'])
            run(['/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain)])
            certificate.write_bytes(cert.read_bytes())
    fingerprint = run(['/usr/bin/openssl', 'x509', '-in', str(certificate), '-noout', '-fingerprint', '-sha1']).strip().split('=')[-1].replace(':', '')
    app = sys.argv[1]
    run(['/usr/bin/codesign', '--force', '--sign', fingerprint, '--keychain', str(keychain), '--timestamp=none', '--identifier', 'local.notype.desktop', app])
    print('Signed with persistent NoType development certificate (no system trust changes).')
except subprocess.CalledProcessError as error:
    # Do not print commands that include keychain passwords.
    print('Local signing failed: ' + error.stderr.strip(), file=sys.stderr)
    sys.exit(1)
