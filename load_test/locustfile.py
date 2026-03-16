"""
AnySkill Firebase Stress Test — locustfile.py
==============================================
Simulates 1,000 customers + 1,000 service providers hammering
the Firebase Firestore REST API and Firebase Auth REST API simultaneously.

Architecture note
-----------------
AnySkill has NO custom REST backend.  Every client call goes directly to
Firebase endpoints:
  • Auth   → https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword
  • Writes → https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents/…
  • Reads  → https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents/…
  • Query  → https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents:runQuery

What this test stresses
-----------------------
1.  sendMessage      — POST  /chats/{roomId}/messages
2.  updateChatMeta   — PATCH /chats/{roomId}  (lastMessage + unreadCount)
3.  getHistory       — GET   /chats/{roomId}/messages?orderBy=timestamp+desc&pageSize=50
4.  listMyChats      — runQuery (arrayContains: uid)
5.  markAsRead       — PATCH /chats/{roomId}  (reset unreadCount)
6.  signInWithPassword — Firebase Auth

Usage
-----
  # Install deps
  pip install -r requirements.txt

  # Seed test users first (run once)
  python seed_users.py

  # Run headless
  locust --headless --users 2000 --spawn-rate 50 --run-time 35m

  # Run with web UI
  locust --host https://firestore.googleapis.com

  # Recommended: use Firebase emulators (see README for setup)
  FIREBASE_EMULATOR=1 locust --headless --users 2000 --spawn-rate 50 --run-time 35m

WARNING
-------
Running this against your PRODUCTION Firebase project will:
  • Consume real Firestore read/write quota
  • Trigger real Cloud Function invocations (sendchatnotification × 2000 msg/s)
  • Incur real Firebase costs
  • Spam real FCM push notifications
Use the Firebase emulator suite or a dedicated test project instead.
"""

import base64
import json
import os
import random
import time
import uuid
from datetime import datetime, timezone

from locust import HttpUser, between, events, task
from locust.contrib.fasthttp import FastHttpUser


# ─── Project constants ────────────────────────────────────────────────────────

PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "anyskill-6fdf3")
WEB_API_KEY = os.getenv("FIREBASE_WEB_API_KEY", "AIzaSyCk9QZ0cIfpeBP2EJ6aZfTHncmg7opphNQ")
NUM_PAIRS   = int(os.getenv("LOAD_TEST_PAIRS", "1000"))   # 1 customer ↔ 1 provider per pair

# When FIREBASE_EMULATOR=1, point at the local emulator instead of production
_EMULATOR = os.getenv("FIREBASE_EMULATOR", "0") == "1"

if _EMULATOR:
    FIRESTORE_HOST = "http://localhost:8080"
    AUTH_HOST      = "http://localhost:9099"
    FIRESTORE_ROOT = (
        f"http://localhost:8080/v1/projects/{PROJECT_ID}/databases/(default)/documents"
    )
    AUTH_URL = (
        f"http://localhost:9099/identitytoolkit.googleapis.com/v1"
        f"/accounts:signInWithPassword?key={WEB_API_KEY}"
    )
else:
    FIRESTORE_HOST = "https://firestore.googleapis.com"
    AUTH_HOST      = "https://identitytoolkit.googleapis.com"
    FIRESTORE_ROOT = (
        f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}"
        f"/databases/(default)/documents"
    )
    AUTH_URL = (
        f"https://identitytoolkit.googleapis.com/v1"
        f"/accounts:signInWithPassword?key={WEB_API_KEY}"
    )

RUN_QUERY_URL = (
    f"{FIRESTORE_HOST}/v1/projects/{PROJECT_ID}"
    f"/databases/(default)/documents:runQuery"
)

TEST_PASSWORD = "LoadTest@2026!"


# ─── Firestore field helpers ──────────────────────────────────────────────────

