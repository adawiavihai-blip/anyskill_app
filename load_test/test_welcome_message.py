"""
test_welcome_message.py — Verify the AnySkill welcome-message feature
======================================================================
Mirrors the Dart logic in onboarding_screen.dart _sendWelcomeMessage().

Runs 3 end-to-end test cases against production Firebase:
  1. Customer-only  → Hebrew customer welcome
  2. Provider-only  → Hebrew professional welcome
  3. Dual-role      → Hebrew professional welcome (provider path wins)

Each test:
  • Creates a real Firebase Auth account
  • Writes the minimal Firestore user doc (mirrors sign_up_screen.dart)
  • Runs the welcome-message Firestore logic (mirrors _sendWelcomeMessage)
  • Reads back Firestore and asserts every field
  • Cleans up all created documents + Auth account

Usage:
  python load_test/test_welcome_message.py
"""

import io
import os
import sys
import requests

# Force UTF-8 output on Windows so Hebrew + symbols print correctly
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ── Config ────────────────────────────────────────────────────────────────────

PROJECT_ID  = os.getenv("FIREBASE_PROJECT_ID", "anyskill-6fdf3")
WEB_API_KEY = os.getenv("FIREBASE_WEB_API_KEY", "AIzaSyCk9QZ0cIfpeBP2EJ6aZfTHncmg7opphNQ")

AUTH_BASE = "https://identitytoolkit.googleapis.com/v1"
FS_BASE   = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"

TEST_PASSWORD  = "WelcomeTest@2026!"
SYSTEM_UID     = "anyskill_system"

CUSTOMER_OPENER = "ברוכים הבאים ל-AnySkill"
PROVIDER_OPENER = "איזה כיף שהצטרפת"

# ── Firestore value helpers (mirrors seed_users.py) ───────────────────────────

def _str(v):   return {"stringValue": str(v)}
def _bool(v):  return {"booleanValue": bool(v)}
def _int(v):   return {"integerValue": str(int(v))}
def _arr(*vs): return {"arrayValue": {"values": list(vs)}}


def _field_val(doc, field):
    """Extract a plain Python value from a Firestore document field."""
    f = doc.get("fields", {}).get(field, {})
    for kind in ("stringValue", "booleanValue", "integerValue", "doubleValue", "nullValue"):
        if kind in f:
            return f[kind]
    if "arrayValue" in f:
        return [_field_val({"fields": {"v": v}}, "v") for v in f["arrayValue"].get("values", [])]
    return None


# ── Firebase Auth helpers ─────────────────────────────────────────────────────

def sign_up(email):
    r = requests.post(
        f"{AUTH_BASE}/accounts:signUp?key={WEB_API_KEY}",
        json={"email": email, "password": TEST_PASSWORD, "returnSecureToken": True},
        timeout=15,
    )
    r.raise_for_status()
    return r.json()  # localId, idToken


def delete_auth(id_token):
    requests.post(
        f"{AUTH_BASE}/accounts:delete?key={WEB_API_KEY}",
        json={"idToken": id_token},
        timeout=10,
    )


# ── Firestore helpers ─────────────────────────────────────────────────────────

def _headers(token):
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def fs_patch(token, path, fields):
    """PATCH (create-or-merge) a Firestore document."""
    r = requests.patch(
        f"{FS_BASE}/{path}",
        json={"fields": fields},
        headers=_headers(token),
        timeout=15,
    )
    r.raise_for_status()
    return r.json()


def fs_get(token, path):
    r = requests.get(f"{FS_BASE}/{path}", headers=_headers(token), timeout=10)
    if r.status_code == 404:
        return None
    r.raise_for_status()
    return r.json()


def fs_delete(token, path):
    requests.delete(f"{FS_BASE}/{path}", headers=_headers(token), timeout=10)


def fs_list(token, path):
    """List documents in a collection (returns list of doc dicts)."""
    r = requests.get(f"{FS_BASE}/{path}", headers=_headers(token), timeout=15)
    if r.status_code == 404:
        return []
    r.raise_for_status()
    return r.json().get("documents", [])


