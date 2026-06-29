import subprocess
from pathlib import Path


def generate_pki(pki_dir: Path) -> None:
    """Generate a test PKI in pki_dir. Idempotent: skips if ca.cert.pem already exists."""
    pki_dir.mkdir(parents=True, exist_ok=True)

    if (pki_dir / 'ca.cert.pem').exists():
        return  # already generated

    # 1. Test CA (self-signed, 10 years)
    _run([
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
        '-keyout', str(pki_dir / 'ca.key.pem'),
        '-out',    str(pki_dir / 'ca.cert.pem'),
        '-days', '3650', '-nodes',
        '-subj', '/CN=Lidi Test CA',
    ])

    # 2. Server certificate (for lidi-send TLS listener and lidi-file-receive TLS listener)
    _gen_signed_cert(pki_dir, 'server', '/CN=localhost',
                     pki_dir / 'ca.key.pem', pki_dir / 'ca.cert.pem', days=3650)

    # 3. Client certificate (for lidi-file-send mTLS and lidi-receive mTLS client)
    _gen_signed_cert(pki_dir, 'client', '/CN=lidi-client',
                     pki_dir / 'ca.key.pem', pki_dir / 'ca.cert.pem', days=3650)

    # 4. Expired certificate (valid CA signature but dates in the past)
    _gen_csr(pki_dir, 'expired', '/CN=lidi-expired')
    _run([
        'openssl', 'x509', '-req',
        '-in',  str(pki_dir / 'expired.csr.pem'),
        '-CA',  str(pki_dir / 'ca.cert.pem'),
        '-CAkey', str(pki_dir / 'ca.key.pem'),
        '-CAcreateserial',
        '-out', str(pki_dir / 'expired.cert.pem'),
        '-set_serial', '1',
        '-not_before', '20200101000000Z',
        '-not_after',  '20200102000000Z',
    ])

    # 5. Other CA (different trust anchor — certificates it signs will be untrusted by our CA)
    _run([
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
        '-keyout', str(pki_dir / 'other_ca.key.pem'),
        '-out',    str(pki_dir / 'other_ca.cert.pem'),
        '-days', '3650', '-nodes',
        '-subj', '/CN=Lidi Other CA',
    ])

    # 6. Wrong-CA certificate (signed by other_ca, not our test CA)
    _gen_signed_cert(pki_dir, 'wrong', '/CN=lidi-wrong',
                     pki_dir / 'other_ca.key.pem', pki_dir / 'other_ca.cert.pem', days=3650)


def _gen_csr(pki_dir: Path, name: str, subject: str) -> None:
    _run([
        'openssl', 'req', '-newkey', 'rsa:2048',
        '-keyout', str(pki_dir / f'{name}.key.pem'),
        '-out',    str(pki_dir / f'{name}.csr.pem'),
        '-nodes', '-subj', subject,
    ])


def _gen_signed_cert(pki_dir: Path, name: str, subject: str,
                     ca_key: Path, ca_cert: Path, days: int) -> None:
    _gen_csr(pki_dir, name, subject)
    _run([
        'openssl', 'x509', '-req',
        '-in',    str(pki_dir / f'{name}.csr.pem'),
        '-CA',    str(ca_cert),
        '-CAkey', str(ca_key),
        '-CAcreateserial',
        '-out',   str(pki_dir / f'{name}.cert.pem'),
        '-days',  str(days),
    ])


def _run(cmd: list) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f'PKI generation failed:\n  cmd: {" ".join(cmd)}\n  stderr: {result.stderr}'
        )