def _str(v):  return {"stringValue": str(v)}
def _bool(v): return {"booleanValue": bool(v)}
def _int(v):  return {"integerValue": str(int(v))}
def _ts():
    return {"timestampValue": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")}


# ─── Auth token manager ───────────────────────────────────────────────────────

class _TokenStore:
    """Thread-safe per-user token cache with auto-refresh."""

    def __init__(self, http_client, email: str, password: str):
        self._client   = http_client
        self._email    = email
        self._password = password
        self._token: str | None = None
        self._expires_at: float = 0.0
        self._uid: str | None   = None

    # ── public ──────────────────────────────────────────────────────────────

    @property
    def uid(self) -> str:
        if not self._uid:
            self._sign_in()
        return self._uid or "unknown"

    @property
    def bearer(self) -> str:
        if not self._token or time.time() > self._expires_at - 120:
            self._sign_in()
        return self._token

    @property
    def auth_headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.bearer}",
            "Content-Type":  "application/json",
        }

    # ── private ─────────────────────────────────────────────────────────────

    def _sign_in(self):
        resp = self._client.post(
            AUTH_URL,
            json={
                "email":             self._email,
                "password":          self._password,
                "returnSecureToken": True,
            },
            name="[Auth] signInWithPassword",
        )
        if resp.status_code != 200:
            resp.failure(f"Auth failed ({resp.status_code}): {resp.text[:200]}")
            raise RuntimeError(f"Auth failed for {self._email}")

        data = resp.json()
        self._token      = data["idToken"]
        self._expires_at = time.time() + int(data.get("expiresIn", 3600))
        self._uid        = data.get("localId") or self._decode_uid(self._token)

    @staticmethod
    def _decode_uid(id_token: str) -> str:
        """Decode UID from the JWT payload (no signature verification needed here)."""
        try:
            payload = id_token.split(".")[1]
            payload += "=" * (4 - len(payload) % 4)
            decoded = json.loads(base64.urlsafe_b64decode(payload))
            return decoded.get("user_id") or decoded.get("sub") or "unknown"
        except Exception:
            return "unknown"


# ─── Shared chat helpers ──────────────────────────────────────────────────────

CUSTOMER_MESSAGES = [
    "שלום, אני מעוניין בשירות שלך",
    "מתי אתה פנוי?",
    "כמה זה עולה לשעה?",
    "האם אתה זמין השבוע?",
    "תודה רבה!",
    "אשמח לשמוע פרטים נוספים",
    "האם יש לך ניסיון בתחום?",
    "מה כולל השירות?",
    "האם ניתן לקבל חשבונית?",
    "יש לך ביקורות?",
]

PROVIDER_REPLIES = [
    "שלום! אשמח לעזור",
    "כן, אני פנוי ביום ראשון",
    "המחיר הוא 150₪ לשעה",
    "בטח, נשמח להיפגש",
    "אשלח לך פרטים נוספים",
    "מה בדיוק אתה מחפש?",
    "יש לי ניסיון רב בתחום",
    "אוכל להגיע אליך ביתית",
    "ניתן לתאם פגישה השבוע",
    "תודה על הפנייה!",
]