def chat_room_id(uid):
    """Deterministic chat room ID: sorted join of [uid, SYSTEM_UID]."""
    ids = sorted([uid, SYSTEM_UID])
    return "_".join(ids)


# ── Core logic (mirrors onboarding_screen.dart) ───────────────────────────────

CUSTOMER_MSG = (
    "ברוכים הבאים ל-AnySkill! 🌟 צריכים עזרה במשהו? הגעתם למקום הנכון. "
    "אלפי אנשי מקצוע זמינים עבורכם עכשיו כדי להפוך כל תוכנית למציאות. "
    "חיפוש קל: מצאו את איש המקצוע המדויק לפי דירוג ומיקום. "
    "צ'אט ישיר: שלחו הודעה וקבלו מענה מהיר. "
    "סוגרים ויוצאים לדרך: תיאום פשוט ובטוח ישירות מהאפליקציה. "
    "במה נתחיל היום?"
)

PROVIDER_MSG = (
    "איזה כיף שהצטרפת לנבחרת אנשי המקצוע של AnySkill! 🚀 "
    "הלקוח הבא שלך כבר כאן. כדי להתחיל ברגל ימין: "
    "הפרופיל שלך: העלה תמונה טובה ופרט על הניסיון שלך – זה כרטיס הביקור שלך. "
    "זמינות: לקוחות מחפשים מענה מהיר. שים לב להתרעות מהצ'אט. "
    "איכות השירות: כל עבודה טובה שווה דירוג של 5 כוכבים שיקפיץ אותך קדימה. "
    "מאחלים לך המון הצלחה ופניות רבות!"
)


def write_user_doc(token, uid, is_customer, is_provider):
    """Mirrors sign_up_screen.dart initial doc + _finish() update."""
    fs_patch(token, f"users/{uid}", {
        "uid":              _str(uid),
        "name":             _str("Test User"),
        "email":            _str("test@example.com"),
        "balance":          _int(0),
        "isCustomer":       _bool(is_customer),
        "isProvider":       _bool(is_provider),
        "isOnline":         _bool(False),
        "isAdmin":          _bool(False),
        "onboardingComplete": _bool(True),
    })


def send_welcome_message(token, uid, is_provider):
    """Mirrors _sendWelcomeMessage() in onboarding_screen.dart."""
    welcome_text = PROVIDER_MSG if is_provider else CUSTOMER_MSG
    preview = (welcome_text[:50] + "...") if len(welcome_text) > 50 else welcome_text
    room_id = chat_room_id(uid)

    # 1. Ensure anyskill_system user doc (create-only — update is blocked by rules)
    if fs_get(token, f"users/{SYSTEM_UID}") is None:
        fs_patch(token, f"users/{SYSTEM_UID}", {
            "uid":          _str(SYSTEM_UID),
            "name":         _str("AnySkill"),
            "profileImage": _str(""),
            "isProvider":   _bool(False),
            "isCustomer":   _bool(False),
            "isOnline":     _bool(True),
            "balance":      _int(0),
        })

    # 2. Create chat room doc
    fs_patch(token, f"chats/{room_id}", {
        "users":                        _arr(_str(uid), _str(SYSTEM_UID)),
        "lastMessage":                  _str(preview),
        "lastSenderId":                 _str(SYSTEM_UID),
        f"unreadCount_{uid}":           _int(1),
        f"unreadCount_{SYSTEM_UID}":    _int(0),
    })

    # 3. Add welcome message
    r = requests.post(
        f"{FS_BASE}/chats/{room_id}/messages",
        json={"fields": {
            "senderId":   _str(SYSTEM_UID),
            "receiverId": _str(uid),
            "message":    _str(welcome_text),
            "type":       _str("text"),
            "isRead":     _bool(False),
        }},
        headers=_headers(token),
        timeout=15,
    )
    r.raise_for_status()


# ── Assertions ────────────────────────────────────────────────────────────────

def assert_eq(label, got, expected):
    if got != expected:
        print(f"  ✗ {label}: expected {expected!r}, got {got!r}")
        return False
    return True


def assert_contains(label, collection, item):
    if item not in collection:
        print(f"  ✗ {label}: {item!r} not in {collection!r}")
        return False
    return True


