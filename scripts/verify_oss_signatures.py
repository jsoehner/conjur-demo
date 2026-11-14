#!/usr/bin/env python3
"""
verify_oss_signatures.py - Verify Cryptographic Signatures on Local OSS Artifacts

Fetches the Trusted OSS GPG and NIST FIPS 204 ML-DSA-65 public keys from the
configured local OSS registry, downloads the project's Python dependencies into
the local cache (.oss-cache/), and verifies detached .asc (GPG) and .mldsa65
(PQC) signatures for every artifact.

Configuration is resolved in order from:
  1. --oss-url CLI argument
  2. OSS_REGISTRY_URL environment variable
  3. .oss/oss.env (local gitignored config)
  4. uv.toml or pip.conf (local gitignored config)
"""

import argparse
import base64
import hashlib
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable, Optional, Tuple, TypeVar

T = TypeVar("T")


DEFAULT_PACKAGES = ["requests"]
DEFAULT_REQUIREMENTS = ["dashboard/requirements.txt"]


def normalize_pkg_name(name: str) -> str:
    """Normalize a Python package name per PEP 503."""
    return re.sub(r"[-_.]+", "-", name).lower()


def extract_base_url(url: str) -> str:
    """Extract scheme://host[:port] from a URL."""
    parsed = urllib.parse.urlparse(url.strip().strip('"').strip("'"))
    if not parsed.scheme or not parsed.netloc:
        raise ValueError(f"Invalid OSS registry URL: {url}")
    return f"{parsed.scheme}://{parsed.netloc}"


def resolve_oss_url(repo_root: Path, cli_url: Optional[str]) -> str:
    """Resolve the local OSS registry base URL from CLI, env, or local config."""
    if cli_url:
        return extract_base_url(cli_url)

    env_url = os.environ.get("OSS_REGISTRY_URL")
    if env_url:
        return extract_base_url(env_url)

    oss_env = repo_root / ".oss" / "oss.env"
    if oss_env.is_file():
        for line in oss_env.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("OSS_REGISTRY_URL="):
                return extract_base_url(line.split("=", 1)[1])

    uv_toml = repo_root / "uv.toml"
    if uv_toml.is_file():
        for line in uv_toml.read_text(encoding="utf-8").splitlines():
            m = re.match(r'^\s*index-url\s*=\s*"([^"]+)"', line)
            if m:
                return extract_base_url(m.group(1))

    pip_conf = repo_root / "pip.conf"
    if pip_conf.is_file():
        for line in pip_conf.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s*index-url\s*=\s*(\S+)", line)
            if m:
                return extract_base_url(m.group(1))

    raise RuntimeError(
        "No local OSS registry endpoint configured. Pass --oss-url, set "
        "OSS_REGISTRY_URL, or create .oss/oss.env / uv.toml / pip.conf."
    )


def retry_operation(
    operation: Callable[[], T],
    description: str,
    retries: int,
    retry_delay: float,
) -> T:
    """Retry an operation when the OSS endpoint may be fetching, scanning, and signing."""
    attempt = 0
    while True:
        attempt += 1
        try:
            return operation()
        except Exception as exc:
            if attempt > retries:
                raise RuntimeError(
                    f"{description} failed after {retries} retry attempt(s): {exc}"
                ) from exc
            wait_seconds = retry_delay * attempt
            print(
                f"[RETRY {attempt}/{retries}] {description} failed ({exc}); "
                f"OSS endpoint may be fetching/scanning/signing. Waiting {wait_seconds:.0f}s...",
                file=sys.stderr,
            )
            time.sleep(wait_seconds)


