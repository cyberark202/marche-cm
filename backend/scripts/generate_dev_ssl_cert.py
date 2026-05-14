from __future__ import annotations

from datetime import datetime, timedelta, timezone
from ipaddress import ip_address
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def main() -> None:
    base_dir = Path(__file__).resolve().parents[1]
    certs_dir = base_dir / "certs"
    certs_dir.mkdir(parents=True, exist_ok=True)

    key_path = certs_dir / "dev-localhost.key.pem"
    cert_path = certs_dir / "dev-localhost.crt.pem"

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "CM"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Central Market"),
            x509.NameAttribute(NameOID.COMMON_NAME, "localhost"),
        ]
    )
    now = datetime.now(timezone.utc)
    san = x509.SubjectAlternativeName(
        [
            x509.DNSName("localhost"),
            x509.DNSName("127.0.0.1.nip.io"),
            x509.IPAddress(ip_address("127.0.0.1")),
        ]
    )

    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=365))
        .add_extension(san, critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(private_key, hashes.SHA256())
    )

    key_path.write_bytes(
        private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))

    print(f"SSL key generated: {key_path}")
    print(f"SSL cert generated: {cert_path}")


if __name__ == "__main__":
    main()