class _ChatMixin:
    """
    Mixin that gives both CustomerUser and ProviderUser their Firestore
    chat operations.  Requires self.auth (_TokenStore) and self.room_id (str).
    """

    # ── Firestore WRITE: new message ─────────────────────────────────────────

    def _send_message(self, receiver_id: str, text: str):
        payload = {
            "fields": {
                "senderId":   _str(self.auth.uid),
                "receiverId": _str(receiver_id),
                "message":    _str(text),
                "type":       _str("text"),
                "timestamp":  _ts(),
                "isRead":     _bool(False),
            }
        }
        r = self.client.post(
            f"{FIRESTORE_ROOT}/chats/{self.room_id}/messages",
            json=payload,
            headers=self.auth.auth_headers,
            name="[Chat] sendMessage",
        )
        if r.status_code not in (200, 201):
            r.failure(f"sendMessage {r.status_code}: {r.text[:120]}")

    # ── Firestore PATCH: chat room metadata ──────────────────────────────────

    def _update_chat_metadata(self, receiver_id: str, last_msg: str):
        """
        Mirrors the app's batch write: update lastMessage + increment unreadCount.
        NOTE: Firestore REST PATCH cannot use FieldValue.increment(); we use a
        simple write here.  The real bottleneck (contention on the chat document)
        is still exercised.
        """
        field_key = f"unreadCount_{receiver_id}"
        payload = {
            "fields": {
                "lastMessage":     _str(last_msg),
                "lastMessageTime": _ts(),
                "lastSenderId":    _str(self.auth.uid),
                field_key:         _int(1),
            }
        }
        mask = (
            f"updateMask.fieldPaths=lastMessage"
            f"&updateMask.fieldPaths=lastMessageTime"
            f"&updateMask.fieldPaths=lastSenderId"
            f"&updateMask.fieldPaths={field_key}"
        )
        r = self.client.patch(
            f"{FIRESTORE_ROOT}/chats/{self.room_id}?{mask}",
            json=payload,
            headers=self.auth.auth_headers,
            name="[Chat] updateChatMetadata",
        )
        if r.status_code not in (200, 201):
            r.failure(f"updateChatMetadata {r.status_code}: {r.text[:120]}")

    # ── Firestore GET: message history ───────────────────────────────────────

    def _get_history(self):
        r = self.client.get(
            f"{FIRESTORE_ROOT}/chats/{self.room_id}/messages"
            f"?orderBy=timestamp+desc&pageSize=50",
            headers=self.auth.auth_headers,
            name="[Chat] getHistory",
        )
        if r.status_code != 200:
            r.failure(f"getHistory {r.status_code}: {r.text[:120]}")
        return r

    # ── Firestore GET: single chat room doc ──────────────────────────────────

    def _get_chat_doc(self):
        r = self.client.get(
            f"{FIRESTORE_ROOT}/chats/{self.room_id}",
            headers=self.auth.auth_headers,
            name="[Chat] getChatDoc",
        )
        if r.status_code not in (200, 404):
            r.failure(f"getChatDoc {r.status_code}: {r.text[:120]}")
        return r

    # ── Firestore PATCH: reset unread counter ────────────────────────────────

    def _mark_as_read(self):
        field_key = f"unreadCount_{self.auth.uid}"
        payload   = {"fields": {field_key: _int(0)}}
        mask      = f"updateMask.fieldPaths={field_key}"
        r = self.client.patch(
            f"{FIRESTORE_ROOT}/chats/{self.room_id}?{mask}",
            json=payload,
            headers=self.auth.auth_headers,
            name="[Chat] markAsRead",
        )
        if r.status_code not in (200, 201):
            r.failure(f"markAsRead {r.status_code}: {r.text[:120]}")

    # ── Firestore runQuery: my chat list ─────────────────────────────────────

    def _list_my_chats(self):
        body = {
            "structuredQuery": {
                "from":  [{"collectionId": "chats"}],
                "where": {
                    "fieldFilter": {
                        "field": {"fieldPath": "users"},
                        "op":    "ARRAY_CONTAINS",
                        "value": _str(self.auth.uid),
                    }
                },
                "limit": 50,
            }
        }
        r = self.client.post(
            RUN_QUERY_URL,
            json=body,
            headers=self.auth.auth_headers,
            name="[Chat] listMyChats",
        )
        if r.status_code != 200:
            r.failure(f"listMyChats {r.status_code}: {r.text[:120]}")
        return r


# ─── User classes ─────────────────────────────────────────────────────────────

