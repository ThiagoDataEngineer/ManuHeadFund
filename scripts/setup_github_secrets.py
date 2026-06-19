#!/usr/bin/env python3
"""
Setup GitHub Secrets via REST API
Requer: GITHUB_TOKEN environment variable (Personal Access Token)
"""

import os
import json
import base64
import subprocess
import sys
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError

def load_credentials():
    """Load credentials from config.local.ps1"""
    config_path = Path("agents/config.local.ps1")

    if not config_path.exists():
        print("✗ config.local.ps1 not found")
        return None, None

    # Parse PowerShell config (simple extraction)
    content = config_path.read_text()

    supabase_url = None
    supabase_key = None

    for line in content.split('\n'):
        if 'SUPABASE_URL' in line and '=' in line and not line.strip().startswith('#'):
            # Extract URL between quotes
            parts = line.split('"')
            if len(parts) >= 2:
                supabase_url = parts[1]

        if 'SUPABASE_SERVICE_KEY' in line and '=' in line and 'SUPABASE_ANON' not in line and not line.strip().startswith('#'):
            # Extract key between quotes
            parts = line.split('"')
            if len(parts) >= 2:
                supabase_key = parts[1]

    if not supabase_url or not supabase_key:
        print("✗ Could not extract credentials")
        return None, None

    return supabase_url, supabase_key

def get_github_token():
    """Get GitHub token from environment"""
    token = os.getenv('GITHUB_TOKEN')
    if not token:
        print("✗ GITHUB_TOKEN not set")
        print("  Set via: $env:GITHUB_TOKEN = 'your_token'")
        print("  Create token at: https://github.com/settings/tokens")
        return None
    return token

def get_public_key(owner, repo, token):
    """Get repository public key for secret encryption"""
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/public-key"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v3+json"
    }

    try:
        req = Request(url, headers=headers)
        with urlopen(req) as response:
            data = json.loads(response.read().decode())
            return data.get('key_id'), data.get('key')
    except URLError as e:
        print(f"✗ Failed to get public key: {e}")
        return None, None

def encrypt_secret(public_key, secret_value):
    """Encrypt secret using Sodium (libsodium)"""
    try:
        import nacl.public
        import nacl.encoding
    except ImportError:
        print("✗ nacl library not found")
        print("  Install: pip install PyNaCl")
        return None

    public_key_obj = nacl.public.PublicKey(
        public_key.encode(),
        encoder=nacl.encoding.Base64Encoder
    )
    encrypted = nacl.public.SealedBox(public_key_obj).encrypt(
        secret_value.encode()
    )
    return base64.b64encode(encrypted.ciphertext).decode()

def set_secret(owner, repo, secret_name, secret_value, token, key_id, public_key):
    """Set GitHub secret"""
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/{secret_name}"

    # Encrypt the secret
    encrypted = encrypt_secret(public_key, secret_value)
    if not encrypted:
        print(f"✗ Failed to encrypt {secret_name}")
        return False

    payload = {
        "encrypted_value": encrypted,
        "key_id": key_id
    }

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    }

    try:
        req = Request(
            url,
            data=json.dumps(payload).encode(),
            headers=headers,
            method="PUT"
        )
        with urlopen(req) as response:
            if response.status in [201, 204]:
                print(f"  ✓ {secret_name} set successfully")
                return True
            else:
                print(f"  ✗ Failed to set {secret_name} (status {response.status})")
                return False
    except URLError as e:
        print(f"  ✗ Failed to set {secret_name}: {e}")
        return False

def main():
    print("╔════════════════════════════════════════════════════════════╗")
    print("║  SETUP GITHUB SECRETS VIA REST API                       ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print()

    # Load credentials
    print("[STEP 1] Loading credentials...")
    supabase_url, supabase_key = load_credentials()
    if not supabase_url or not supabase_key:
        return 1

    print(f"  ✓ SUPABASE_URL: {supabase_url}")
    print(f"  ✓ SUPABASE_SERVICE_KEY: {supabase_key[:50]}...")
    print()

    # Get GitHub token
    print("[STEP 2] Getting GitHub token...")
    token = get_github_token()
    if not token:
        return 1
    print("  ✓ Token loaded")
    print()

    # Get public key
    owner = "ThiagoDataEngineer"
    repo = "ManuHeadFund"
    print("[STEP 3] Getting repository public key...")
    key_id, public_key = get_public_key(owner, repo, token)
    if not key_id or not public_key:
        return 1
    print(f"  ✓ Key ID: {key_id}")
    print()

    # Set secrets
    print("[STEP 4] Setting secrets...")

    success = True
    success &= set_secret(owner, repo, "SUPABASE_URL", supabase_url, token, key_id, public_key)
    success &= set_secret(owner, repo, "SUPABASE_SERVICE_KEY", supabase_key, token, key_id, public_key)

    print()

    if success:
        print("╔════════════════════════════════════════════════════════════╗")
        print("║  ✓ GITHUB SECRETS CONFIGURED SUCCESSFULLY               ║")
        print("╚════════════════════════════════════════════════════════════╝")
        print()
        print("Next steps:")
        print("  • GitHub Actions activates automatically")
        print(f"  • Check: https://github.com/{owner}/{repo}/actions")
        print("  • Workflow: Hourly Auto-Calibration")
        print()
        return 0
    else:
        print("✗ Failed to set some secrets")
        return 1

if __name__ == "__main__":
    sys.exit(main())