def assert_startswith(label, text, prefix):
    if not str(text or "").startswith(prefix):
        print(f"  ✗ {label}: expected to start with {prefix!r}, got {str(text)[:80]!r}")
        return False
    return True


def verify(token, uid, is_provider, label):
    room_id = chat_room_id(uid)
    passed = True

    # Check anyskill_system user doc
    sys_doc = fs_get(token, f"users/{SYSTEM_UID}")
    if sys_doc is None:
        print(f"  ✗ users/{SYSTEM_UID}: document not found")
        passed = False
    else:
        passed &= assert_eq("anyskill_system.name", _field_val(sys_doc, "name"), "AnySkill")

    # Check chat room doc
    chat_doc = fs_get(token, f"chats/{room_id}")
    if chat_doc is None:
        print(f"  ✗ chats/{room_id}: document not found")
        return False
    users_array = _field_val(chat_doc, "users") or []
    passed &= assert_contains("chat.users contains uid", users_array, uid)
    passed &= assert_contains("chat.users contains anyskill_system", users_array, SYSTEM_UID)
    unread = _field_val(chat_doc, f"unreadCount_{uid}")
    passed &= assert_eq(f"unreadCount_{uid}", str(unread), "1")

    # Check message
    msgs = fs_list(token, f"chats/{room_id}/messages")
    if not msgs:
        print(f"  ✗ chats/{room_id}/messages: no messages found")
        return False
    msg_fields = msgs[0].get("fields", {})
    msg_doc = {"fields": msg_fields}
    passed &= assert_eq("message.senderId", _field_val(msg_doc, "senderId"), SYSTEM_UID)
    passed &= assert_eq("message.type", _field_val(msg_doc, "type"), "text")
    expected_opener = PROVIDER_OPENER if is_provider else CUSTOMER_OPENER
    passed &= assert_startswith("message.text opener", _field_val(msg_doc, "message"), expected_opener)

    return passed


# ── Cleanup ───────────────────────────────────────────────────────────────────

def cleanup(token, uid, id_token):
    room_id = chat_room_id(uid)
    # Delete messages
    for doc in fs_list(token, f"chats/{room_id}/messages"):
        msg_path = doc["name"].split("/documents/", 1)[-1]
        fs_delete(token, msg_path)
    # Delete chat doc
    fs_delete(token, f"chats/{room_id}")
    # Delete user doc
    fs_delete(token, f"users/{uid}")
    # Delete Auth account
    delete_auth(id_token)


# ── Test runner ───────────────────────────────────────────────────────────────

CASES = [
    ("wt_customer@test.anyskill.com", False, True,  "Customer-only"),
    ("wt_provider@test.anyskill.com", True,  False, "Provider-only"),
    ("wt_dual@test.anyskill.com",     True,  True,  "Dual-role    "),
]

def main():
    print(f"\nAnySkill Welcome Message — 3 test cases against project '{PROJECT_ID}'\n")
    all_passed = True

    for email, is_provider, is_customer, label in CASES:
        print(f"[{label}]  {email}")
        id_token = uid = token = None
        try:
            # Setup
            data     = sign_up(email)
            uid      = data["localId"]
            id_token = data["idToken"]
            token    = id_token

            write_user_doc(token, uid, is_customer, is_provider)
            send_welcome_message(token, uid, is_provider)

            # Verify
            ok = verify(token, uid, is_provider, label)
            if ok:
                print(f"  ✓ PASS\n")
            else:
                print(f"  FAIL\n")
                all_passed = False

        except Exception as e:
            print(f"  ✗ ERROR: {e}\n")
            all_passed = False

        finally:
            if uid and id_token and token:
                cleanup(token, uid, id_token)
                print(f"  Cleaned up uid={uid}\n") if not all_passed else None

    # Note: anyskill_system doc is intentionally left (it's a permanent system doc).
    # Delete it manually if needed: Firestore console → users/anyskill_system → Delete.

    if all_passed:
        print("All 3 tests PASSED ✓")
        print("Note: users/anyskill_system was created/updated in Firestore (permanent system doc).")
    else:
        print("Some tests FAILED ✗")
        sys.exit(1)


if __name__ == "__main__":
    main()