class CustomerUser(HttpUser, _ChatMixin):
    """
    Represents a customer browsing and sending messages.

    Task weights reflect real usage patterns:
      5× sendMessage      — customers initiate conversations
      3× getHistory       — polling for replies
      2× listMyChats      — opening the app / switching tabs
      1× markAsRead       — opening a chat room
    """

    host      = FIRESTORE_HOST
    wait_time = between(1, 3)  # customers are impatient

    def on_start(self):
        idx = random.randint(1, NUM_PAIRS)
        self._pair_idx    = idx
        self._provider_id = f"provider_{idx:04d}"
        self.room_id      = f"lt_c{idx:04d}_p{idx:04d}"   # deterministic test room

        email = f"customer_{idx:04d}@loadtest.anyskill.com"
        self.auth = _TokenStore(self.client, email, TEST_PASSWORD)
        try:
            _ = self.auth.uid   # trigger sign-in; fail fast if creds missing
        except RuntimeError:
            self.environment.runner.quit()

    @task(5)
    def send_message(self):
        text = random.choice(CUSTOMER_MESSAGES)
        self._send_message(self._provider_id, text)
        self._update_chat_metadata(self._provider_id, text)

    @task(3)
    def poll_history(self):
        self._get_history()

    @task(2)
    def open_app(self):
        self._list_my_chats()

    @task(1)
    def open_chat_room(self):
        self._get_chat_doc()
        self._mark_as_read()


class ProviderUser(HttpUser, _ChatMixin):
    """
    Represents a service provider checking messages and replying.

    Task weights:
      4× getHistory       — providers constantly check for new work
      3× replyToCustomer  — replying when available
      2× listMyChats      — managing multiple clients
      1× markAsRead
    """

    host      = FIRESTORE_HOST
    wait_time = between(2, 5)   # providers are busier / slower to respond

    def on_start(self):
        idx = random.randint(1, NUM_PAIRS)
        self._pair_idx    = idx
        self._customer_id = f"customer_{idx:04d}"
        self.room_id      = f"lt_c{idx:04d}_p{idx:04d}"

        email = f"provider_{idx:04d}@loadtest.anyskill.com"
        self.auth = _TokenStore(self.client, email, TEST_PASSWORD)
        try:
            _ = self.auth.uid
        except RuntimeError:
            self.environment.runner.quit()

    @task(4)
    def poll_history(self):
        self._get_history()

    @task(3)
    def reply_to_customer(self):
        text = random.choice(PROVIDER_REPLIES)
        self._send_message(self._customer_id, text)
        self._update_chat_metadata(self._customer_id, text)

    @task(2)
    def check_chat_list(self):
        self._list_my_chats()

    @task(1)
    def mark_as_read(self):
        self._get_chat_doc()
        self._mark_as_read()


# ─── Load shape: gradual ramp to 2,000 concurrent users ──────────────────────

# Set LOCUST_SHAPE=1 to activate the 45-minute ramp shape.
# When unset, --users / --spawn-rate / --run-time CLI flags are respected.
if os.getenv("LOCUST_SHAPE", "0") == "1":
    from locust import LoadTestShape

    class AnySkillLoadShape(LoadTestShape):
        """
        Realistic traffic ramp for a marketplace chat product.

        Min  0- 2   Warm-up:        100 users,  spawn  5/s
        Min  2- 7   Light load:     200 users,  spawn 10/s
        Min  7-17   Ramp-up:      1 000 users,  spawn 50/s
        Min 17-27   Peak (full):  2 000 users,  spawn 100/s
        Min 27-37   Sustained:    2 000 users   (hold)
        Min 37-42   Cool-down:      500 users,  spawn 50/s
        Min 42-45   Drain:            0 users,  spawn 50/s
        """

        stages = [
            {"duration":  120, "users":  100, "spawn_rate":  5},
            {"duration":  420, "users":  200, "spawn_rate": 10},
            {"duration": 1020, "users": 1000, "spawn_rate": 50},
            {"duration": 1620, "users": 2000, "spawn_rate": 100},
            {"duration": 2220, "users": 2000, "spawn_rate":   0},
            {"duration": 2520, "users":  500, "spawn_rate":  50},
            {"duration": 2700, "users":    0, "spawn_rate":  50},
        ]

        def tick(self):
            run_time = self.get_run_time()
            for stage in self.stages:
                if run_time < stage["duration"]:
                    spawn = stage["spawn_rate"] if stage["spawn_rate"] > 0 else 1
                    return stage["users"], spawn
            return None  # end the test

    # end AnySkillLoadShape


