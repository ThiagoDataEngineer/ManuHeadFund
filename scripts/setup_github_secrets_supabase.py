#!/usr/bin/env python3
"""
setup_github_secrets_supabase.py

Cria/atualiza secrets do GitHub via REST API.
Encripta valores com libsodium sealed_box (formato exigido pelo GitHub).

Uso:
  python scripts/setup_github_secrets_supabase.py \
    --token ghp_XXX \
    --repo  ThiagoDataEngineer/ManuHeadFund \
    --secret SUPABASE_URL=https://xxx.supabase.co \
    --secret SUPABASE_ANON_KEY=sb_publishable_xxx \
    --secret SUPABASE_SERVICE_KEY=eyJ...

Reqs: pip install pynacl requests
"""
import argparse
import sys
import base64

import requests
from nacl import encoding, public


def get_repo_public_key(token: str, repo: str) -> dict:
    r = requests.get(
        f"https://api.github.com/repos/{repo}/actions/secrets/public-key",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "manuheadfund-setup",
        },
        timeout=15,
    )
    r.raise_for_status()
    return r.json()


def encrypt_secret(public_key_b64: str, value: str) -> str:
    pub = public.PublicKey(public_key_b64.encode("utf-8"), encoding.Base64Encoder())
    sealed = public.SealedBox(pub)
    enc = sealed.encrypt(value.encode("utf-8"))
    return base64.b64encode(enc).decode("utf-8")


def put_secret(token: str, repo: str, name: str, key_id: str, encrypted_value: str):
    r = requests.put(
        f"https://api.github.com/repos/{repo}/actions/secrets/{name}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "manuheadfund-setup",
        },
        json={
            "encrypted_value": encrypted_value,
            "key_id": key_id,
        },
        timeout=15,
    )
    r.raise_for_status()
    return r.status_code


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--token", required=True, help="GitHub PAT (ghp_*)")
    p.add_argument("--repo", required=True, help="owner/repo")
    p.add_argument("--secret", action="append", required=True,
                   help="NAME=VALUE (pode repetir)")
    args = p.parse_args()

    print(f"[setup] Repo: {args.repo}")
    print(f"[setup] Fetching public key...")
    pk = get_repo_public_key(args.token, args.repo)
    key_id = pk["key_id"]
    print(f"[setup] Public key id: {key_id}")
    print()

    pairs = []
    for s in args.secret:
        if "=" not in s:
            print(f"[setup] SKIP invalid format: {s}")
            continue
        name, _, value = s.partition("=")
        if not name or not value:
            print(f"[setup] SKIP empty name or value: {s}")
            continue
        pairs.append((name, value))

    print(f"[setup] {len(pairs)} secret(s) to upload\n")

    failed = 0
    for name, value in pairs:
        try:
            enc = encrypt_secret(pk["key"], value)
            status = put_secret(args.token, args.repo, name, key_id, enc)
            verb = "Created" if status == 201 else ("Updated" if status == 204 else f"Status {status}")
            print(f"  [+] {name:30} {verb}")
        except Exception as e:
            print(f"  [x] {name:30} FAILED: {e}")
            failed += 1

    print()
    print(f"[setup] Total: {len(pairs) - failed} OK, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
