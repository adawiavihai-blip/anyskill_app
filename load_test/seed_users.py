"""
seed_users.py — Create test Firebase accounts + Firestore docs before load test
================================================================================
Run ONCE before the load test.  Creates:
  • {NUM_PAIRS} customer accounts  (customer_0001@loadtest.anyskill.com … )
  • {NUM_PAIRS} provider accounts  (provider_0001@loadtest.anyskill.com … )
  • {NUM_PAIRS} chat room documents in /chats/{roomId}
  • Minimal user profile docs in /users/{uid}

IMPORTANT: Use a Firebase project dedicated to load testing, or the emulator.
           This will create real Firebase Auth accounts.

Usage:
  # Against emulator (recommended)
  FIREBASE_EMULATOR=1 python seed_users.py --pairs 1000

  # Against production (costs money, creates real accounts)
  FIREBASE_PROJECT_ID=anyskill-6fdf3 \\
  FIREBASE_WEB_API_KEY=AIzaSy... \\
  FIREBASE_SERVICE_ACCOUNT=path/to/sa.json \\
  python seed_users.py --pairs 1000

  # Teardown after testing
  python seed_users.py --teardown --pairs 1000
"""

import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

# ─── Config ──────────────────────────────────────────────────────────────────

PROJECT_ID  = os.getenv("FIREBASE_PROJECT_ID", "anyskill-6fdf3")
WEB_API_KEY = os.getenv("FIREBASE_WEB_API_KEY", "AIzaSyCk9QZ0cIfpeBP2EJ6aZfTHncmg7opphNQ")
EMULATOR    = os.getenv("FIREBASE_EMULATOR", "0") == "1"

if EMULATOR:
    AUTH_BASE_URL  = f"http://localhost:9099/identitytoolkit.googleapis.com/v1"
    FS_BASE_URL    = f"http://localhost:8080/v1/projects/{PROJECT_ID}/databases/(default)/documents"
    FS_COMMIT_URL  = f"http://localhost:8080/v1/projects/{PROJECT_ID}/databases/(default)/documents:commit"
else:
    AUTH_BASE_URL  = "https://identitytoolkit.googleapis.com/v1"
    FS_BASE_URL    = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
    FS_COMMIT_URL  = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents:commit"

TEST_PASSWORD = "LoadTest@2026!"
CONCURRENCY   = 20    # parallel threads for account creation


# ─── Firestore helpers ────────────────────────────────────────────────────────

def _str(v):  return {"stringValue": str(v)}
def _bool(v): return {"booleanValue": bool(v)}
def _int(v):  return {"integerValue": str(int(v))}
def _arr(*vs): return {"arrayValue": {"values": list(vs)}}


# ─── Firebase Auth REST helpers ───────────────────────────────────────────────

def _sign_up(email: str, password: str) -> dict | None:
    """Create a Firebase Auth account.  Returns user dict or None on failure."""
    resp = requests.post(
        f"{AUTH_BASE_URL}/accounts:signUp?key={WEB_API_KEY}",
        json={"email": email, "password": password, "returnSecureToken": True},
        timeout=15,
    )
    if resp.status_code == 200:
        return resp.json()   # localId, idToken, …
    if resp.status_code == 400:
        body = resp.json()
        if body.get("error", {}).get("message") == "EMAIL_EXISTS":
            # Account already exists — sign in instead
            return _sign_in(email, password)
    print(f"  [WARN] signUp {email}: {resp.status_code} {resp.text[:100]}")
    return None


def _sign_in(email: str, password: str) -> dict | None:
    resp = requests.post(
        f"{AUTH_BASE_URL}/accounts:signInWithPassword?key={WEB_API_KEY}",
        json={"email": email, "password": password, "returnSecureToken": True},
        timeout=15,
    )
    if resp.status_code == 200:
        return resp.json()
    print(f"  [WARN] signIn {email}: {resp.status_code} {resp.text[:100]}")
    return None


def _delete_user(id_token: str) -> bool:
    resp = requests.post(
        f"{AUTH_BASE_URL}/accounts:delete?key={WEB_API_KEY}",
        json={"idToken": id_token},
        timeout=10,
    )
    return resp.status_code == 200


# ─── Firestore helpers ────────────────────────────────────────────────────────

def _write_user_doc(id_token: str, uid: str, name: str, role: str):
    """Write a minimal /users/{uid} profile document."""
    headers = {"Authorization": f"Bearer {id_token}", "Content-Type": "application/json"}
    payload = {
        "fields": {
            "name":         _str(name),
            "email":        _str(f"{name.replace(' ', '_').lower()}@loadtest.anyskill.com"),
            "isProvider":   _bool(role == "provider"),
            "isCustomer":   _bool(role == "customer"),
            "isOnline":     _bool(False),
            "balance":      _int(500),          # seed with ₪500 for testing
            "serviceType":  _str("בדיקות עומס"),
            "aboutMe":      _str("Load test account — safe to delete"),
            "pricePerHour": _int(100),
            "fcmToken":     _str(""),           # no real FCM token
        }
    }
    resp = requests.patch(
        f"{FS_BASE_URL}/users/{uid}",
        json=payload,
        headers=headers,
        timeout=15,
    )
    return resp.status_code in (200, 201)