# ─── Event hooks: custom reporting ───────────────────────────────────────────

_SLOW_THRESHOLD_MS = 3_000   # flag anything slower than 3 s
_slow_requests: list[tuple[str, float]] = []


@events.request.add_listener
def on_request(
    request_type, name, response_time, response_length,
    response, exception, context, **kwargs
):
    if exception:
        print(f"[EXCEPTION] {name}: {exception}")
    elif response_time > _SLOW_THRESHOLD_MS:
        _slow_requests.append((name, response_time))
        if len(_slow_requests) <= 20:   # avoid flooding stdout
            print(f"[SLOW] {name}: {response_time:.0f} ms")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    mode = "EMULATOR" if _EMULATOR else "PRODUCTION FIREBASE"
    print(f"\n{'='*64}")
    print(f"  AnySkill Firebase Stress Test -- Starting")
    print(f"  Target  : {mode}")
    print(f"  Project : {PROJECT_ID}")
    print(f"  Pairs   : {NUM_PAIRS} customers + {NUM_PAIRS} providers")
    print(f"  Ops     : sendMessage, getHistory, listMyChats, markAsRead, Auth")
    print(f"{'='*64}\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    stats = environment.stats
    print("\n" + "=" * 72)
    print("  AnySkill Load Test — Final Report")
    print("=" * 72)
    header = f"  {'Endpoint':<40} {'Req':>6} {'Fail':>6} {'p50':>7} {'p95':>7} {'p99':>7}"
    print(header)
    print("-" * 72)

    for key in sorted(stats.entries.keys()):
        s   = stats.entries[key]
        p50 = s.get_response_time_percentile(0.50) or 0
        p95 = s.get_response_time_percentile(0.95) or 0
        p99 = s.get_response_time_percentile(0.99) or 0
        flag = " ◄ SLOW" if p95 > _SLOW_THRESHOLD_MS else ""
        print(
            f"  {key[1]:<40} {s.num_requests:>6} {s.num_failures:>6} "
            f"{p50:>6.0f}ms {p95:>6.0f}ms {p99:>6.0f}ms{flag}"
        )

    print("=" * 72)

    total_rps = stats.total.current_rps
    total_fail_rate = (
        (stats.total.num_failures / stats.total.num_requests * 100)
        if stats.total.num_requests else 0
    )
    print(f"\n  RPS at end: {total_rps:.1f}")
    print(f"  Failure rate: {total_fail_rate:.2f}%")

    if _slow_requests:
        print(f"\n  Top slow requests (>{_SLOW_THRESHOLD_MS}ms): {len(_slow_requests)} occurrences")
        counts: dict[str, int] = {}
        for name, _ in _slow_requests:
            counts[name] = counts.get(name, 0) + 1
        for name, c in sorted(counts.items(), key=lambda x: -x[1])[:10]:
            print(f"    {c:>4}×  {name}")

    print("\n  Bottleneck hints:")
    for key in stats.entries:
        s   = stats.entries[key]
        p99 = s.get_response_time_percentile(0.99) or 0
        if p99 > 5_000:
            print(f"    ✗ {key[1]} — p99={p99:.0f}ms → likely write contention or quota limit")
        elif s.num_failures / max(s.num_requests, 1) > 0.05:
            print(f"    ✗ {key[1]} — {s.num_failures} failures → check Firestore rules / quota")
    print()