def download_file(
    url: str,
    dest: Path,
    force: bool = False,
    retries: int = 5,
    retry_delay: float = 5.0,
) -> Path:
    """Download a URL to dest if not already cached (or when force=True), with retries."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0 and not force:
        return dest

    def _fetch() -> Path:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=30) as resp:
            dest.write_bytes(resp.read())
        return dest

    return retry_operation(_fetch, f"Fetching {url}", retries=retries, retry_delay=retry_delay)


def dearmor(content: bytes) -> bytes:
    """Strip PEM armor headers if present and base64-decode."""
    text = content.decode("utf-8", errors="ignore")
    if "-----BEGIN " in text and "-----END " in text:
        clean_lines = [
            line.strip()
            for line in text.strip().splitlines()
            if not line.startswith("-----")
        ]
        return base64.b64decode("".join(clean_lines))
    return content


def setup_gpg_keyring(
    oss_url: str, cache_dir: Path, refresh: bool, retries: int, retry_delay: float
) -> Tuple[Path, Path]:
    """Fetch public keys into .oss-cache/keys and import GPG key into isolated keyring."""
    keys_dir = cache_dir / "keys"
    gnupg_dir = cache_dir / "gnupg"
    gnupg_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(gnupg_dir, 0o700)

    gpg_pub = download_file(
        f"{oss_url}/keys/trusted-oss-pubkey.asc",
        keys_dir / "trusted-oss-pubkey.asc",
        force=refresh,
        retries=retries,
        retry_delay=retry_delay,
    )
    mldsa_pub = download_file(
        f"{oss_url}/keys/trusted-oss-mldsa65.pub",
        keys_dir / "trusted-oss-mldsa65.pub",
        force=refresh,
        retries=retries,
        retry_delay=retry_delay,
    )

    proc = subprocess.run(
        ["gpg", "--homedir", str(gnupg_dir), "--batch", "--quiet", "--import", str(gpg_pub)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"Failed to import GPG public key: {proc.stderr.strip()}")

    return gnupg_dir, mldsa_pub


def download_project_wheels(
    oss_url: str,
    cache_dir: Path,
    requirements_files: list[Path],
    packages: list[str],
    retries: int,
    retry_delay: float,
) -> Path:
    """Download project OSS Python wheels into .oss-cache/wheels via the trusted OSS index."""
    wheels_dir = cache_dir / "wheels"
    wheels_dir.mkdir(parents=True, exist_ok=True)

    parsed = urllib.parse.urlparse(oss_url)
    host = parsed.hostname or ""
    index_url = f"{oss_url}/pypi/trusted/simple"

    cmd = [
        sys.executable,
        "-m",
        "pip",
        "download",
        "--dest",
        str(wheels_dir),
        "--index-url",
        index_url,
        "--trusted-host",
        host,
        "--quiet",
    ]
    for req_file in requirements_files:
        if req_file.is_file():
            cmd.extend(["-r", str(req_file)])
    cmd.extend(packages)

    print(f"[*] Downloading OSS Python artifacts from trusted registry: {index_url} ...")

    def _run_pip_download() -> Path:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.strip() or f"pip exited with code {proc.returncode}")
        return wheels_dir

    return retry_operation(
        _run_pip_download,
        "Downloading OSS Python artifacts",
        retries=retries,
        retry_delay=retry_delay,
    )


def artifact_pkg_candidates(filename: str) -> list[str]:
    """Derive candidate package directory names from a wheel or sdist filename."""
    raw_name = filename.split("-", 1)[0]
    norm = normalize_pkg_name(raw_name)
    lower = raw_name.lower()
    return [norm] if norm == lower else [norm, lower]


def fetch_signature(
    oss_url: str,
    filename: str,
    ext: str,
    sigs_dir: Path,
    refresh: bool,
    retries: int,
    retry_delay: float,
) -> Path:
    """Download a detached signature (.asc or .mldsa65) from /pypi/trusted/packages/."""
    def _attempt_all_candidates() -> Path:
        last_err: Optional[Exception] = None
        for pkg in artifact_pkg_candidates(filename):
            url = f"{oss_url}/pypi/trusted/packages/{pkg}/{filename}{ext}"
            dest = sigs_dir / f"{filename}{ext}"
            try:
                return download_file(
                    url, dest, force=refresh, retries=0, retry_delay=retry_delay
                )
            except Exception as exc:
                last_err = exc
        raise RuntimeError(f"Signature {filename}{ext} not found on {oss_url}: {last_err}")

    return retry_operation(
        _attempt_all_candidates,
        f"Fetching signature {filename}{ext}",
        retries=retries,
        retry_delay=retry_delay,
    )


def verify_gpg(gnupg_dir: Path, artifact: Path, asc_path: Path) -> bool:
    """Verify detached GPG signature."""
    proc = subprocess.run(
        ["gpg", "--homedir", str(gnupg_dir), "--batch", "--verify", str(asc_path), str(artifact)],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode == 0


def verify_mldsa65(artifact: Path, sig_path: Path, pub_path: Path) -> Tuple[bool, bool]:
    """Verify detached NIST FIPS 204 ML-DSA-65 signature if dilithium-py is installed."""
    try:
        from dilithium_py.dilithium import Dilithium3
    except ImportError:
        return True, True  # (ok, skipped)

    pk = dearmor(pub_path.read_bytes())
    sig = dearmor(sig_path.read_bytes())
    ok = Dilithium3.verify(pk, artifact.read_bytes(), sig)
    return ok, False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify GPG and ML-DSA-65 signatures for local OSS dependencies."
    )
    parser.add_argument("--oss-url", help="Override local OSS registry base URL")
    parser.add_argument(
        "--trusted-only",
        action="store_true",
        default=True,
        help="Use /pypi/trusted/simple exclusively (default)",
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=5,
        help="Number of retries if an artifact or signature is still being fetched/scanned/signed (default: 5)",
    )
    parser.add_argument(
        "--retry-delay",
        type=float,
        default=5.0,
        help="Base delay in seconds between retries (default: 5.0)",
    )
    parser.add_argument(
        "--refresh-keys",
        action="store_true",
        help="Force re-download of public keys and signatures",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(".oss-cache"),
        help="Local cache directory (default: .oss-cache)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    cache_dir = args.cache_dir if args.cache_dir.is_absolute() else repo_root / args.cache_dir

    try:
        oss_url = resolve_oss_url(repo_root, args.oss_url)
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print(f"[*] Using local OSS registry: {oss_url}")

    try:
        gnupg_dir, mldsa_pub = setup_gpg_keyring(
            oss_url, cache_dir, args.refresh_keys, args.retries, args.retry_delay
        )
        req_paths = [repo_root / p for p in DEFAULT_REQUIREMENTS]
        wheels_dir = download_project_wheels(
            oss_url, cache_dir, req_paths, DEFAULT_PACKAGES, args.retries, args.retry_delay
        )
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    artifacts = sorted(
        p for p in wheels_dir.iterdir()
        if p.is_file() and (p.name.endswith(".whl") or p.name.endswith(".tar.gz"))
    )
    if not artifacts:
        print("[ERROR] No OSS artifacts downloaded to verify.", file=sys.stderr)
        return 1

    sigs_dir = cache_dir / "sigs"
    failed = 0
    pqc_skipped = False

    for artifact in artifacts:
        sha256 = hashlib.sha256(artifact.read_bytes()).hexdigest()[:16]
        try:
            asc_path = fetch_signature(
                oss_url, artifact.name, ".asc", sigs_dir, args.refresh_keys, args.retries, args.retry_delay
            )
            if not verify_gpg(gnupg_dir, artifact, asc_path):
                print(f"[FAIL] GPG signature invalid: {artifact.name}", file=sys.stderr)
                failed += 1
                continue

            mldsa_sig = fetch_signature(
                oss_url, artifact.name, ".mldsa65", sigs_dir, args.refresh_keys, args.retries, args.retry_delay
            )
            pqc_ok, skipped = verify_mldsa65(artifact, mldsa_sig, mldsa_pub)
            if skipped:
                pqc_skipped = True
                pqc_label = "ML-DSA-65: sig-present (dilithium-py not installed)"
            elif pqc_ok:
                pqc_label = "ML-DSA-65: OK"
            else:
                print(f"[FAIL] ML-DSA-65 signature invalid: {artifact.name}", file=sys.stderr)
                failed += 1
                continue

            print(f"[OK] {artifact.name} (sha256:{sha256}..., GPG: OK, {pqc_label})")
        except Exception as exc:
            print(f"[FAIL] {artifact.name}: {exc}", file=sys.stderr)
            failed += 1

    if pqc_skipped:
        print(
            "[INFO] Note: Install 'dilithium-py' to enable client-side ML-DSA-65 "
            "cryptographic verification in addition to GPG."
        )

    if failed:
        print(f"[ERROR] {failed} artifact(s) failed signature verification.", file=sys.stderr)
        return 1

    print(f"[SUCCESS] All {len(artifacts)} OSS artifact(s) passed signed verification.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