def _write_chat_room(id_token: str, room_id: str, uid1: str, uid2: str):
    """Create a /chats/{roomId} document with both user UIDs."""
    headers = {"Authorization": f"Bearer {id_token}", "Content-Type": "application/json"}
    payload = {
        "fields": {
            "users":            _arr(_str(uid1), _str(uid2)),
            "lastMessage":      _str(""),
            "lastMessageTime":  {"nullValue": None},
            "lastSenderId":     _str(""),
            f"unreadCount_{uid1}": _int(0),
            f"unreadCount_{uid2}": _int(0),
        }
    }
    resp = requests.patch(
        f"{FS_BASE_URL}/chats/{room_id}",
        json=payload,
        headers=headers,
        timeout=15,
    )
    return resp.status_code in (200, 201)


# ─── Core seeding logic ───────────────────────────────────────────────────────

def seed_pair(idx: int) -> dict:
    """Create one customer + one provider + their chat room."""
    c_email = f"customer_{idx:04d}@loadtest.anyskill.com"
    p_email = f"provider_{idx:04d}@loadtest.anyskill.com"
    room_id = f"lt_c{idx:04d}_p{idx:04d}"

    result = {"idx": idx, "ok": False, "error": None}

    # 1. Create / sign in both accounts
    c_data = _sign_up(c_email, TEST_PASSWORD)
    if not c_data:
        result["error"] = f"customer sign-up failed"
        return result

    p_data = _sign_up(p_email, TEST_PASSWORD)
    if not p_data:
        result["error"] = "provider sign-up failed"
        return result

    c_uid, c_token = c_data["localId"], c_data["idToken"]
    p_uid, p_token = p_data["localId"], p_data["idToken"]

    # 2. Write user profile docs (use customer token; both are authenticated writes)
    _write_user_doc(c_token, c_uid, f"Customer {idx:04d}", "customer")
    _write_user_doc(p_token, p_uid, f"Provider {idx:04d}", "provider")

    # 3. Write the shared chat room doc
    _write_chat_room(c_token, room_id, c_uid, p_uid)

    result["ok"] = True
    return result


def _delete_firestore_doc(id_token: str, path: str) -> bool:
    """DELETE a single Firestore document by REST path (e.g. 'users/uid')."""
    headers = {"Authorization": f"Bearer {id_token}"}
    resp = requests.delete(f"{FS_BASE_URL}/{path}", headers=headers, timeout=10)
    return resp.status_code in (200, 204)


def _delete_messages_subcollection(id_token: str, room_id: str):
    """List and delete all messages inside a chat room (best-effort)."""
    headers = {"Authorization": f"Bearer {id_token}"}
    page_token = None
    deleted = 0
    while True:
        params = {"pageSize": 300}
        if page_token:
            params["pageToken"] = page_token
        resp = requests.get(
            f"{FS_BASE_URL}/chats/{room_id}/messages",
            headers=headers,
            params=params,
            timeout=15,
        )
        if resp.status_code != 200:
            break
        body = resp.json()
        docs = body.get("documents", [])
        for doc in docs:
            # doc["name"] is the full resource path
            msg_path = doc["name"].split("/documents/", 1)[-1]
            _delete_firestore_doc(id_token, msg_path)
            deleted += 1
        page_token = body.get("nextPageToken")
        if not page_token:
            break
    return deleted


def teardown_pair(idx: int) -> dict:
    """Delete Firestore docs + Auth accounts for one customer/provider pair."""
    result = {"idx": idx, "ok": False}
    room_id = f"lt_c{idx:04d}_p{idx:04d}"

    for role in ("customer", "provider"):
        email = f"{role}_{idx:04d}@loadtest.anyskill.com"
        data  = _sign_in(email, TEST_PASSWORD)
        if not data:
            continue
        token = data["idToken"]
        uid   = data["localId"]

        # 1. Delete messages subcollection (customer token has write access)
        if role == "customer":
            _delete_messages_subcollection(token, room_id)
            _delete_firestore_doc(token, f"chats/{room_id}")

        # 2. Delete the /users/{uid} profile doc
        _delete_firestore_doc(token, f"users/{uid}")

        # 3. Delete the Auth account last (token becomes invalid after this)
        _delete_user(token)

    result["ok"] = True
    return result


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Seed/teardown AnySkill load test users")
    parser.add_argument("--pairs",    type=int,  default=1000,  help="Number of customer/provider pairs")
    parser.add_argument("--workers",  type=int,  default=CONCURRENCY, help="Parallel threads")
    parser.add_argument("--teardown", action="store_true",      help="Delete test accounts instead")
    args = parser.parse_args()

    mode   = "TEARDOWN" if args.teardown else "SEED"
    action = teardown_pair if args.teardown else seed_pair
    target = "emulator" if EMULATOR else "PRODUCTION Firebase"

    print(f"\n{mode}: {args.pairs} pairs against {target}")
    print(f"Concurrency: {args.workers} threads\n")

    ok = 0
    fail = 0
    start = time.time()

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(action, i): i for i in range(1, args.pairs + 1)}
        for future in as_completed(futures):
            res = future.result()
            if res.get("ok"):
                ok += 1
            else:
                fail += 1
                if res.get("error"):
                    print(f"  [FAIL] pair {res['idx']}: {res['error']}")
            if (ok + fail) % 100 == 0:
                elapsed = time.time() - start
                print(f"  Progress: {ok + fail}/{args.pairs} ({ok} ok, {fail} fail) — {elapsed:.0f}s")

    elapsed = time.time() - start
    print(f"\n{mode} complete: {ok} ok, {fail} failed in {elapsed:.1f}s")
    if fail > 0:
        print("Re-run to retry failed pairs (script is idempotent).")
    sys.exit(0 if fail == 0 else 1)


if __name__ == "__main__":
    main()
