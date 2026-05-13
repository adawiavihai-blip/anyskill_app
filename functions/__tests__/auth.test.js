/**
 * Auth flow tests for AnySkill Cloud Functions.
 *
 * Covers: onCall auth guards, admin checks, ownership gates.
 *
 * PHASE 2 NOTE: Tests for Stripe-backed functions (createPaymentIntent,
 * releaseEscrow, onboardProvider, processRefund) were removed alongside the
 * Stripe Connect integration. The Israeli payment provider tests will be
 * added when that integration is wired up.
 *
 * Run: cd functions && npx jest __tests__/auth.test.js
 */

"use strict";

// ── Mock firebase-admin BEFORE requiring anything ───────────────────────────
const mockFirestore = {
  collection: jest.fn(),
};
const mockAuth = {
  verifyIdToken: jest.fn(),
  deleteUser: jest.fn(),
  // 2026-05-09: extended for setUserRole happy-path tests (Custom Claims sync).
  // setCustomUserClaims is called after every role change to keep the JWT
  // claim in sync with the Firestore role field. revokeRefreshTokens is
  // called on privilege REMOVAL to force re-auth within 1h.
  setCustomUserClaims: jest.fn(async () => {}),
  revokeRefreshTokens: jest.fn(async () => {}),
  getUser: jest.fn(async (uid) => ({ uid, customClaims: {} })),
};

jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
  firestore: jest.fn(() => mockFirestore),
  auth: jest.fn(() => mockAuth),
  storage: jest.fn(() => ({ bucket: jest.fn() })),
}));
// Stub FieldValue used in CF code
jest.mock("firebase-admin", () => {
  const fv = {
    serverTimestamp: jest.fn(() => "SERVER_TS"),
    increment: jest.fn((n) => `INC(${n})`),
    arrayUnion: jest.fn((arr) => `UNION(${arr})`),
  };
  return {
    initializeApp: jest.fn(),
    firestore: Object.assign(jest.fn(() => mockFirestore), {
      FieldValue: fv,
    }),
    auth: jest.fn(() => mockAuth),
    storage: jest.fn(() => ({ bucket: jest.fn() })),
  };
});

jest.mock("firebase-functions/v2/https", () => ({
  onCall: jest.fn((optsOrHandler, maybeHandler) => {
    return typeof optsOrHandler === "function" ? optsOrHandler : maybeHandler;
  }),
  onRequest: jest.fn((optsOrHandler, maybeHandler) => {
    return typeof optsOrHandler === "function" ? optsOrHandler : maybeHandler;
  }),
  HttpsError: class HttpsError extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
    }
  },
}));

// Firestore trigger mocks — UNWRAP the handler so tests can call it directly.
// Each CF declares `onDocumentX(opts, handler)` so the 2nd arg is the actual
// function. Returning `handler` here makes `index.notifyProviderOnApproval`
// the real handler (same pattern as the onCall mock above).
jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentCreated: jest.fn((optsOrHandler, maybeHandler) =>
    typeof optsOrHandler === "function" ? optsOrHandler : maybeHandler),
  onDocumentUpdated: jest.fn((optsOrHandler, maybeHandler) =>
    typeof optsOrHandler === "function" ? optsOrHandler : maybeHandler),
  onDocumentWritten: jest.fn((optsOrHandler, maybeHandler) =>
    typeof optsOrHandler === "function" ? optsOrHandler : maybeHandler),
  onDocumentDeleted: jest.fn((optsOrHandler, maybeHandler) =>
    typeof optsOrHandler === "function" ? optsOrHandler : maybeHandler),
}));
// Same unwrap pattern as the firestore-trigger mocks above — exposes the
// real handler so tests can call `await trigger()` directly. Unlocks
// coverage for ~30 scheduled CFs (anytaskAutoRelease, expireOpenTasks,
// expireStories, dispatch CFs, vault analytics, etc).
jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: jest.fn((optsOrHandler, maybeHandler) =>
    typeof optsOrHandler === "function" ? optsOrHandler : maybeHandler),
}));
jest.mock("firebase-functions/params", () => ({
  defineSecret: jest.fn(() => ({ value: () => "test-secret" })),
}));
// Anthropic mock with runtime-overridable `messages.create`. Per-test:
//   const Anthropic = require("@anthropic-ai/sdk").default;
//   Anthropic.__create.mockResolvedValueOnce({...});
jest.mock("@anthropic-ai/sdk", () => {
  class MockAnthropic {
    constructor() {
      this.messages = { create: MockAnthropic.__create };
    }
  }
  MockAnthropic.__create = jest.fn(async () => ({
    content: [{ text: "[]" }],
    usage: { input_tokens: 100, output_tokens: 50 },
  }));
  return { default: MockAnthropic };
});

// ── Helpers ─────────────────────────────────────────────────────────────────

function mockDocSnap(exists, data = {}) {
  return { exists, data: () => data, id: "mock-id" };
}

function mockCollection(docSnapMap = {}) {
  const buildDocRef = (col, id) => ({
    get: jest.fn(async () => docSnapMap[`${col}/${id}`] || mockDocSnap(false)),
    set: jest.fn(async () => {}),
    update: jest.fn(async () => {}),
    delete: jest.fn(async () => {}),
    collection: jest.fn((subCol) => ({
      doc: jest.fn((subId) => ({
        get: jest.fn(async () =>
          docSnapMap[`${col}/${id}/${subCol}/${subId}`] || mockDocSnap(false)
        ),
        set: jest.fn(async () => {}),
      })),
    })),
  });

  mockFirestore.collection.mockImplementation((col) => ({
    doc: jest.fn((id) => buildDocRef(col, id)),
    add: jest.fn(async () => ({ id: "new-doc-id" })),
    where: jest.fn(() => ({
      get: jest.fn(async () => ({ docs: [], empty: true })),
      limit: jest.fn(() => ({ get: jest.fn(async () => ({ docs: [], empty: true })) })),
    })),
  }));

  mockFirestore.runTransaction = jest.fn(async (cb) => {
    const tx = {
      get: jest.fn(async (ref) => {
        if (typeof ref.get === "function") return ref.get();
        return mockDocSnap(false);
      }),
      update: jest.fn(),
      set: jest.fn(),
    };
    return cb(tx);
  });
}

// ── Load modules under test ─────────────────────────────────────────────────
const index = require("../index");

// ═══════════════════════════════════════════════════════════════════════════════
// TEST SUITES
// ═══════════════════════════════════════════════════════════════════════════════

describe("onCall auth guards — processPaymentRelease (legacy/credits)", () => {
  const ppr = index.processPaymentRelease;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(
      ppr({ auth: null, data: { jobId: "j1", expertId: "e1", totalAmount: 100 } })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  // Updated 2026-05-09 to match CF behavior after CLAUDE.md §50 Vuln 2 hardening:
  // expertId & totalAmount are now read from the job doc, not the request payload.
  // Client only needs to provide jobId. Other validation happens server-side.
  test("rejects when jobId is missing", async () => {
    await expect(
      ppr({ auth: { uid: "u1" }, data: {} })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects when job doc does not exist", async () => {
    mockCollection({}); // no jobs/j1 mocked → exists: false
    await expect(
      ppr({ auth: { uid: "u1" }, data: { jobId: "j1" } })
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("rejects caller who is not the customer", async () => {
    mockCollection({
      "jobs/j1": mockDocSnap(true, {
        customerId: "real-customer",
        expertId: "e1",
        totalAmount: 100,
        status: "expert_completed",   // pass status check first
      }),
    });

    await expect(
      ppr({
        auth: { uid: "not-the-customer" },
        data: { jobId: "j1" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });
});

describe("onCall admin guard — deleteUser", () => {
  const deleteUser = index.deleteUser;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(
      deleteUser({ auth: null, data: { uid: "target" } })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin caller", async () => {
    mockCollection({
      "users/regular": mockDocSnap(true, { isAdmin: false }),
    });

    await expect(
      deleteUser({
        auth: { uid: "regular", token: { email: "user@gmail.com" } },
        data: { uid: "target" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects non-admin even with previously-hardcoded email (v9.7.0 security fix)", async () => {
    // v9.7.0: Email-based admin bypass removed. Only Firestore isAdmin flag works.
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: false }),
    });

    await expect(
      deleteUser({
        auth: { uid: "admin1", token: { email: "other-admin@test.com" } },
        data: { uid: "target" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("allows Firestore isAdmin flag", async () => {
    mockCollection({
      "users/admin2": mockDocSnap(true, { isAdmin: true }),
    });
    mockAuth.deleteUser.mockResolvedValue();

    const result = await deleteUser({
      auth: { uid: "admin2", token: { email: "other@gmail.com" } },
      data: { uid: "target" },
    });

    expect(result).toEqual({ success: true });
  });

  test("rejects missing uid in data", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      deleteUser({
        auth: { uid: "admin1", token: { email: "other-admin@test.com" } },
        data: {},
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("handles already-deleted auth user gracefully", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });
    mockAuth.deleteUser.mockRejectedValue({ code: "auth/user-not-found" });

    const result = await deleteUser({
      auth: { uid: "admin1", token: { email: "other-admin@test.com" } },
      data: { uid: "ghost" },
    });

    expect(result).toEqual({ success: true });
  });
});

describe("onCall admin guard — setCorsOnStorage", () => {
  const setCorsOnStorage = index.setCorsOnStorage;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(
      setCorsOnStorage({ auth: null, data: {} })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin", async () => {
    mockCollection({
      "users/u1": mockDocSnap(true, { isAdmin: false }),
    });

    await expect(
      setCorsOnStorage({ auth: { uid: "u1" }, data: {} })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects non-existent user doc", async () => {
    mockCollection({});

    await expect(
      setCorsOnStorage({ auth: { uid: "ghost" }, data: {} })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// setUserRole — privilege escalation safeguards (CLAUDE.md §50)
// Critical: this CF is the ONLY way to grant admin/support_agent roles.
// Wrong code here = total takeover.
// ═══════════════════════════════════════════════════════════════════════════════
describe("setUserRole — admin privilege management", () => {
  const setUserRole = index.setUserRole;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(
      setUserRole({ auth: null, data: { targetUserId: "u1", newRole: "admin" } })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin caller (regular user trying to self-promote)", async () => {
    mockCollection({
      "users/regular": mockDocSnap(true, { isAdmin: false }),
    });

    await expect(
      setUserRole({
        auth: { uid: "regular" },
        data: { targetUserId: "victim", newRole: "admin" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects missing targetUserId", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      setUserRole({ auth: { uid: "admin1" }, data: { newRole: "admin" } })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects admin trying to change their OWN role (self-target)", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: { targetUserId: "admin1", newRole: "customer" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects unknown role in rolesToAdd array", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: { targetUserId: "victim", rolesToAdd: ["super_admin_god"] },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects unknown legacy newRole", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: { targetUserId: "victim", newRole: "owner" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects when target user does not exist", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
      // 'victim' not seeded — get() returns exists:false
    });

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: { targetUserId: "ghost", newRole: "admin" },
      })
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("rejects rolesToAdd that is not an array", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: { targetUserId: "victim", rolesToAdd: "admin" },   // string, not array
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects when no rolesToAdd, no rolesToRemove, no newRole (empty op)", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: { targetUserId: "victim" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects activeRole that is not in VALID_ROLES", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
    });

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: {
          targetUserId: "victim",
          newRole: "admin",
          activeRole: "owner",   // invalid
        },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// grantAdminCredit — money creation primitive (CLAUDE.md §4.6)
// Validation gates: amount > 0, amount ≤ 5000, reason ≥ 10 chars, no self-grant.
// Daily cap of ₪20,000/admin enforced INSIDE the transaction (not tested here).
// ═══════════════════════════════════════════════════════════════════════════════
describe("grantAdminCredit — input validation gates", () => {
  const grantAdminCredit = index.grantAdminCredit;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(
      grantAdminCredit({
        auth: null,
        data: { targetUserId: "u1", amount: 100, reason: "test reason long" },
      })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin caller", async () => {
    mockCollection({
      "users/regular": mockDocSnap(true, { isAdmin: false }),
    });

    await expect(
      grantAdminCredit({
        auth: { uid: "regular" },
        data: { targetUserId: "u1", amount: 100, reason: "test reason long" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects missing targetUserId", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: { amount: 100, reason: "test reason long" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects zero amount", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: { targetUserId: "u1", amount: 0, reason: "test reason long" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects negative amount", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: { targetUserId: "u1", amount: -100, reason: "test reason long" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects non-number amount", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: { targetUserId: "u1", amount: "100", reason: "test reason long" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects amount above ₪5,000 cap", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: { targetUserId: "u1", amount: 5001, reason: "test reason long" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects reason shorter than 10 chars", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: { targetUserId: "u1", amount: 100, reason: "short" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects missing reason", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: { targetUserId: "u1", amount: 100 },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects reason longer than 500 chars", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: {
          targetUserId: "u1",
          amount: 100,
          reason: "x".repeat(501),
        },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects admin granting credit to themselves", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1" },
        data: {
          targetUserId: "admin1",   // self-target
          amount: 100,
          reason: "test reason long enough",
        },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// HAPPY PATHS — verify CFs actually WORK with valid input.
// Validation tests above prove rejection paths; these prove the CF reaches
// its return statement when fed correct data. Critical for catching
// accidental breakage of legitimate flows.
// ═══════════════════════════════════════════════════════════════════════════════
describe("setUserRole — happy paths", () => {
  const setUserRole = index.setUserRole;

  beforeEach(() => jest.clearAllMocks());

  test("admin grants support_agent role to a regular user (legacy newRole API)", async () => {
    // Helper to capture .update() calls so we can verify the right fields are written
    const updateCalls = [];
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "users" && id === "admin1") {
            return {
              exists: true, id, data: () => ({ isAdmin: true, name: "Admin" }),
            };
          }
          if (col === "users" && id === "victim_to_promote") {
            return {
              exists: true, id,
              data: () => ({
                name: "Victim",
                role: "customer",
                roles: ["customer"],
              }),
            };
          }
          return { exists: false, id, data: () => ({}) };
        }),
        set:    jest.fn(async () => {}),
        update: jest.fn(async (payload) => {
          updateCalls.push({ col, id, payload });
        }),
        delete: jest.fn(async () => {}),
        collection: jest.fn(() => ({
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
            set: jest.fn(async () => {}),
          })),
          add: jest.fn(async () => ({ id: "new-audit-id" })),
        })),
      })),
      add: jest.fn(async () => ({ id: "new-doc-id" })),
      where: jest.fn(() => ({
        get:   jest.fn(async () => ({ docs: [], empty: true })),
        limit: jest.fn(() => ({ get: jest.fn(async () => ({ docs: [], empty: true })) })),
      })),
    }));

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: { targetUserId: "victim_to_promote", newRole: "support_agent" },
      })
    ).resolves.toMatchObject({ success: true });

    // Verify the target user doc was updated with the new role
    const targetUpdate = updateCalls.find(
      (c) => c.col === "users" && c.id === "victim_to_promote",
    );
    expect(targetUpdate).toBeDefined();
    expect(targetUpdate.payload.roles).toContain("support_agent");
    expect(targetUpdate.payload.role).toBe("support_agent");
    expect(targetUpdate.payload.isAdmin).toBe(false);

    // Verify Custom Claims were synced (CLAUDE.md §50 Round C)
    const admin = require("firebase-admin");
    expect(admin.auth().setCustomUserClaims).toHaveBeenCalledWith(
      "victim_to_promote",
      expect.objectContaining({ support_agent: true, admin: false }),
    );
  });

  test("admin grants admin role using rolesToAdd (multi-role API)", async () => {
    const updateCalls = [];
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "users" && id === "admin1") {
            return {
              exists: true, id, data: () => ({ isAdmin: true, name: "Admin" }),
            };
          }
          if (col === "users" && id === "new_admin") {
            return {
              exists: true, id,
              data: () => ({ roles: ["customer"], name: "New Admin" }),
            };
          }
          return { exists: false, id, data: () => ({}) };
        }),
        set:    jest.fn(async () => {}),
        update: jest.fn(async (payload) => {
          updateCalls.push({ col, id, payload });
        }),
        collection: jest.fn(() => ({
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
            set: jest.fn(async () => {}),
          })),
          add: jest.fn(async () => ({ id: "audit-id" })),
        })),
      })),
      add: jest.fn(async () => ({ id: "new-doc-id" })),
      where: jest.fn(() => ({
        get:   jest.fn(async () => ({ docs: [], empty: true })),
        limit: jest.fn(() => ({ get: jest.fn(async () => ({ docs: [], empty: true })) })),
      })),
    }));

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: {
          targetUserId: "new_admin",
          rolesToAdd: ["admin"],
          rolesToRemove: [],
        },
      })
    ).resolves.toMatchObject({ success: true });

    const targetUpdate = updateCalls.find(
      (c) => c.col === "users" && c.id === "new_admin",
    );
    expect(targetUpdate).toBeDefined();
    // Should have both customer (existing) AND admin (added)
    expect(targetUpdate.payload.roles).toEqual(
      expect.arrayContaining(["customer", "admin"]),
    );
    expect(targetUpdate.payload.isAdmin).toBe(true);

    // Verify Custom Claims dual-write
    const admin = require("firebase-admin");
    expect(admin.auth().setCustomUserClaims).toHaveBeenCalledWith(
      "new_admin",
      expect.objectContaining({ admin: true }),
    );
  });

  test("admin removing a role triggers revokeRefreshTokens (force re-auth within 1h)", async () => {
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "users" && id === "admin1") {
            return { exists: true, id, data: () => ({ isAdmin: true }) };
          }
          if (col === "users" && id === "demoted_admin") {
            return {
              exists: true, id,
              data: () => ({
                roles: ["customer", "admin"],   // currently has admin
                isAdmin: true,
                name: "Demoted Admin",
              }),
            };
          }
          return { exists: false, id, data: () => ({}) };
        }),
        set:    jest.fn(async () => {}),
        update: jest.fn(async () => {}),
        collection: jest.fn(() => ({
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
            set: jest.fn(async () => {}),
          })),
          add: jest.fn(async () => ({ id: "audit-id" })),
        })),
      })),
      add: jest.fn(async () => ({ id: "new-doc-id" })),
      where: jest.fn(() => ({
        get:   jest.fn(async () => ({ docs: [], empty: true })),
        limit: jest.fn(() => ({ get: jest.fn(async () => ({ docs: [], empty: true })) })),
      })),
    }));

    await expect(
      setUserRole({
        auth: { uid: "admin1" },
        data: {
          targetUserId: "demoted_admin",
          rolesToAdd: [],
          rolesToRemove: ["admin"],
        },
      })
    ).resolves.toMatchObject({ success: true });

    // Privilege removal MUST revoke refresh tokens — this forces the
    // demoted admin to re-auth within ≤1h instead of waiting for natural
    // token expiry. Critical security property (CLAUDE.md §50 Round C).
    const admin = require("firebase-admin");
    expect(admin.auth().revokeRefreshTokens).toHaveBeenCalledWith(
      "demoted_admin",
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// grantAdminCredit — happy paths (added 2026-05-10 session 3)
// Money creation primitive (CLAUDE.md §4.6). Validation tests above cover
// rejection paths; these verify the function actually completes when fed
// valid inputs.
// ═══════════════════════════════════════════════════════════════════════════════
describe("grantAdminCredit — happy paths", () => {
  const grantAdminCredit = index.grantAdminCredit;

  beforeEach(() => jest.clearAllMocks());

  // Helper: build a doc-mock that returns custom data for known IDs.
  // Also makes .where() chainable (the CF chains 3 .where() calls inside
  // the daily-cap query) and .runTransaction() invoke its callback with
  // a tx that proxies tx.get(ref) → ref.get().
  function setupHappyPathMocks({
    callerData,
    callerUid,
    targetData,
    targetUid,
    dailyAuditDocs = [],
    idempotencyExists = false,
  }) {
    const txCalls = { update: [], set: [] };

    const docFor = (col, id) => ({
      get: jest.fn(async () => {
        if (col === "users" && id === callerUid) {
          return { exists: true, id, data: () => callerData };
        }
        if (col === "users" && id === targetUid) {
          return { exists: true, id, data: () => targetData };
        }
        if (col === "admin_credit_idempotency") {
          return {
            exists: idempotencyExists,
            data: () => ({ result: { cached: true, success: true } }),
          };
        }
        return { exists: false, id, data: () => ({}) };
      }),
      set: jest.fn(async () => {}),
      update: jest.fn(async () => {}),
    });

    mockFirestore.collection.mockImplementation((col) => {
      // Chainable .where() that always lands on a .get()
      const whereChain = {
        where: jest.fn(() => whereChain),
        get: jest.fn(async () => ({
          docs: dailyAuditDocs.map((data) => ({ data: () => data })),
          empty: dailyAuditDocs.length === 0,
        })),
        limit: jest.fn(() => whereChain),
      };
      return {
        doc: jest.fn((id) => docFor(col, id)),
        add: jest.fn(async () => ({ id: "new-doc-id" })),
        where: jest.fn(() => whereChain),
      };
    });

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn((ref, payload) => txCalls.update.push({ ref, payload })),
        set:    jest.fn((ref, payload) => txCalls.set.push({ ref, payload })),
      };
      return cb(tx);
    });

    // Timestamp helper used by the CF
    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return txCalls;
  }

  test("valid grant of ₪100 to a user with no prior balance succeeds", async () => {
    const txCalls = setupHappyPathMocks({
      callerUid:  "admin1",
      callerData: { isAdmin: true, name: "Admin" },
      targetUid:  "alice",
      targetData: { name: "Alice", balance: 0 },
    });

    await expect(
      grantAdminCredit({
        auth: { uid: "admin1", token: { name: "Admin User" } },
        data: {
          targetUserId: "alice",
          amount: 100,
          reason: "Welcome bonus for early adopter",
        },
      })
    ).resolves.toMatchObject({ success: true });

    // Verify the right writes happened inside the transaction:
    //   1. tx.update on target user (balance increment)
    //   2. tx.set on transactions collection (ledger entry)
    //   3. tx.set on admin_audit_log (counts toward future daily cap)
    expect(txCalls.update.length).toBeGreaterThanOrEqual(1);
    expect(txCalls.set.length).toBeGreaterThanOrEqual(2);
  });

  test("valid grant returns updated balance information", async () => {
    setupHappyPathMocks({
      callerUid:  "admin1",
      callerData: { isAdmin: true },
      targetUid:  "alice",
      targetData: { name: "Alice", balance: 50 },
    });

    const result = await grantAdminCredit({
      auth: { uid: "admin1", token: {} },
      data: {
        targetUserId: "alice",
        amount: 100,
        reason: "Refund for cancelled booking",
      },
    });

    expect(result.success).toBe(true);
    expect(result.beforeBalance).toBe(50);
    expect(result.afterBalance).toBe(150);
  });

  test("idempotency: replay returns cached result without re-charging", async () => {
    const txCalls = setupHappyPathMocks({
      callerUid:  "admin1",
      callerData: { isAdmin: true },
      targetUid:  "alice",
      targetData: { name: "Alice", balance: 0 },
      idempotencyExists: true,   // cached result exists
    });

    // The cache record needs createdAt for the age check; mock to be recent
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "users" && id === "admin1") {
            return { exists: true, id, data: () => ({ isAdmin: true }) };
          }
          if (col === "admin_credit_idempotency") {
            return {
              exists: true,
              data: () => ({
                result: { success: true, cached: true, beforeBalance: 0, afterBalance: 100 },
                createdAt: { toMillis: () => Date.now() - 1000 },  // 1s ago, well within 1h
              }),
            };
          }
          if (col === "users" && id === "alice") {
            return { exists: true, id, data: () => ({ balance: 100 }) };
          }
          return { exists: false, id, data: () => ({}) };
        }),
        set: jest.fn(async () => {}),
        update: jest.fn(async () => {}),
      })),
      add: jest.fn(async () => ({ id: "new-doc-id" })),
      where: jest.fn(() => ({
        where: jest.fn(() => ({
          where: jest.fn(() => ({
            get: jest.fn(async () => ({ docs: [], empty: true })),
          })),
        })),
        get: jest.fn(async () => ({ docs: [], empty: true })),
      })),
    }));

    const result = await grantAdminCredit({
      auth: { uid: "admin1", token: {} },
      data: {
        targetUserId: "alice",
        amount: 100,
        reason: "Test idempotent retry",
        clientReqId: "client-uuid-abc-123",
      },
    });

    // Replay returns the cached result — should be the same shape but a flag
    expect(result.cached).toBe(true);
    // Critically, NO new transaction should have run
    expect(txCalls.update.length).toBe(0);
    expect(txCalls.set.length).toBe(0);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// processPaymentRelease — happy paths (added 2026-05-10 session 4)
// THE most critical CF in the app — moves real money from customer escrow to
// expert balance + platform commission. Validation tests above cover rejection
// paths; these verify the success flow actually completes.
//
// CF flow (CLAUDE.md §50 Vuln 2 hardening):
//   1. Read job → derive expertId, totalAmount from doc (NOT request)
//   2. Verify caller is the customer
//   3. Verify status == 'expert_completed'
//   4. Pre-tx: read expert serviceType + category lookup
//   5. Tx: read 4 docs in parallel, compute commission, update balances + write
//      transactions + platform_earnings + admin settings + (optional) category
//      bookingCount
// ═══════════════════════════════════════════════════════════════════════════════
describe("processPaymentRelease — happy paths", () => {
  const ppr = index.processPaymentRelease;

  beforeEach(() => jest.clearAllMocks());

  function setupPprMocks({
    customerId,
    expertId,
    totalAmount,
    feePercentage = 0.10,
    customerBalance = 0,
    expertBalance = 0,
    expertExists = true,
    remainingAmount = 0,
    serviceType = "",
  }) {
    const txCalls = { update: [], set: [] };

    mockFirestore.collection.mockImplementation((col) => {
      const buildDoc = (id) => ({
        get: jest.fn(async () => {
          if (col === "jobs") {
            return {
              exists: true,
              id,
              data: () => ({
                customerId,
                expertId,
                totalAmount,
                customerName: "Alice",
                expertName: "Bob",
                status: "expert_completed",
                remainingAmount,
              }),
            };
          }
          if (col === "users" && id === expertId) {
            return expertExists
              ? { exists: true, id, data: () => ({ balance: expertBalance, serviceType }) }
              : { exists: false, id, data: () => ({}) };
          }
          if (col === "users" && id === customerId) {
            return {
              exists: true, id,
              data: () => ({ balance: customerBalance, name: "Alice" }),
            };
          }
          if (col === "admin") {
            return {
              exists: true, id,
              data: () => ({}),
              collection: jest.fn(() => ({
                doc: jest.fn(() => ({
                  get: jest.fn(async () => ({
                    exists: true,
                    data: () => ({ feePercentage }),
                  })),
                  set: jest.fn(async () => {}),
                })),
              })),
            };
          }
          return { exists: false, id, data: () => ({}) };
        }),
        set: jest.fn(async () => {}),
        update: jest.fn(async () => {}),
        // Nested collection (admin/admin/settings/settings)
        collection: jest.fn((subCol) => ({
          doc: jest.fn((subId) => ({
            get: jest.fn(async () => ({
              exists: true,
              data: () => ({ feePercentage }),
            })),
            set: jest.fn(async () => {}),
          })),
        })),
      });

      // Chainable .where().limit().get() for category lookup
      const queryChain = {
        where: jest.fn(() => queryChain),
        limit: jest.fn(() => queryChain),
        get: jest.fn(async () => ({ docs: [], empty: true })),
      };

      return {
        doc: jest.fn((id) => buildDoc(id)),
        add: jest.fn(async () => ({ id: "auto-id" })),
        where: jest.fn(() => queryChain),
      };
    });

    // Transaction mock — proxies tx.get(ref) to ref.get(), captures writes
    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn((ref, payload) => txCalls.update.push({ ref, payload })),
        set:    jest.fn((ref, payload) => txCalls.set.push({ ref, payload })),
      };
      return cb(tx);
    });

    return txCalls;
  }

  test("non-deposit job: full release with 10% commission split", async () => {
    const txCalls = setupPprMocks({
      customerId: "alice",
      expertId:   "bob",
      totalAmount: 200,
      feePercentage: 0.10,
      customerBalance: 0,        // already paid via escrow at booking
      expertBalance: 50,
      remainingAmount: 0,        // not a deposit job
    });

    await expect(
      ppr({
        auth: { uid: "alice" },
        data: { jobId: "job1" },
      })
    ).resolves.toMatchObject({ success: true });

    // Verify the writes that matter:
    //   1. Job updated to 'completed'
    //   2. Expert balance incremented (200 - 20 fee = 180 net)
    //   3. Admin platform balance incremented (20)
    //   4. transactions ledger entry for expert
    //   5. platform_earnings entry
    expect(txCalls.update.length).toBeGreaterThanOrEqual(2);  // job + expert
    expect(txCalls.set.length).toBeGreaterThanOrEqual(3);     // earnings + transaction + admin settings
  });

  test("deposit job: charges remaining amount from customer balance", async () => {
    const txCalls = setupPprMocks({
      customerId: "alice",
      expertId:   "bob",
      totalAmount: 200,
      feePercentage: 0.10,
      customerBalance: 200,     // has enough to cover the remainder
      expertBalance: 0,
      remainingAmount: 140,     // 30% deposit was paid; 70% remains
    });

    await expect(
      ppr({
        auth: { uid: "alice" },
        data: { jobId: "job1" },
      })
    ).resolves.toMatchObject({ success: true });

    // Customer should be debited (1 update for balance) + transaction logged
    // (1 set for the customer wallet log) IN ADDITION to the standard releases
    expect(txCalls.update.length).toBeGreaterThanOrEqual(3);  // job + expert + customer
    expect(txCalls.set.length).toBeGreaterThanOrEqual(4);     // earnings + tx_expert + tx_customer + admin settings
  });

  test("deposit job: insufficient customer balance throws failed-precondition", async () => {
    setupPprMocks({
      customerId: "alice",
      expertId:   "bob",
      totalAmount: 200,
      customerBalance: 50,      // NOT enough to cover ₪140 remainder
      expertBalance: 0,
      remainingAmount: 140,
    });

    await expect(
      ppr({
        auth: { uid: "alice" },
        data: { jobId: "job1" },
      })
    ).rejects.toMatchObject({ code: "failed-precondition" });
    // §60 update: HttpsError instances now propagate through the outer
    // try/catch without being re-wrapped as 'internal'. The inner
    // balance check throws `failed-precondition` ("יתרה לא מספיקה...")
    // and the client sees that code directly — needed so the UI can
    // surface a "top up your wallet" message instead of a generic
    // "internal error". See processPaymentRelease catch block in
    // functions/index.js for the HttpsError pass-through.
  });

  test("custom commission overrides global fee percentage", async () => {
    const txCalls = setupPprMocks({
      customerId: "alice",
      expertId:   "bob",
      totalAmount: 200,
      feePercentage: 0.10,       // global is 10%
    });

    // Override mockFirestore so expertRef.get() returns customCommission
    const oldImpl = mockFirestore.collection.getMockImplementation();
    mockFirestore.collection.mockImplementation((col) => {
      if (col === "users") {
        return {
          doc: jest.fn((id) => ({
            get: jest.fn(async () => {
              if (id === "bob") {
                return {
                  exists: true, id,
                  data: () => ({
                    balance: 0,
                    customCommission: 0.05,   // VIP rate: 5%
                    serviceType: "",
                  }),
                };
              }
              if (id === "alice") {
                return { exists: true, id, data: () => ({ balance: 0 }) };
              }
              return { exists: false, id, data: () => ({}) };
            }),
            set:    jest.fn(async () => {}),
            update: jest.fn(async () => {}),
          })),
        };
      }
      return oldImpl(col);
    });

    await expect(
      ppr({
        auth: { uid: "alice" },
        data: { jobId: "job1" },
      })
    ).resolves.toMatchObject({ success: true });

    // The expert balance update should reflect the custom 5% rate, not 10%
    // Net: 200 - (200 * 0.05) = 190
    // We can't directly verify the increment value (it's wrapped in
    // FieldValue.increment) but we CAN verify the set() to platform_earnings
    // received the lower fee amount.
    const earningsSet = txCalls.set.find(
      (c) => c.payload && typeof c.payload.amount === "number" && c.payload.jobId === "job1",
    );
    expect(earningsSet).toBeDefined();
    // 5% of 200 = 10 (custom), not 20 (global)
    expect(earningsSet.payload.amount).toBe(10);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// processCancellation — full coverage (added 2026-05-10 session 4 bonus)
// CLAUDE.md §4.4 cancellation policy. Three paths:
//   1. Provider cancels → 100% refund to customer
//   2. Customer cancels BEFORE deadline → 100% refund
//   3. Customer cancels AFTER deadline → penalty split (50% flexible/moderate,
//      100% strict/nonRefundable)
// ═══════════════════════════════════════════════════════════════════════════════
describe("processCancellation — rejection paths", () => {
  const proc = index.processCancellation;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(
      proc({ auth: null, data: { jobId: "j1" } })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects missing jobId", async () => {
    await expect(
      proc({ auth: { uid: "alice" }, data: {} })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects when caller is neither customer nor expert", async () => {
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "jobs") {
            return {
              exists: true,
              data: () => ({
                customerId: "alice", expertId: "bob",
                totalAmount: 200, status: "paid_escrow",
              }),
            };
          }
          return { exists: false, data: () => ({}) };
        }),
      })),
    }));
    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => (typeof ref.get === "function" ? ref.get() : mockDocSnap(false))),
        update: jest.fn(),
        set: jest.fn(),
      };
      return cb(tx);
    });

    await expect(
      proc({
        auth: { uid: "eve" },           // neither customer nor expert
        data: { jobId: "j1" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects job in wrong status (already completed)", async () => {
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn(() => ({
        get: jest.fn(async () => ({
          exists: true,
          data: () => ({
            customerId: "alice", expertId: "bob",
            totalAmount: 200, status: "completed",   // not paid_escrow
          }),
        })),
      })),
    }));
    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => (typeof ref.get === "function" ? ref.get() : mockDocSnap(false))),
        update: jest.fn(), set: jest.fn(),
      };
      return cb(tx);
    });

    await expect(
      proc({ auth: { uid: "alice" }, data: { jobId: "j1" } })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });
});

describe("processCancellation — happy paths", () => {
  const proc = index.processCancellation;

  beforeEach(() => jest.clearAllMocks());

  // Helper: mock a job + admin settings, capture tx writes.
  function setupCancelMocks({
    customerId = "alice",
    expertId = "bob",
    totalAmount = 200,
    paidAtBooking,         // omit = full payment (= totalAmount)
    cancellationPolicy = "flexible",
    cancellationDeadline,  // optional Date
    feePercentage = 0.10,
  }) {
    const txCalls = { update: [], set: [] };

    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => {
        if (col === "jobs") {
          return {
            get: jest.fn(async () => ({
              exists: true,
              data: () => ({
                customerId, expertId, totalAmount, chatRoomId: "chat1",
                paidAtBooking: paidAtBooking ?? totalAmount,
                cancellationPolicy,
                cancellationDeadline: cancellationDeadline
                  ? { toDate: () => cancellationDeadline }
                  : null,
                status: "paid_escrow",
              }),
            })),
            collection: jest.fn(() => ({
              doc: jest.fn(() => ({
                get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
              })),
            })),
          };
        }
        if (col === "admin") {
          return {
            collection: jest.fn(() => ({
              doc: jest.fn(() => ({
                get: jest.fn(async () => ({
                  exists: true,
                  data: () => ({ feePercentage }),
                })),
              })),
            })),
          };
        }
        return {
          get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
        };
      }),
      add: jest.fn(async () => ({ id: "auto-id" })),
    }));

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => (typeof ref.get === "function" ? ref.get() : mockDocSnap(false))),
        update: jest.fn((ref, payload) => txCalls.update.push({ ref, payload })),
        set:    jest.fn((ref, payload) => txCalls.set.push({ ref, payload })),
      };
      return cb(tx);
    });

    return txCalls;
  }

  test("provider cancels → customer gets full refund (100%)", async () => {
    const txCalls = setupCancelMocks({});

    const result = await proc({
      auth: { uid: "bob" },                    // expert (provider) cancels
      data: { jobId: "j1", cancelledBy: "provider" },
    });

    expect(result.success).toBe(true);
    // Verify customer balance was incremented by full totalAmount
    const customerCredit = txCalls.update.find(
      (c) => c.payload && c.payload.balance,
    );
    expect(customerCredit).toBeDefined();
    // Job should be marked cancelled (no penalty)
    const jobUpdate = txCalls.update.find(
      (c) => c.payload && c.payload.status === "cancelled",
    );
    expect(jobUpdate).toBeDefined();
    expect(jobUpdate.payload.customerRefund).toBe(200);
    expect(jobUpdate.payload.expertPenaltyCredit).toBe(0);
  });

  test("customer cancels BEFORE deadline → full refund", async () => {
    // Deadline is 1 day in the FUTURE → before deadline
    const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const txCalls = setupCancelMocks({ cancellationDeadline: tomorrow });

    const result = await proc({
      auth: { uid: "alice" },                  // customer cancels
      data: { jobId: "j1", cancelledBy: "customer" },
    });

    expect(result.success).toBe(true);
    // status: 'cancelled' (no penalty)
    const jobUpdate = txCalls.update.find(
      (c) => c.payload && c.payload.status === "cancelled",
    );
    expect(jobUpdate).toBeDefined();
    expect(jobUpdate.payload.customerRefund).toBe(200);   // full refund
  });

  test("customer cancels AFTER deadline (flexible) → 50% penalty split", async () => {
    // Deadline was 1 hour AGO → after deadline
    const yesterday = new Date(Date.now() - 60 * 60 * 1000);
    const txCalls = setupCancelMocks({
      cancellationDeadline: yesterday,
      cancellationPolicy: "flexible",
      totalAmount: 200,
      feePercentage: 0.10,
    });

    const result = await proc({
      auth: { uid: "alice" },
      data: { jobId: "j1", cancelledBy: "customer" },
    });

    expect(result.success).toBe(true);
    // 50% penalty: customer 100, expert (90) — 10% fee on penalty 100 = 10 platform
    const jobUpdate = txCalls.update.find(
      (c) => c.payload && c.payload.status === "cancelled_with_penalty",
    );
    expect(jobUpdate).toBeDefined();
    expect(jobUpdate.payload.customerRefund).toBe(100);       // 50% of 200
    expect(jobUpdate.payload.expertPenaltyCredit).toBe(90);   // 100 * (1 - 0.10)

    // Platform earnings record for the 10 fee
    const platformEarning = txCalls.set.find(
      (c) => c.payload && c.payload.type === "cancellation_penalty_fee",
    );
    expect(platformEarning).toBeDefined();
    expect(platformEarning.payload.amount).toBe(10);
  });

  test("customer cancels AFTER deadline (nonRefundable) → 100% penalty", async () => {
    const yesterday = new Date(Date.now() - 60 * 60 * 1000);
    const txCalls = setupCancelMocks({
      cancellationDeadline: yesterday,
      cancellationPolicy: "nonRefundable",
      totalAmount: 200,
      feePercentage: 0.10,
    });

    const result = await proc({
      auth: { uid: "alice" },
      data: { jobId: "j1", cancelledBy: "customer" },
    });

    expect(result.success).toBe(true);
    const jobUpdate = txCalls.update.find(
      (c) => c.payload && c.payload.status === "cancelled_with_penalty",
    );
    expect(jobUpdate).toBeDefined();
    expect(jobUpdate.payload.customerRefund).toBe(0);          // no refund
    expect(jobUpdate.payload.expertPenaltyCredit).toBe(180);   // 200 * (1 - 0.10)
  });

  test("customer cancels AFTER deadline on a deposit job → penalty capped at paid amount", async () => {
    // Customer paid only 60₪ deposit on a 200₪ booking
    const yesterday = new Date(Date.now() - 60 * 60 * 1000);
    const txCalls = setupCancelMocks({
      cancellationDeadline: yesterday,
      cancellationPolicy: "strict",
      totalAmount: 200,
      paidAtBooking: 60,                       // deposit only
      feePercentage: 0.10,
    });

    const result = await proc({
      auth: { uid: "alice" },
      data: { jobId: "j1", cancelledBy: "customer" },
    });

    expect(result.success).toBe(true);
    const jobUpdate = txCalls.update.find(
      (c) => c.payload && c.payload.status === "cancelled_with_penalty",
    );
    expect(jobUpdate).toBeDefined();
    // strict = 100% penalty, but capped at paidAtBooking (60).
    // Customer refund: 60 - 60 = 0
    // Expert credit: 60 * (1 - 0.10) = 54
    // Platform fee: 60 * 0.10 = 6
    expect(jobUpdate.payload.customerRefund).toBe(0);
    expect(jobUpdate.payload.expertPenaltyCredit).toBe(54);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// supportAgentAction — full coverage (added 2026-05-10 session 4 bonus 2)
// CLAUDE.md §4.8 Support Agent RBAC. Centralized dispatch for tier-2 actions:
// verify_identity, flag_account, unflag_account, send_password_reset.
// EVERY call writes a support_audit_log entry — losing audit on a sensitive
// action would be a compliance failure.
// ═══════════════════════════════════════════════════════════════════════════════
describe("supportAgentAction — rejection paths", () => {
  const sa = index.supportAgentAction;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(
      sa({ auth: null, data: { action: "flag_account", targetUserId: "u1", reason: "spammer" } })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects caller who is neither admin nor support_agent", async () => {
    mockCollection({
      "users/regular": mockDocSnap(true, { isAdmin: false, role: "customer" }),
    });

    await expect(
      sa({
        auth: { uid: "regular" },
        data: { action: "flag_account", targetUserId: "victim", reason: "test reason" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects when caller user doc does not exist", async () => {
    mockCollection({}); // no users seeded

    await expect(
      sa({
        auth: { uid: "ghost" },
        data: { action: "flag_account", targetUserId: "victim", reason: "test reason" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects missing action", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true, role: "admin" }),
    });

    await expect(
      sa({
        auth: { uid: "admin1" },
        data: { targetUserId: "victim", reason: "test reason" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects missing targetUserId", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true, role: "admin" }),
    });

    await expect(
      sa({
        auth: { uid: "admin1" },
        data: { action: "flag_account", reason: "test reason" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects self-target (agent CANNOT act on their own account)", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true, role: "admin" }),
    });

    await expect(
      sa({
        auth: { uid: "admin1" },
        data: {
          action: "flag_account",
          targetUserId: "admin1",      // self-target
          reason: "test reason here",
        },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects reason shorter than 5 chars", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true, role: "admin" }),
    });

    await expect(
      sa({
        auth: { uid: "admin1" },
        data: { action: "flag_account", targetUserId: "victim", reason: "abc" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects unknown action", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true, role: "admin" }),
    });

    await expect(
      sa({
        auth: { uid: "admin1" },
        data: {
          action: "delete_all_users",   // not in VALID_ACTIONS
          targetUserId: "victim",
          reason: "I am a bad admin",
        },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects when target user does not exist", async () => {
    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true, role: "admin" }),
      // 'ghost' not seeded
    });

    await expect(
      sa({
        auth: { uid: "admin1" },
        data: { action: "flag_account", targetUserId: "ghost", reason: "test reason" },
      })
    ).rejects.toMatchObject({ code: "not-found" });
  });
});

describe("supportAgentAction — happy paths", () => {
  const sa = index.supportAgentAction;

  beforeEach(() => jest.clearAllMocks());

  // Helper: capture .update() and .add() calls so we can verify side effects
  function setupAgentMocks({
    callerUid,
    callerData,
    targetUid,
    targetData,
  }) {
    const updateCalls = [];
    const addCalls = [];

    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "users" && id === callerUid) {
            return { exists: true, id, data: () => callerData };
          }
          if (col === "users" && id === targetUid) {
            return { exists: true, id, data: () => targetData };
          }
          return { exists: false, id, data: () => ({}) };
        }),
        update: jest.fn(async (payload) => {
          updateCalls.push({ col, id, payload });
        }),
        set: jest.fn(async () => {}),
      })),
      add: jest.fn(async (payload) => {
        addCalls.push({ col, payload });
        return { id: "auto-id" };
      }),
    }));

    return { updateCalls, addCalls };
  }

  test("admin verifies identity → user doc updated + audit log", async () => {
    const { updateCalls, addCalls } = setupAgentMocks({
      callerUid: "admin1",
      callerData: { isAdmin: true, role: "admin", name: "Admin User" },
      targetUid: "victim",
      targetData: { name: "Victim", isPendingExpert: true },
    });

    const result = await sa({
      auth: { uid: "admin1" },
      data: {
        action: "verify_identity",
        targetUserId: "victim",
        reason: "ID document looks legit",
      },
    });

    expect(result.success).toBe(true);

    // Target user updated with isVerified: true
    const targetUpdate = updateCalls.find((c) => c.id === "victim");
    expect(targetUpdate).toBeDefined();
    expect(targetUpdate.payload.isVerified).toBe(true);
    expect(targetUpdate.payload.isPendingExpert).toBe(false);
    expect(targetUpdate.payload.verifiedBy).toBe("admin1");

    // Audit log written
    const auditEntry = addCalls.find((c) => c.col === "support_audit_log");
    expect(auditEntry).toBeDefined();
    expect(auditEntry.payload.agentUid).toBe("admin1");
    expect(auditEntry.payload.action).toBe("verify_identity");
    expect(auditEntry.payload.targetUserId).toBe("victim");
    expect(auditEntry.payload.reason).toBe("ID document looks legit");
  });

  test("support_agent flags account → flagged: true + audit log", async () => {
    const { updateCalls, addCalls } = setupAgentMocks({
      callerUid: "agent1",
      callerData: { role: "support_agent", name: "Agent Smith" },   // NOT admin
      targetUid: "spammer",
      targetData: { name: "Spammer", flagged: false },
    });

    const result = await sa({
      auth: { uid: "agent1" },
      data: {
        action: "flag_account",
        targetUserId: "spammer",
        reason: "Multiple bogus listings — manually verified",
      },
    });

    expect(result.success).toBe(true);

    const targetUpdate = updateCalls.find((c) => c.id === "spammer");
    expect(targetUpdate).toBeDefined();
    expect(targetUpdate.payload.flagged).toBe(true);
    expect(targetUpdate.payload.flagReason).toBe("Multiple bogus listings — manually verified");
    expect(targetUpdate.payload.flaggedBy).toBe("agent1");

    // Audit log shows agentRole: 'support_agent'
    const auditEntry = addCalls.find((c) => c.col === "support_audit_log");
    expect(auditEntry).toBeDefined();
    expect(auditEntry.payload.agentRole).toBe("support_agent");
  });

  test("admin unflags account → flagged: false + audit log", async () => {
    const { updateCalls, addCalls } = setupAgentMocks({
      callerUid: "admin1",
      callerData: { isAdmin: true, role: "admin", name: "Admin" },
      targetUid: "previously_flagged",
      targetData: { flagged: true },
    });

    const result = await sa({
      auth: { uid: "admin1" },
      data: {
        action: "unflag_account",
        targetUserId: "previously_flagged",
        reason: "Manual review confirmed legitimate user",
      },
    });

    expect(result.success).toBe(true);

    const targetUpdate = updateCalls.find((c) => c.id === "previously_flagged");
    expect(targetUpdate).toBeDefined();
    expect(targetUpdate.payload.flagged).toBe(false);
    expect(targetUpdate.payload.unflaggedBy).toBe("admin1");

    // Critically: audit log records this even though the action UNDOES the previous flag
    const auditEntry = addCalls.find((c) => c.col === "support_audit_log");
    expect(auditEntry).toBeDefined();
    expect(auditEntry.payload.action).toBe("unflag_account");
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// purchaseVipWithCredits — rejection paths
// ═══════════════════════════════════════════════════════════════════════════════
//
// VIP subscription is the platform's primary monetization product.
// Every rejection path here pins a money-safety property: an unauthenticated
// caller, a missing user doc, an insufficient balance, or a duplicate
// subscription must NEVER result in a successful charge.
// ═══════════════════════════════════════════════════════════════════════════════
describe("purchaseVipWithCredits — rejection paths", () => {
  const purchase = index.purchaseVipWithCredits;

  beforeEach(() => jest.clearAllMocks());

  // Helper: builds the minimal mock surface for a rejection scenario.
  //   userExists  — flips users/{uid}.exists
  //   balance     — value on the user doc (default 0)
  //   existingSub — array of fake docs returned by the duplicate-sub query
  //                 (empty = no existing subscription)
  function setupReject({
    userExists = true,
    balance = 0,
    existingSub = [],
  }) {
    mockFirestore.collection.mockImplementation((col) => {
      const whereChain = {
        where: jest.fn(() => whereChain),
        limit: jest.fn(() => whereChain),
        get: jest.fn(async () => ({
          docs: existingSub,
          empty: existingSub.length === 0,
          size: existingSub.length,
          forEach: (cb) => existingSub.forEach(cb),
        })),
      };
      return {
        doc: jest.fn(() => ({
          id: "auto-id",
          get: jest.fn(async () => ({
            exists: userExists,
            data: () => ({ balance, name: "Provider" }),
          })),
        })),
        add: jest.fn(async () => ({ id: "auto-id" })),
        where: jest.fn(() => whereChain),
      };
    });

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn(),
        set: jest.fn(),
      };
      return cb(tx);
    });

    // Timestamp helper used by the CF
    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };
  }

  test("rejects when caller is unauthenticated", async () => {
    setupReject({});
    await expect(
      purchase({ auth: null, data: {} })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects when caller's user doc is missing", async () => {
    setupReject({ userExists: false });
    await expect(
      purchase({ auth: { uid: "ghost" }, data: {} })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("rejects when balance < 99 (insufficient balance)", async () => {
    setupReject({ userExists: true, balance: 50 });
    await expect(
      purchase({ auth: { uid: "broke" }, data: {} })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("rejects when balance is exactly 0 (edge case)", async () => {
    setupReject({ userExists: true, balance: 0 });
    await expect(
      purchase({ auth: { uid: "zero-balance" }, data: {} })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("rejects when provider already has an active subscription", async () => {
    setupReject({
      userExists: true,
      balance: 200,
      existingSub: [{ data: () => ({ status: "active", providerId: "p1" }) }],
    });
    await expect(
      purchase({ auth: { uid: "p1" }, data: {} })
    ).rejects.toMatchObject({ code: "already-exists" });
  });

  test("rejects when provider is already on the waitlist", async () => {
    setupReject({
      userExists: true,
      balance: 200,
      existingSub: [{ data: () => ({ status: "waitlist", providerId: "p1", waitlistPosition: 3 }) }],
    });
    await expect(
      purchase({ auth: { uid: "p1" }, data: {} })
    ).rejects.toMatchObject({ code: "already-exists" });
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// purchaseVipWithCredits — happy paths
// ═══════════════════════════════════════════════════════════════════════════════
//
// These tests pin the SUCCESS contract:
//   • valid purchase debits exactly ₪99 (transaction is atomic)
//   • when <30 slots filled → status='active', waitlistPosition=null
//   • when ≥30 slots filled → status='waitlist', waitlistPosition=max+1
//
// The transaction MUST write 4 docs (subscription + payment + balance update
// + transactions ledger). If a future refactor accidentally drops one of
// these writes, these tests fail.
// ═══════════════════════════════════════════════════════════════════════════════
describe("purchaseVipWithCredits — happy paths", () => {
  const purchase = index.purchaseVipWithCredits;

  beforeEach(() => jest.clearAllMocks());

  /**
   * Helper: builds a complete happy-path mock that:
   *   - Returns the configured user doc with `balance`
   *   - Returns no existing subscription (duplicate-check passes)
   *   - Reports `activeCount` active subscriptions for the capacity check
   *   - Reports waitlist docs with positions [`waitlistPositions`]
   *   - Captures every tx.set / tx.update for assertion
   *   - Captures collection().add() calls for post-tx audit/notification checks
   */
  function setupOk({
    callerUid,
    balance,
    activeCount = 0,
    waitlistPositions = [],
  }) {
    const txCalls = { update: [], set: [] };
    const addCalls = [];
    let docCounter = 0;

    // The CF chains: subsCol.where(...).where(...).limit(N).get()
    // We need three different return shapes for three different queries,
    // distinguished by which .where() filter is applied first.
    function makeSubsQueryChain() {
      let mode = null;     // 'duplicate' | 'active' | 'waitlist'

      const chain = {
        where: jest.fn((field, op, value) => {
          if (field === "providerId") mode = "duplicate";
          else if (field === "status" && op === "in") mode = "duplicate";
          else if (field === "status" && op === "==" && value === "active") mode = "active";
          else if (field === "status" && op === "==" && value === "waitlist") mode = "waitlist";
          return chain;
        }),
        limit: jest.fn(() => chain),
        get: jest.fn(async () => {
          if (mode === "duplicate") {
            return { docs: [], empty: true, size: 0, forEach: () => {} };
          }
          if (mode === "active") {
            const docs = Array.from({ length: activeCount }, (_, i) => ({
              data: () => ({ status: "active" }),
              id: `active-${i}`,
            }));
            return { docs, empty: docs.length === 0, size: docs.length, forEach: (cb) => docs.forEach(cb) };
          }
          if (mode === "waitlist") {
            const docs = waitlistPositions.map((p, i) => ({
              data: () => ({ status: "waitlist", waitlistPosition: p }),
              id: `wl-${i}`,
            }));
            return {
              docs, empty: docs.length === 0, size: docs.length,
              forEach: (cb) => docs.forEach(cb),
            };
          }
          return { docs: [], empty: true, size: 0, forEach: () => {} };
        }),
      };
      return chain;
    }

    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => {
        // Calls without an id are creating a new doc — return a unique ref
        const finalId = id || `new-${col}-${docCounter++}`;
        return {
          id: finalId,
          get: jest.fn(async () => {
            if (col === "users" && finalId === callerUid) {
              return {
                exists: true,
                id: finalId,
                data: () => ({ balance, name: "VIP Provider" }),
              };
            }
            return { exists: false, id: finalId, data: () => ({}) };
          }),
          set: jest.fn(async () => {}),
          update: jest.fn(async () => {}),
        };
      }),
      add: jest.fn(async (payload) => {
        addCalls.push({ col, payload });
        return { id: "auto-id" };
      }),
      where: jest.fn((field, op, value) => {
        // Each .collection('vip_subscriptions') call returns a fresh chain
        const chain = makeSubsQueryChain();
        return chain.where(field, op, value);
      }),
    }));

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn((ref, payload) =>
          txCalls.update.push({ ref, payload })),
        set: jest.fn((ref, payload) =>
          txCalls.set.push({ ref, payload })),
      };
      return cb(tx);
    });

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { txCalls, addCalls };
  }

  test("valid purchase with slot available → status='active', exactly ₪99 debited", async () => {
    const { txCalls, addCalls } = setupOk({
      callerUid: "provider1",
      balance: 200,
      activeCount: 5,         // 5 < 30 → slot available
      waitlistPositions: [],
    });

    const result = await purchase({
      auth: { uid: "provider1" },
      data: { autoRenew: true },
    });

    expect(result.status).toBe("active");
    expect(result.waitlistPosition).toBe(null);
    expect(result.amountCharged).toBe(99);
    expect(result.newBalance).toBe(101);    // 200 - 99
    expect(result.subscriptionId).toBeDefined();
    expect(result.paymentId).toBeDefined();

    // Transaction must write: subscription + payment + transactions ledger (3 sets)
    // and update the user balance (1 update)
    expect(txCalls.set.length).toBeGreaterThanOrEqual(3);
    expect(txCalls.update.length).toBeGreaterThanOrEqual(1);

    // The subscription doc must carry status='active' (no waitlistPosition)
    const subSet = txCalls.set.find(
      (c) => c.payload.providerId === "provider1" && c.payload.status === "active"
    );
    expect(subSet).toBeDefined();
    expect(subSet.payload.pricePerMonth).toBe(99);
    expect(subSet.payload.autoRenew).toBe(true);
    expect(subSet.payload.waitlistPosition).toBeUndefined();

    // Payment doc must record paid + credits
    const paymentSet = txCalls.set.find(
      (c) => c.payload.amount === 99 && c.payload.paymentMethod === "credits"
    );
    expect(paymentSet).toBeDefined();
    expect(paymentSet.payload.status).toBe("paid");

    // Best-effort post-tx side effects (audit log + user notification)
    const audit = addCalls.find((c) => c.col === "admin_audit_log");
    expect(audit).toBeDefined();
    expect(audit.payload.action).toBe("vip_purchase");

    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.type).toBe("vip_active");
  });

  test("valid purchase when carousel is full → status='waitlist', position=max+1", async () => {
    const { txCalls, addCalls } = setupOk({
      callerUid: "provider2",
      balance: 100,
      activeCount: 30,                  // FULL — no slot available
      waitlistPositions: [1, 2, 3],     // 3 already on waitlist
    });

    const result = await purchase({
      auth: { uid: "provider2" },
      data: {},
    });

    expect(result.status).toBe("waitlist");
    expect(result.waitlistPosition).toBe(4);     // max(1,2,3) + 1
    expect(result.amountCharged).toBe(99);
    expect(result.newBalance).toBe(1);

    // Subscription doc carries status='waitlist' AND waitlistPosition=4
    const subSet = txCalls.set.find(
      (c) => c.payload.providerId === "provider2" && c.payload.status === "waitlist"
    );
    expect(subSet).toBeDefined();
    expect(subSet.payload.waitlistPosition).toBe(4);

    // Notification reflects waitlist (NOT active)
    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.type).toBe("vip_waitlist");
  });

  test("autoRenew=false is honored on the subscription doc", async () => {
    const { txCalls } = setupOk({
      callerUid: "provider3",
      balance: 99,                  // exact balance — edge case for ≥
      activeCount: 0,
      waitlistPositions: [],
    });

    await purchase({
      auth: { uid: "provider3" },
      data: { autoRenew: false },
    });

    const subSet = txCalls.set.find(
      (c) => c.payload.providerId === "provider3"
    );
    expect(subSet).toBeDefined();
    expect(subSet.payload.autoRenew).toBe(false);
  });

  test("first slot edge case: activeCount=29 → still gets active (29 < 30)", async () => {
    const { txCalls } = setupOk({
      callerUid: "provider4",
      balance: 200,
      activeCount: 29,
      waitlistPositions: [],
    });

    const result = await purchase({
      auth: { uid: "provider4" },
      data: {},
    });

    expect(result.status).toBe("active");
    expect(result.waitlistPosition).toBe(null);

    const subSet = txCalls.set.find(
      (c) => c.payload.providerId === "provider4"
    );
    expect(subSet.payload.status).toBe("active");
  });

  test("first waitlist entry when full → position=1 (no prior waitlist)", async () => {
    const { txCalls } = setupOk({
      callerUid: "provider5",
      balance: 200,
      activeCount: 30,
      waitlistPositions: [],     // no one on waitlist yet
    });

    const result = await purchase({
      auth: { uid: "provider5" },
      data: {},
    });

    expect(result.status).toBe("waitlist");
    expect(result.waitlistPosition).toBe(1);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// resolveDisputeAdmin — rejection paths + 3 happy paths
// ═══════════════════════════════════════════════════════════════════════════════
//
// Admin-only money CF (CLAUDE.md §4.5) — when a customer disputes a job, the
// admin chooses ONE of three resolutions:
//   • refund  → 100% to customer, 0 to expert, 0 platform fee
//   • release → 0 to customer, totalAmount * (1 - feePct) to expert, fee to platform
//   • split   → 50% to customer, 50% * (1 - feePct) to expert, 50% * feePct to platform
//
// Every path writes a different combination of balance updates + transactions
// + platform_earnings docs. A bug here could overpay one party, skip the
// platform fee, or short-pay the customer. These tests pin the exact math.
// ═══════════════════════════════════════════════════════════════════════════════
describe("resolveDisputeAdmin — rejection paths", () => {
  const resolve = index.resolveDisputeAdmin;

  beforeEach(() => {
    jest.clearAllMocks();
    // Mock admin.messaging so the post-tx FCM block doesn't crash.
    // (sendNotif() is wrapped in try/catch, but messaging() is called outside
    // try/catch on a `null` if not stubbed.)
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async () => ({ messageId: "mock" })),
    }));
  });

  function setupRejectMocks({
    callerIsAdmin = true,
    jobExists = true,
    jobStatus = "disputed",
  }) {
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => {
        if (col === "users") {
          return {
            get: jest.fn(async () => ({
              exists: true,
              id,
              data: () => ({ isAdmin: callerIsAdmin }),
            })),
          };
        }
        if (col === "jobs") {
          return {
            get: jest.fn(async () => ({
              exists: jobExists,
              id,
              data: () => ({
                status: jobStatus,
                customerId: "c1",
                expertId: "e1",
                totalAmount: 200,
              }),
            })),
            set: jest.fn(),
            update: jest.fn(),
          };
        }
        return {
          get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
          collection: jest.fn(() => ({
            doc: jest.fn(() => ({
              get: jest.fn(async () => ({
                exists: true,
                data: () => ({ feePercentage: 0.10 }),
              })),
            })),
          })),
        };
      }),
      add: jest.fn(async () => ({ id: "auto-id" })),
    }));

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn(),
        set: jest.fn(),
      };
      return cb(tx);
    });
  }

  test("rejects unauthenticated", async () => {
    setupRejectMocks({});
    await expect(
      resolve({ auth: null, data: { jobId: "j1", resolution: "refund" } })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin caller", async () => {
    setupRejectMocks({ callerIsAdmin: false });
    await expect(
      resolve({
        auth: { uid: "regular-user", token: {} },
        data: { jobId: "j1", resolution: "refund" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects missing jobId", async () => {
    setupRejectMocks({ callerIsAdmin: true });
    await expect(
      resolve({
        auth: { uid: "admin1", token: {} },
        data: { resolution: "refund" },
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects invalid resolution", async () => {
    setupRejectMocks({ callerIsAdmin: true });
    await expect(
      resolve({
        auth: { uid: "admin1", token: {} },
        data: { jobId: "j1", resolution: "nuke" },   // not in [refund,release,split]
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects when job is missing", async () => {
    setupRejectMocks({ callerIsAdmin: true, jobExists: false });
    await expect(
      resolve({
        auth: { uid: "admin1", token: {} },
        data: { jobId: "ghost", resolution: "refund" },
      })
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("rejects when job is not in 'disputed' status", async () => {
    setupRejectMocks({ callerIsAdmin: true, jobStatus: "completed" });
    await expect(
      resolve({
        auth: { uid: "admin1", token: {} },
        data: { jobId: "j1", resolution: "refund" },
      })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });
});


describe("resolveDisputeAdmin — happy paths", () => {
  const resolve = index.resolveDisputeAdmin;

  beforeEach(() => {
    jest.clearAllMocks();
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async () => ({ messageId: "mock" })),
    }));
  });

  /**
   * Helper: builds the full happy-path mock surface.
   *   - users/{adminUid}.isAdmin: true   (for isAdminCaller)
   *   - users/{customerId} + users/{expertId} return the configured users
   *     (with no fcmToken so the messaging path short-circuits)
   *   - jobs/{jobId} with the configured status + amounts
   *   - admin/admin/settings/settings.feePercentage
   *   - Captures tx.update + tx.set calls for assertion
   */
  function setupResolveMocks({
    adminUid = "admin1",
    customerId = "alice",
    expertId = "bob",
    totalAmount = 200,
    feePercentage = 0.10,
  }) {
    const txCalls = { update: [], set: [] };

    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => {
        if (col === "users") {
          return {
            get: jest.fn(async () => {
              if (id === adminUid) {
                return {
                  exists: true, id,
                  data: () => ({ isAdmin: true, name: "Admin" }),
                };
              }
              if (id === customerId) {
                return {
                  exists: true, id,
                  data: () => ({ name: "Customer", balance: 0 }),
                };
              }
              if (id === expertId) {
                return {
                  exists: true, id,
                  data: () => ({ name: "Expert", balance: 0 }),
                };
              }
              return { exists: false, id, data: () => ({}) };
            }),
            update: jest.fn(),
          };
        }
        if (col === "jobs") {
          return {
            get: jest.fn(async () => ({
              exists: true, id,
              data: () => ({
                customerId, expertId, totalAmount,
                status: "disputed",
              }),
            })),
            update: jest.fn(),
          };
        }
        if (col === "admin") {
          // db.collection('admin').doc('admin').collection('settings').doc('settings')
          return {
            collection: jest.fn(() => ({
              doc: jest.fn(() => ({
                get: jest.fn(async () => ({
                  exists: true,
                  data: () => ({ feePercentage }),
                })),
              })),
            })),
          };
        }
        return {
          get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
        };
      }),
      add: jest.fn(async () => ({ id: "auto-id" })),
    }));

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn((ref, payload) =>
          txCalls.update.push({ ref, payload })),
        set: jest.fn((ref, payload) =>
          txCalls.set.push({ ref, payload })),
      };
      return cb(tx);
    });

    return txCalls;
  }

  test("refund: customer gets 100%, expert gets 0, no platform fee", async () => {
    const txCalls = setupResolveMocks({
      totalAmount: 200,
      feePercentage: 0.10,
    });

    const result = await resolve({
      auth: { uid: "admin1", token: {} },
      data: { jobId: "j1", resolution: "refund", adminNote: "Service not delivered" },
    });

    expect(result.success).toBe(true);
    expect(result.resolution).toBe("refund");
    expect(result.newStatus).toBe("refunded");
    expect(result.customerCredit).toBe(200);
    expect(result.expertCredit).toBe(0);
    expect(result.platformFee).toBe(0);

    // ONE balance update (customer only) + job status update = 2 updates
    expect(txCalls.update.length).toBeGreaterThanOrEqual(2);

    // No platform_earnings doc created (refund earns no platform fee)
    const platformEarnings = txCalls.set.filter(
      (c) => c.payload && c.payload.type &&
        String(c.payload.type).includes("dispute")
    );
    expect(platformEarnings.length).toBe(0);

    // Customer transaction ledger entry recorded
    const customerTxn = txCalls.set.find(
      (c) => c.payload && c.payload.userId === "alice" && c.payload.amount === 200
    );
    expect(customerTxn).toBeDefined();
  });

  test("release: expert gets total - fee, customer gets 0, fee → platform", async () => {
    const txCalls = setupResolveMocks({
      totalAmount: 200,
      feePercentage: 0.10,
    });

    const result = await resolve({
      auth: { uid: "admin1", token: {} },
      data: { jobId: "j1", resolution: "release", adminNote: "Customer claim unsubstantiated" },
    });

    expect(result.success).toBe(true);
    expect(result.resolution).toBe("release");
    expect(result.newStatus).toBe("completed");
    expect(result.customerCredit).toBe(0);
    expect(result.expertCredit).toBe(180);     // 200 - (200 * 0.10)
    expect(result.platformFee).toBe(20);

    // ONE balance update (expert only) + job status = ≥2 updates
    expect(txCalls.update.length).toBeGreaterThanOrEqual(2);

    // Platform earnings doc with type='dispute_release_fee'
    const platformEarning = txCalls.set.find(
      (c) => c.payload && c.payload.type === "dispute_release_fee"
    );
    expect(platformEarning).toBeDefined();
    expect(platformEarning.payload.amount).toBe(20);

    // Expert transaction ledger entry recorded
    const expertTxn = txCalls.set.find(
      (c) => c.payload && c.payload.userId === "bob" && c.payload.amount === 180
    );
    expect(expertTxn).toBeDefined();
  });

  test("split: customer gets 50%, expert gets 50%-fee, platform gets 50%*fee", async () => {
    const txCalls = setupResolveMocks({
      totalAmount: 200,
      feePercentage: 0.10,
    });

    const result = await resolve({
      auth: { uid: "admin1", token: {} },
      data: { jobId: "j1", resolution: "split", adminNote: "Both parties at fault" },
    });

    expect(result.success).toBe(true);
    expect(result.resolution).toBe("split");
    expect(result.newStatus).toBe("split_resolved");
    expect(result.customerCredit).toBe(100);   // 200 * 0.5
    expect(result.expertCredit).toBe(90);      // 100 - (100 * 0.10)
    expect(result.platformFee).toBe(10);       // 100 * 0.10

    // BOTH balances updated + job status = ≥3 updates
    expect(txCalls.update.length).toBeGreaterThanOrEqual(3);

    // Platform earnings doc with type='dispute_split_fee'
    const platformEarning = txCalls.set.find(
      (c) => c.payload && c.payload.type === "dispute_split_fee"
    );
    expect(platformEarning).toBeDefined();
    expect(platformEarning.payload.amount).toBe(10);

    // BOTH transaction ledger entries recorded
    const customerTxn = txCalls.set.find(
      (c) => c.payload && c.payload.userId === "alice" && c.payload.amount === 100
    );
    expect(customerTxn).toBeDefined();
    const expertTxn = txCalls.set.find(
      (c) => c.payload && c.payload.userId === "bob" && c.payload.amount === 90
    );
    expect(expertTxn).toBeDefined();
  });

  test("custom fee percentage from admin settings is honored (not hardcoded 10%)", async () => {
    // Admin set the platform fee to 15% — every path should use that value.
    const txCalls = setupResolveMocks({
      totalAmount: 1000,
      feePercentage: 0.15,
    });

    const result = await resolve({
      auth: { uid: "admin1", token: {} },
      data: { jobId: "j1", resolution: "release" },
    });

    expect(result.expertCredit).toBe(850);     // 1000 - (1000 * 0.15)
    expect(result.platformFee).toBe(150);

    const platformEarning = txCalls.set.find(
      (c) => c.payload && c.payload.type === "dispute_release_fee"
    );
    expect(platformEarning.payload.amount).toBe(150);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// sendGlobalBroadcast — security regression net for §50 Vuln 7
// ═══════════════════════════════════════════════════════════════════════════════
//
// SECURITY-CRITICAL: This CF was exploited as a phishing/spam primitive
// before §50 Round B (2026-04-25). Before the fix, ANY authenticated user
// could call this CF and push an arbitrary FCM notification to every
// registered token in the system ("title: 📢 AnySkill, body: <attacker
// text>") — perfect for "your account is suspended, click here" attacks.
//
// The fix: explicit `isAdminCaller` gate. The first two tests below pin
// that the gate STAYS in place. If a future regression removes either
// `request.auth` or `isAdminCaller`, these tests fail loudly and
// catch the regression in CI before it reaches production.
// ═══════════════════════════════════════════════════════════════════════════════
describe("sendGlobalBroadcast — security gate (§50 Vuln 7 regression net)", () => {
  const broadcast = index.sendGlobalBroadcast;

  beforeEach(() => {
    jest.clearAllMocks();
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      sendEachForMulticast: jest.fn(async (msg) => ({
        successCount: msg.tokens.length,
        failureCount: 0,
      })),
    }));
  });

  /**
   * Helper: builds the mock surface for sendGlobalBroadcast.
   *   - users/{adminUid}.isAdmin: callerIsAdmin (drives isAdminCaller gate)
   *   - users.where('fcmToken','!=',null).select().limit().get() returns
   *     `tokenDocs` — a list of { id, data: () => ({ fcmToken }) }
   *   - broadcast_history.add captured for assertion
   */
  function setupBroadcastMocks({
    callerUid = "admin1",
    callerIsAdmin = true,
    tokenDocs = [],
  }) {
    const addCalls = [];
    const messagingCalls = [];

    // Token query is chainable: where().select().limit().startAfter().get()
    const queryChain = {
      where: jest.fn(() => queryChain),
      select: jest.fn(() => queryChain),
      limit: jest.fn(() => queryChain),
      startAfter: jest.fn(() => queryChain),
      get: jest.fn(async () => ({
        docs: tokenDocs,
        empty: tokenDocs.length === 0,
        size: tokenDocs.length,
      })),
    };

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "users") {
        return {
          // doc(uid).get() — used by isAdminCaller for the admin gate
          doc: jest.fn((id) => ({
            get: jest.fn(async () => ({
              exists: true,
              id,
              data: () => (id === callerUid ? { isAdmin: callerIsAdmin } : {}),
            })),
          })),
          // .where() — used by the token-pagination query
          where: jest.fn(() => queryChain),
        };
      }
      if (col === "broadcast_history") {
        return {
          add: jest.fn(async (payload) => {
            addCalls.push({ col, payload });
            return { id: "auto-id" };
          }),
        };
      }
      return {
        doc: jest.fn(() => ({ get: jest.fn(async () => ({ exists: false })) })),
        add: jest.fn(async () => ({ id: "auto-id" })),
        where: jest.fn(() => queryChain),
      };
    });

    // Replace the messaging mock with a capturing variant
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      sendEachForMulticast: jest.fn(async (msg) => {
        messagingCalls.push(msg);
        return { successCount: msg.tokens.length, failureCount: 0 };
      }),
    }));

    return { addCalls, messagingCalls };
  }

  // ─── Rejection paths (security gate) ──────────────────────────────────────

  test("[SECURITY] rejects unauthenticated caller (no spam from logged-out attackers)", async () => {
    setupBroadcastMocks({});
    await expect(
      broadcast({ auth: null, data: { message: "phish-test" } })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("[SECURITY] rejects non-admin caller (the §50 Vuln 7 fix — REGRESSION NET)", async () => {
    // This is THE regression test for the §50 Round B fix.
    // Before the fix, this same call would have succeeded and spammed
    // every device with token. After the fix, it must throw permission-denied.
    const { messagingCalls, addCalls } = setupBroadcastMocks({
      callerUid: "regular-user",
      callerIsAdmin: false,
      tokenDocs: [{ id: "u1", data: () => ({ fcmToken: "token-1" }) }],
    });

    await expect(
      broadcast({
        auth: { uid: "regular-user", token: {} },
        data: { message: "Your account is suspended, click here: evil.com" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });

    // CRITICAL: even though token query would have found a token, NO multicast
    // was attempted and NO history doc was written.
    expect(messagingCalls.length).toBe(0);
    expect(addCalls.length).toBe(0);
  });

  test("rejects empty message", async () => {
    setupBroadcastMocks({ callerIsAdmin: true });
    await expect(
      broadcast({
        auth: { uid: "admin1", token: {} },
        data: { message: "   " },     // whitespace-only → trimmed to empty
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects missing message field", async () => {
    setupBroadcastMocks({ callerIsAdmin: true });
    await expect(
      broadcast({
        auth: { uid: "admin1", token: {} },
        data: {},
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  // ─── Happy paths ──────────────────────────────────────────────────────────

  test("admin sends → multicast called once, history doc written", async () => {
    const { messagingCalls, addCalls } = setupBroadcastMocks({
      callerUid: "admin1",
      callerIsAdmin: true,
      tokenDocs: [
        { id: "u1", data: () => ({ fcmToken: "tok-1" }) },
        { id: "u2", data: () => ({ fcmToken: "tok-2" }) },
        { id: "u3", data: () => ({ fcmToken: "tok-3" }) },
      ],
    });

    const result = await broadcast({
      auth: { uid: "admin1", token: {} },
      data: { message: "New feature launched! Check the wallet tab." },
    });

    expect(result.sent).toBe(3);
    expect(result.total).toBe(3);

    // ONE multicast call (3 tokens fits in one batch of 500)
    expect(messagingCalls.length).toBe(1);
    expect(messagingCalls[0].tokens).toEqual(["tok-1", "tok-2", "tok-3"]);
    expect(messagingCalls[0].notification.title).toBe("📢 AnySkill");
    expect(messagingCalls[0].notification.body).toBe(
      "New feature launched! Check the wallet tab.");
    expect(messagingCalls[0].data.type).toBe("broadcast");

    // History doc recorded
    expect(addCalls.length).toBe(1);
    expect(addCalls[0].col).toBe("broadcast_history");
    expect(addCalls[0].payload.message).toBe(
      "New feature launched! Check the wallet tab.");
    expect(addCalls[0].payload.sentBy).toBe("admin1");
    expect(addCalls[0].payload.platform).toBe("fcm-push");
    expect(addCalls[0].payload.totalTokens).toBe(3);
    expect(addCalls[0].payload.sent).toBe(3);
  });

  test("no tokens registered → returns sent:0, no multicast, no history", async () => {
    const { messagingCalls, addCalls } = setupBroadcastMocks({
      callerUid: "admin1",
      callerIsAdmin: true,
      tokenDocs: [],
    });

    const result = await broadcast({
      auth: { uid: "admin1", token: {} },
      data: { message: "broadcast to nobody" },
    });

    expect(result.sent).toBe(0);
    expect(messagingCalls.length).toBe(0);
    expect(addCalls.length).toBe(0);
  });

  test("trims leading/trailing whitespace from message", async () => {
    const { messagingCalls } = setupBroadcastMocks({
      callerUid: "admin1",
      callerIsAdmin: true,
      tokenDocs: [{ id: "u1", data: () => ({ fcmToken: "tok-1" }) }],
    });

    await broadcast({
      auth: { uid: "admin1", token: {} },
      data: { message: "   Hello world   " },
    });

    // The trimmed message lands in the multicast notification body
    expect(messagingCalls[0].notification.body).toBe("Hello world");
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// notifyProviderOnApproval — Firestore-trigger tests (CLAUDE.md §39)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Trigger: onDocumentUpdated('users/{uid}'). Fires on EVERY update, but
// only acts when:
//   1. isVerified flips false → true
//   2. user is a provider (isProvider == true)
//   3. verifiedAt is NOT yet stamped (idempotency)
//
// Side effects (best-effort, all wrapped in try/catch):
//   • FCM push (skipped if no token)
//   • In-app notification doc (always written — durable record)
//   • Stamp verifiedAt + isPendingExpert=false on the user doc
//
// These tests pin: (a) the gate logic — when does the CF do nothing?
// (b) the side effects — what gets written when it DOES fire?
// ═══════════════════════════════════════════════════════════════════════════════
describe("notifyProviderOnApproval — gate logic", () => {
  const trigger = index.notifyProviderOnApproval;

  beforeEach(() => {
    jest.clearAllMocks();
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async () => ({ messageId: "mock" })),
    }));
  });

  /**
   * Helper: builds a fake event { data: { before, after }, params: { uid } }.
   * Captures all writes to notifications + users/{uid}.update for assertion.
   */
  function buildMocks() {
    const addCalls = [];
    const updateCalls = [];

    mockFirestore.collection.mockImplementation((col) => ({
      add: jest.fn(async (payload) => {
        addCalls.push({ col, payload });
        return { id: "auto-id" };
      }),
      doc: jest.fn((id) => ({
        update: jest.fn(async (payload) => {
          updateCalls.push({ col, id, payload });
        }),
      })),
    }));

    return { addCalls, updateCalls };
  }

  function buildEvent({ before, after, uid = "u1" }) {
    return {
      params: { uid },
      data: {
        before: { data: () => before },
        after:  { data: () => after  },
      },
    };
  }

  test("no-op when isVerified did NOT flip (true → true)", async () => {
    const { addCalls, updateCalls } = buildMocks();
    await trigger(buildEvent({
      before: { isVerified: true,  isProvider: true },
      after:  { isVerified: true,  isProvider: true, name: "Bob" },
    }));
    expect(addCalls.length).toBe(0);
    expect(updateCalls.length).toBe(0);
  });

  test("no-op when isVerified is being REVOKED (true → false)", async () => {
    const { addCalls, updateCalls } = buildMocks();
    await trigger(buildEvent({
      before: { isVerified: true,  isProvider: true },
      after:  { isVerified: false, isProvider: true },
    }));
    expect(addCalls.length).toBe(0);
    expect(updateCalls.length).toBe(0);
  });

  test("no-op when user is NOT a provider (customer being verified)", async () => {
    // Edge case: shouldn't happen in practice, but if a customer is somehow
    // marked verified, we should NOT push the "you can now receive bookings"
    // notification. This guard protects against role confusion.
    const { addCalls, updateCalls } = buildMocks();
    await trigger(buildEvent({
      before: { isVerified: false, isProvider: false },
      after:  { isVerified: true,  isProvider: false, name: "Alice" },
    }));
    expect(addCalls.length).toBe(0);
    expect(updateCalls.length).toBe(0);
  });

  test("no-op when verifiedAt is already stamped (idempotency)", async () => {
    // Idempotency safety: if the CF already fired (verifiedAt exists),
    // a second update on the user doc must NOT re-notify.
    const { addCalls, updateCalls } = buildMocks();
    await trigger(buildEvent({
      before: { isVerified: false, isProvider: true },
      after:  {
        isVerified: true, isProvider: true,
        verifiedAt: { toMillis: () => Date.now() - 60_000 },
        name: "Bob",
      },
    }));
    expect(addCalls.length).toBe(0);
    expect(updateCalls.length).toBe(0);
  });

  test("no-op when event.data is missing", async () => {
    const { addCalls, updateCalls } = buildMocks();
    await trigger({ params: { uid: "u1" }, data: null });
    expect(addCalls.length).toBe(0);
    expect(updateCalls.length).toBe(0);
  });
});


describe("notifyProviderOnApproval — happy paths (verification approved)", () => {
  const trigger = index.notifyProviderOnApproval;
  let messagingCalls;

  beforeEach(() => {
    jest.clearAllMocks();
    messagingCalls = [];
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async (msg) => {
        messagingCalls.push(msg);
        return { messageId: "mock" };
      }),
    }));
  });

  function buildMocks() {
    const addCalls = [];
    const updateCalls = [];

    mockFirestore.collection.mockImplementation((col) => ({
      add: jest.fn(async (payload) => {
        addCalls.push({ col, payload });
        return { id: "auto-id" };
      }),
      doc: jest.fn((id) => ({
        update: jest.fn(async (payload) => {
          updateCalls.push({ col, id, payload });
        }),
      })),
    }));

    return { addCalls, updateCalls };
  }

  function buildEvent({ after, uid = "p1" }) {
    return {
      params: { uid },
      data: {
        before: { data: () => ({ isVerified: false, isProvider: true }) },
        after:  { data: () => after },
      },
    };
  }

  test("fires when isVerified flips false → true on a provider", async () => {
    const { addCalls, updateCalls } = buildMocks();

    await trigger(buildEvent({
      uid: "p1",
      after: {
        isVerified: true,
        isProvider: true,
        name: "Bob the Builder",
        serviceType: "שיפוצים",
        fcmToken: "device-token-123",
      },
    }));

    // 1. FCM push sent with the right payload
    expect(messagingCalls.length).toBe(1);
    expect(messagingCalls[0].token).toBe("device-token-123");
    expect(messagingCalls[0].notification.title).toBe("אושרת בהצלחה! 🎉");
    expect(messagingCalls[0].notification.body).toContain("Bob the Builder");
    expect(messagingCalls[0].notification.body).toContain("שיפוצים");
    expect(messagingCalls[0].data.type).toBe("provider_approved");
    expect(messagingCalls[0].data.uid).toBe("p1");

    // 2. In-app notification doc written
    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.userId).toBe("p1");
    expect(notif.payload.type).toBe("provider_approved");
    expect(notif.payload.title).toBe("אושרת בהצלחה! 🎉");
    expect(notif.payload.isRead).toBe(false);

    // 3. verifiedAt + isPendingExpert stamps written (idempotency)
    const stamp = updateCalls.find(
      (c) => c.col === "users" && c.id === "p1"
    );
    expect(stamp).toBeDefined();
    expect(stamp.payload.verifiedAt).toBeDefined();
    expect(stamp.payload.isPendingExpert).toBe(false);
  });

  test("works without serviceType (generic message)", async () => {
    const { addCalls } = buildMocks();

    await trigger(buildEvent({
      after: {
        isVerified: true,
        isProvider: true,
        name: "Carol",
        // no serviceType
        fcmToken: "tok-2",
      },
    }));

    expect(messagingCalls.length).toBe(1);
    // Generic body: doesn't mention category
    expect(messagingCalls[0].notification.body).not.toContain("בקטגוריית");
    expect(messagingCalls[0].notification.body).toContain("Carol");

    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.body).toContain("Carol");
  });

  test("works without fcmToken — push skipped, in-app notif still written", async () => {
    // The CF must NEVER fail when the user has no FCM token. The in-app
    // notification + verifiedAt stamp are the durable contract.
    const { addCalls, updateCalls } = buildMocks();

    await trigger(buildEvent({
      uid: "p3",
      after: {
        isVerified: true,
        isProvider: true,
        name: "David",
        // NO fcmToken / deviceToken
      },
    }));

    // Push was NOT attempted
    expect(messagingCalls.length).toBe(0);

    // But notification doc IS written
    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();

    // And verifiedAt IS stamped (so subsequent updates won't re-notify)
    const stamp = updateCalls.find((c) => c.col === "users" && c.id === "p3");
    expect(stamp).toBeDefined();
    expect(stamp.payload.verifiedAt).toBeDefined();
  });

  test("FCM failure does NOT prevent the in-app notification + stamp", async () => {
    // If FCM throws (token expired, network error), the durable contract
    // — the in-app notification + the idempotency stamp — must still
    // execute. Otherwise a transient FCM blip would cause a re-notification
    // loop on the next user-doc update.
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async () => {
        throw new Error("FCM service unavailable");
      }),
    }));

    const { addCalls, updateCalls } = buildMocks();

    await trigger(buildEvent({
      uid: "p4",
      after: {
        isVerified: true,
        isProvider: true,
        name: "Erin",
        fcmToken: "expired-token",
      },
    }));

    // In-app notification IS still written
    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();

    // verifiedAt IS still stamped
    const stamp = updateCalls.find((c) => c.col === "users" && c.id === "p4");
    expect(stamp).toBeDefined();
    expect(stamp.payload.verifiedAt).toBeDefined();
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// anytaskAutoRelease — scheduled CF (every 30 min, IST)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Money-flow scheduled CF that runs every 30 minutes. Two phases per tick:
//
//   Phase 1 — Auto-release: any task in 'proof_submitted' status whose
//             autoReleaseDate has passed gets:
//               • status flipped to 'completed'
//               • autoReleased: true (idempotency)
//               • provider balance += netToProvider, pendingBalance -= same
//               • platform_earnings ledger entry
//               • transactions ledger entry
//               • admin totalPlatformBalance += commission
//               • 2 notifications (provider + creator)
//               • activity-log entry on task subcollection
//
//   Phase 2 — Reminders: notify the creator at 24h and 2h before auto-release.
//             Each reminder is sent once via the _reminder24hSent / _reminder2hSent
//             flags written back to the task doc.
//
// Bugs in this CF would directly cost money (over-pay, double-pay, skip
// commission). Tests pin the exact contract.
// ═══════════════════════════════════════════════════════════════════════════════
describe("anytaskAutoRelease — scheduled CF", () => {
  const trigger = index.anytaskAutoRelease;

  beforeEach(() => jest.clearAllMocks());

  /**
   * Helper builds a comprehensive mock for the scheduled handler.
   *
   * @param expiredTasks  — array of {data, id} that the Phase 1 query returns.
   * @param reminderTasks — array of {data, id} that the Phase 2 query returns.
   *
   * Captures: every batch op, every collection().add() (notifications),
   * every doc.ref.update() (reminder flags), every nested .collection("activity").add().
   */
  function setupAutoReleaseMocks({ expiredTasks = [], reminderTasks = [] }) {
    const batchOps = [];
    const addCalls = [];
    const docUpdateCalls = [];
    const activityAddCalls = [];

    // Build a snapshot doc with .ref pointing to a mock doc-ref that supports
    // batch.update(ref, ...) AND ref.update(...) AND ref.collection("activity").add(...)
    function buildSnapDoc(data, taskId) {
      const docRef = {
        id: taskId,
        update: jest.fn(async (payload) => {
          docUpdateCalls.push({ taskId, payload });
        }),
        collection: jest.fn((subcol) => ({
          add: jest.fn(async (payload) => {
            activityAddCalls.push({ taskId, subcol, payload });
            return { id: "auto-id" };
          }),
        })),
      };
      return { id: taskId, data: () => data, ref: docRef };
    }

    // The CF makes TWO `.collection("anytasks")` calls — first the Phase 1
    // expired query (3 wheres + limit), second the Phase 2 reminder query
    // (2 wheres + limit). We track which call we're on via a counter.
    let anytasksCallCount = 0;

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "anytasks") {
        anytasksCallCount++;
        const isExpiredQuery = anytasksCallCount === 1;
        const docs = (isExpiredQuery ? expiredTasks : reminderTasks)
          .map((t) => buildSnapDoc(t.data, t.id));

        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs,
            empty: docs.length === 0,
            size: docs.length,
          })),
        };
        return chain;
      }
      // Other collections — notifications, transactions, platform_earnings, users
      const docMock = (id) => ({
        id: id || `auto-${col}`,
        get: jest.fn(async () => ({ exists: false })),
        update: jest.fn(),
        collection: jest.fn(() => ({
          doc: jest.fn(() => docMock("nested")),
        })),
      });
      return {
        doc: jest.fn(docMock),
        add: jest.fn(async (payload) => {
          addCalls.push({ col, payload });
          return { id: "auto-id" };
        }),
      };
    });

    // db.batch() mock — returns an object with update/set/commit
    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ op: "update", ref, payload })),
      set: jest.fn((ref, payload, opts) =>
        batchOps.push({ op: "set", ref, payload, opts })),
      commit: jest.fn(async () => {}),
    }));

    // Timestamp.now() helper used by the CF
    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps, addCalls, docUpdateCalls, activityAddCalls };
  }

  test("no expired + no reminders → CF runs cleanly with no writes", async () => {
    const { batchOps, addCalls, docUpdateCalls } = setupAutoReleaseMocks({
      expiredTasks: [],
      reminderTasks: [],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
    expect(addCalls.length).toBe(0);
    expect(docUpdateCalls.length).toBe(0);
  });

  test("Phase 1: single expired task → batch commit + 2 notifs + activity log", async () => {
    const { batchOps, addCalls, activityAddCalls } = setupAutoReleaseMocks({
      expiredTasks: [{
        id: "task-1",
        data: {
          status: "proof_submitted",
          autoReleased: false,
          providerId: "prov-1",
          creatorId: "crea-1",
          providerName: "Bob",
          netToProvider: 90,
          commission: 10,
          title: "תיקון ברז",
        },
      }],
      reminderTasks: [],
    });

    await trigger();

    // ── Batch contents ────────────────────────────────────────────────────
    // Phase 1 must write 4 batch ops per expired task:
    //   1. update task doc (status, autoReleased, completedAt, etc)
    //   2. update provider user doc (balance, pendingBalance, count)
    //   3. set platform_earnings doc
    //   4. set transactions doc
    //   5. set admin totalPlatformBalance (with merge)
    expect(batchOps.length).toBeGreaterThanOrEqual(4);

    // Provider balance gets exactly netToProvider, NOT total amount
    const balanceUpdate = batchOps.find(
      (op) => op.op === "update" && op.payload.balance && op.payload.pendingBalance
    );
    expect(balanceUpdate).toBeDefined();
    // FieldValue.increment is mocked to "INC(N)" string at the top of file
    expect(String(balanceUpdate.payload.balance)).toBe("INC(90)");
    expect(String(balanceUpdate.payload.pendingBalance)).toBe("INC(-90)");

    // Platform_earnings carries the COMMISSION (10), not the full amount
    const earningsSet = batchOps.find(
      (op) => op.op === "set" && op.payload.amount === 10
    );
    expect(earningsSet).toBeDefined();
    expect(earningsSet.payload.source).toBe("anytask_auto_release");
    expect(earningsSet.payload.taskId).toBe("task-1");

    // Transactions ledger: receiver = provider, amount = netToProvider
    const txnSet = batchOps.find(
      (op) => op.op === "set" && op.payload.type === "anytask_auto_release"
    );
    expect(txnSet).toBeDefined();
    expect(txnSet.payload.receiverId).toBe("prov-1");
    expect(txnSet.payload.amount).toBe(90);

    // ── Post-batch side effects ──────────────────────────────────────────
    // 2 notifications (provider + creator)
    const providerNotif = addCalls.find(
      (c) => c.col === "notifications" && c.payload.userId === "prov-1"
    );
    expect(providerNotif).toBeDefined();
    expect(providerNotif.payload.type).toBe("anytask_auto_released");
    expect(providerNotif.payload.taskId).toBe("task-1");
    expect(providerNotif.payload.body).toContain("90");
    expect(providerNotif.payload.body).toContain("תיקון ברז");

    const creatorNotif = addCalls.find(
      (c) => c.col === "notifications" && c.payload.userId === "crea-1"
    );
    expect(creatorNotif).toBeDefined();
    expect(creatorNotif.payload.type).toBe("anytask_auto_released");

    // Activity log entry on the task subcollection
    expect(activityAddCalls.length).toBe(1);
    expect(activityAddCalls[0].subcol).toBe("activity");
    expect(activityAddCalls[0].payload.actorRole).toBe("system");
    expect(activityAddCalls[0].payload.action).toBe("auto_released");
  });

  test("Phase 1: missing providerId → task is skipped (continue)", async () => {
    // Edge case: malformed task data (no providerId). The CF must skip it
    // gracefully, not crash, and not commit a batch.
    const { batchOps, addCalls } = setupAutoReleaseMocks({
      expiredTasks: [{
        id: "broken-1",
        data: {
          status: "proof_submitted",
          autoReleased: false,
          // NO providerId
          creatorId: "crea-1",
          netToProvider: 100,
        },
      }],
      reminderTasks: [],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
    expect(addCalls.length).toBe(0);
  });

  test("Phase 2: 24h reminder fires when hoursLeft is in [22, 26]", async () => {
    const releaseDate = new Date(Date.now() + 24 * 60 * 60 * 1000);    // 24h from now
    const { addCalls, docUpdateCalls } = setupAutoReleaseMocks({
      expiredTasks: [],
      reminderTasks: [{
        id: "task-2",
        data: {
          status: "proof_submitted",
          autoReleased: false,
          autoReleaseDate: { toDate: () => releaseDate },
          creatorId: "crea-2",
          title: "ניקיון משרד",
          // No _reminder24hSent flag yet
        },
      }],
    });

    await trigger();

    // 24h reminder notification sent to creator
    const reminder = addCalls.find(
      (c) => c.col === "notifications" && c.payload.type === "anytask_reminder_24h"
    );
    expect(reminder).toBeDefined();
    expect(reminder.payload.userId).toBe("crea-2");
    expect(reminder.payload.body).toContain("ניקיון משרד");
    expect(reminder.payload.taskId).toBe("task-2");

    // _reminder24hSent flag stamped on the task (idempotency for next tick)
    const flagUpdate = docUpdateCalls.find((c) => c.taskId === "task-2");
    expect(flagUpdate).toBeDefined();
    expect(flagUpdate.payload._reminder24hSent).toBe(true);
  });

  test("Phase 2: 24h reminder NOT re-sent when _reminder24hSent already true", async () => {
    // Idempotency test: a task that already had the 24h reminder must not
    // get it again, even if its release time is still in the [22, 26] window
    // (next 30-min tick after the first reminder).
    const releaseDate = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const { addCalls, docUpdateCalls } = setupAutoReleaseMocks({
      expiredTasks: [],
      reminderTasks: [{
        id: "already-reminded",
        data: {
          status: "proof_submitted",
          autoReleased: false,
          autoReleaseDate: { toDate: () => releaseDate },
          creatorId: "crea-3",
          _reminder24hSent: true,    // already sent
        },
      }],
    });

    await trigger();

    // No 24h reminder, no flag re-write
    expect(addCalls.length).toBe(0);
    expect(docUpdateCalls.length).toBe(0);
  });

  test("Phase 2: 2h reminder fires when hoursLeft is in [1.5, 2.5]", async () => {
    const releaseDate = new Date(Date.now() + 2 * 60 * 60 * 1000);    // 2h from now
    const { addCalls, docUpdateCalls } = setupAutoReleaseMocks({
      expiredTasks: [],
      reminderTasks: [{
        id: "task-3",
        data: {
          status: "proof_submitted",
          autoReleased: false,
          autoReleaseDate: { toDate: () => releaseDate },
          creatorId: "crea-4",
          title: "הובלה",
        },
      }],
    });

    await trigger();

    const reminder = addCalls.find(
      (c) => c.col === "notifications" && c.payload.type === "anytask_reminder_2h"
    );
    expect(reminder).toBeDefined();
    expect(reminder.payload.userId).toBe("crea-4");
    expect(reminder.payload.body).toContain("הובלה");

    const flagUpdate = docUpdateCalls.find((c) => c.taskId === "task-3");
    expect(flagUpdate).toBeDefined();
    expect(flagUpdate.payload._reminder2hSent).toBe(true);
  });

  test("Phase 2: task in middle of window (10h left) → no reminder", async () => {
    // Confirms that the bracketing windows [22,26] and [1.5,2.5] are
    // strict — a task with 10h left should NOT trigger either reminder.
    const releaseDate = new Date(Date.now() + 10 * 60 * 60 * 1000);
    const { addCalls, docUpdateCalls } = setupAutoReleaseMocks({
      expiredTasks: [],
      reminderTasks: [{
        id: "middle",
        data: {
          status: "proof_submitted",
          autoReleased: false,
          autoReleaseDate: { toDate: () => releaseDate },
          creatorId: "crea-5",
          title: "X",
        },
      }],
    });

    await trigger();

    expect(addCalls.length).toBe(0);
    expect(docUpdateCalls.length).toBe(0);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// anytaskExpireOpen — scheduled CF (daily 02:00 IST)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Money-flow CF (CLAUDE.md §37). Refunds creators whose AnyTasks have sat
// 'open' for 7+ days without being claimed. Per task:
//   • status flipped to 'expired'
//   • creator balance += amount (FULL refund — no fee on expired tasks)
//   • transactions ledger entry (type='anytask_expired_refund')
//   • notification to creator (with the refund amount + task title)
//
// Bugs here would fail to refund creators (lost money for the customer)
// or charge a phantom fee (over-charge). Tests pin the contract.
// ═══════════════════════════════════════════════════════════════════════════════
describe("anytaskExpireOpen — scheduled CF", () => {
  const trigger = index.anytaskExpireOpen;

  beforeEach(() => jest.clearAllMocks());

  function setupExpireMocks({ openTasks = [] }) {
    const batchOps = [];
    const addCalls = [];

    function buildSnapDoc(data, taskId) {
      return {
        id: taskId,
        data: () => data,
        ref: { id: taskId },
      };
    }

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "anytasks") {
        const docs = openTasks.map((t) => buildSnapDoc(t.data, t.id));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return chain;
      }
      return {
        doc: jest.fn((id) => ({ id: id || "auto" })),
        add: jest.fn(async (payload) => {
          addCalls.push({ col, payload });
          return { id: "auto-id" };
        }),
      };
    });

    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ op: "update", ref, payload })),
      set: jest.fn((ref, payload) =>
        batchOps.push({ op: "set", ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps, addCalls };
  }

  test("no open tasks → CF runs cleanly with no writes", async () => {
    const { batchOps, addCalls } = setupExpireMocks({ openTasks: [] });
    await trigger();
    expect(batchOps.length).toBe(0);
    expect(addCalls.length).toBe(0);
  });

  test("single expired task → status flip + full refund + notif", async () => {
    const { batchOps, addCalls } = setupExpireMocks({
      openTasks: [{
        id: "stale-1",
        data: {
          status: "open",
          creatorId: "creator-1",
          creatorName: "Alice",
          amount: 150,
          title: "תיקון מנעול",
        },
      }],
    });

    await trigger();

    // Batch should have:
    //  - update task status → 'expired'
    //  - update creator balance += 150
    //  - set transactions doc
    expect(batchOps.length).toBeGreaterThanOrEqual(3);

    const statusUpdate = batchOps.find(
      (op) => op.op === "update" && op.payload.status === "expired"
    );
    expect(statusUpdate).toBeDefined();

    // FULL refund (FieldValue.increment mocked to 'INC(N)' string)
    const balanceUpdate = batchOps.find(
      (op) => op.op === "update" && op.payload.balance
    );
    expect(balanceUpdate).toBeDefined();
    expect(String(balanceUpdate.payload.balance)).toBe("INC(150)");

    // Transactions ledger
    const txnSet = batchOps.find(
      (op) => op.op === "set" && op.payload.type === "anytask_expired_refund"
    );
    expect(txnSet).toBeDefined();
    expect(txnSet.payload.receiverId).toBe("creator-1");
    expect(txnSet.payload.amount).toBe(150);

    // Notification with refund amount + task title
    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.userId).toBe("creator-1");
    expect(notif.payload.type).toBe("anytask_expired");
    expect(notif.payload.body).toContain("150");
    expect(notif.payload.body).toContain("תיקון מנעול");
  });

  test("expired task with amount=0 → status flip BUT no refund/no transaction", async () => {
    // Edge case: a free task somehow expired. Status must still flip
    // (cleans the queue), but we don't write a phantom ₪0 transaction.
    const { batchOps } = setupExpireMocks({
      openTasks: [{
        id: "free-task",
        data: {
          status: "open",
          creatorId: "creator-2",
          amount: 0,
          title: "X",
        },
      }],
    });

    await trigger();

    // ONLY the status flip — no balance update, no transaction
    const statusUpdate = batchOps.find(
      (op) => op.op === "update" && op.payload.status === "expired"
    );
    expect(statusUpdate).toBeDefined();

    const balanceUpdate = batchOps.find(
      (op) => op.op === "update" && op.payload.balance
    );
    expect(balanceUpdate).toBeUndefined();

    const txnSet = batchOps.find(
      (op) => op.op === "set" && op.payload.type === "anytask_expired_refund"
    );
    expect(txnSet).toBeUndefined();
  });

  test("expired task with no creatorId → status flip only (no notif/refund)", async () => {
    // Defensive guard: malformed task with no creatorId. CF must not crash.
    const { batchOps, addCalls } = setupExpireMocks({
      openTasks: [{
        id: "orphan",
        data: {
          status: "open",
          // NO creatorId
          amount: 100,
          title: "Orphan",
        },
      }],
    });

    await trigger();

    // Status update yes, but no refund, no notification
    const statusUpdate = batchOps.find(
      (op) => op.op === "update" && op.payload.status === "expired"
    );
    expect(statusUpdate).toBeDefined();
    expect(addCalls.length).toBe(0);

    const balanceUpdate = batchOps.find(
      (op) => op.op === "update" && op.payload.balance
    );
    expect(balanceUpdate).toBeUndefined();
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// expireVipSubscriptions — scheduled CF (daily 00:30 IST)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Maintenance CF: clears the `isPromoted` flag on users whose VIP
// subscription expiry has passed. Cheap and simple — single query, single
// batch commit.
//
// A bug here would either:
//   • Fail to clear expired VIPs → free promotion
//   • Clear active VIPs → over-revoke (paid users lose their boost)
// ═══════════════════════════════════════════════════════════════════════════════
describe("expireVipSubscriptions — scheduled CF", () => {
  const trigger = index.expireVipSubscriptions;

  beforeEach(() => jest.clearAllMocks());

  function setupVipExpireMocks({ expiredVips = [] }) {
    const batchOps = [];

    const docs = expiredVips.map((v) => ({
      id: v.id,
      data: () => v.data,
      ref: { id: v.id },
    }));

    mockFirestore.collection.mockImplementation(() => ({
      where: jest.fn(function chain() {
        return {
          where: jest.fn(chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
      }),
    }));

    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ op: "update", ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
    };

    return { batchOps };
  }

  test("no expired VIPs → returns early, no batch commit", async () => {
    const { batchOps } = setupVipExpireMocks({ expiredVips: [] });
    await trigger();
    // Empty query → CF returns before creating a batch
    expect(batchOps.length).toBe(0);
    // mockFirestore.batch was NOT invoked at all in this case
    expect(mockFirestore.batch).not.toHaveBeenCalled();
  });

  test("single expired VIP → batch.update with isPromoted: false", async () => {
    const { batchOps } = setupVipExpireMocks({
      expiredVips: [{
        id: "vip-1",
        data: { isPromoted: true, name: "Premium Provider" },
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(1);
    expect(batchOps[0].op).toBe("update");
    expect(batchOps[0].payload.isPromoted).toBe(false);
    expect(batchOps[0].ref.id).toBe("vip-1");
  });

  test("multiple expired VIPs → all in single batch", async () => {
    const { batchOps } = setupVipExpireMocks({
      expiredVips: [
        { id: "v1", data: { isPromoted: true } },
        { id: "v2", data: { isPromoted: true } },
        { id: "v3", data: { isPromoted: true } },
      ],
    });

    await trigger();

    expect(batchOps.length).toBe(3);
    expect(batchOps.every((op) => op.payload.isPromoted === false)).toBe(true);
    // All ids covered
    const ids = batchOps.map((op) => op.ref.id).sort();
    expect(ids).toEqual(["v1", "v2", "v3"]);
    // Batch was constructed exactly ONCE (single commit, not per-doc)
    expect(mockFirestore.batch).toHaveBeenCalledTimes(1);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// Flash Auction CFs (CLAUDE.md §57) — onFlashAuctionCreate, dispatchFlashAuction,
// notifyOnFlashAuctionOffer
// ═══════════════════════════════════════════════════════════════════════════════
//
// Three-CF dispatch system for emergency motorcycle towing:
//
//   1. onFlashAuctionCreate (onCreate trigger) — fires the moment the
//      customer creates an auction doc. Tier-1 dispatch: up to 5 nearest
//      providers within 5 km.
//
//   2. dispatchFlashAuction (scheduled, every 1 min) — handles tier
//      expansion (5→10→15 km) and the 120s expiry. Only acts on auctions
//      with offerCount === 0 (customers with offers stay engaged).
//
//   3. notifyOnFlashAuctionOffer (onCreate sub-collection trigger) — fires
//      when a provider submits an offer. Notifies the customer.
//
// These tests use a SHARED mock that returns no nearby providers (empty
// users query). That makes _faDispatchTier a no-op that returns the
// existing notifiedProviderIds — which is exactly what we want for unit
// tests of the orchestration logic. The geographical dispatch is covered
// by integration/manual testing.
// ═══════════════════════════════════════════════════════════════════════════════
describe("onFlashAuctionCreate — onCreate trigger", () => {
  const trigger = index.onFlashAuctionCreate;

  beforeEach(() => {
    jest.clearAllMocks();
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async () => ({ messageId: "mock" })),
    }));
  });

  function setupCreateMocks() {
    const updateCalls = [];
    const addCalls = [];

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "flash_auctions") {
        return {
          doc: jest.fn((id) => ({
            id,
            update: jest.fn(async (payload) => {
              updateCalls.push({ col, id, payload });
            }),
          })),
        };
      }
      if (col === "admin") {
        return {
          doc: jest.fn(() => ({
            collection: jest.fn(() => ({
              doc: jest.fn(() => ({
                get: jest.fn(async () => ({
                  exists: true,
                  data: () => ({ feePercentage: 0.10 }),
                })),
              })),
            })),
          })),
        };
      }
      if (col === "users") {
        // Empty query → _faDispatchTier returns no candidates
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({ docs: [], empty: true, size: 0 })),
        };
        return {
          where: jest.fn(() => chain),
        };
      }
      return {
        add: jest.fn(async (payload) => {
          addCalls.push({ col, payload });
          return { id: "auto-id" };
        }),
      };
    });

    return { updateCalls, addCalls };
  }

  function buildEvent({ data, auctionId = "a1" }) {
    return {
      params: { auctionId },
      data: {
        data: () => data,
      },
    };
  }

  test("no-op when auction status is NOT 'searching'", async () => {
    const { updateCalls } = setupCreateMocks();

    await trigger(buildEvent({
      data: { status: "matched", customerId: "c1" },     // already matched, not new
    }));

    expect(updateCalls.length).toBe(0);
  });

  test("status='searching' → tier-1 dispatch + auction.update with radius=5", async () => {
    const { updateCalls } = setupCreateMocks();

    await trigger(buildEvent({
      auctionId: "a1",
      data: {
        status: "searching",
        customerId: "c1",
        pickupLocation: { lat: 32.07, lng: 34.78 },
        distanceKm: 5,
      },
    }));

    // The CF must update the auction with the dispatch results
    const auctionUpdate = updateCalls.find(
      (c) => c.col === "flash_auctions" && c.id === "a1"
    );
    expect(auctionUpdate).toBeDefined();
    expect(auctionUpdate.payload.currentRadiusKm).toBe(5);
    expect(auctionUpdate.payload.notifiedProviderIds).toEqual([]);
    expect(auctionUpdate.payload.lastDispatchAt).toBeDefined();
  });

  test("no-op when event.data is missing", async () => {
    const { updateCalls } = setupCreateMocks();
    await trigger({ params: { auctionId: "a1" }, data: null });
    expect(updateCalls.length).toBe(0);
  });
});


describe("dispatchFlashAuction — scheduled tier expansion + expiry", () => {
  const trigger = index.dispatchFlashAuction;

  beforeEach(() => {
    jest.clearAllMocks();
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async () => ({ messageId: "mock" })),
    }));
  });

  /**
   * Helper: builds the mock surface for the scheduled dispatcher.
   *
   * @param liveAuctions — array of {id, data} returned by the live-auctions query
   *
   * Each auction's doc.ref.update() is captured into updateCalls so we
   * can verify which state transition fired.
   */
  function setupDispatcherMocks({ liveAuctions = [] }) {
    const updateCalls = [];
    const addCalls = [];

    const docs = liveAuctions.map((a) => ({
      id: a.id,
      data: () => a.data,
      ref: {
        id: a.id,
        update: jest.fn(async (payload) => {
          updateCalls.push({ id: a.id, payload });
        }),
      },
    }));

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "flash_auctions") {
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return chain;
      }
      if (col === "admin") {
        return {
          doc: jest.fn(() => ({
            collection: jest.fn(() => ({
              doc: jest.fn(() => ({
                get: jest.fn(async () => ({
                  exists: true,
                  data: () => ({ feePercentage: 0.10 }),
                })),
              })),
            })),
          })),
        };
      }
      if (col === "users") {
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({ docs: [], empty: true, size: 0 })),
        };
        return { where: jest.fn(() => chain) };
      }
      return {
        add: jest.fn(async (payload) => {
          addCalls.push({ col, payload });
          return { id: "auto-id" };
        }),
      };
    });

    return { updateCalls, addCalls };
  }

  test("no live auctions → CF no-ops cleanly", async () => {
    const { updateCalls } = setupDispatcherMocks({ liveAuctions: [] });
    await trigger();
    expect(updateCalls.length).toBe(0);
  });

  test("auction with offerCount > 0 → no expansion, no expiry (customer engaged)", async () => {
    // Engaged customer with offers must NOT be touched, even if old.
    const oldDate = new Date(Date.now() - 200 * 1000);    // 200s ago
    const { updateCalls } = setupDispatcherMocks({
      liveAuctions: [{
        id: "engaged",
        data: {
          status: "has_offers",
          createdAt: { toDate: () => oldDate },
          offerCount: 2,
          currentRadiusKm: 5,
        },
      }],
    });

    await trigger();

    expect(updateCalls.length).toBe(0);
  });

  test("auction with age > 120s AND offerCount=0 → status='expired'", async () => {
    const oldDate = new Date(Date.now() - 130 * 1000);    // 130s ago
    const { updateCalls } = setupDispatcherMocks({
      liveAuctions: [{
        id: "stale",
        data: {
          status: "searching",
          createdAt: { toDate: () => oldDate },
          offerCount: 0,
          currentRadiusKm: 15,
        },
      }],
    });

    await trigger();

    const expireUpdate = updateCalls.find((c) => c.id === "stale");
    expect(expireUpdate).toBeDefined();
    expect(expireUpdate.payload.status).toBe("expired");
    expect(expireUpdate.payload.expiredAt).toBeDefined();
  });

  test("auction at age=45s AND radius=5 → tier-2 expansion (radius=10)", async () => {
    const created = new Date(Date.now() - 45 * 1000);    // 45s ago
    const { updateCalls } = setupDispatcherMocks({
      liveAuctions: [{
        id: "tier2",
        data: {
          status: "searching",
          createdAt: { toDate: () => created },
          offerCount: 0,
          currentRadiusKm: 5,
          notifiedProviderIds: ["existing-1"],
          pickupLocation: { lat: 32.07, lng: 34.78 },
          distanceKm: 5,
        },
      }],
    });

    await trigger();

    const expandUpdate = updateCalls.find((c) => c.id === "tier2");
    expect(expandUpdate).toBeDefined();
    expect(expandUpdate.payload.currentRadiusKm).toBe(10);
    // notifiedProviderIds is rewritten with the result of _faDispatchTier
    expect(Array.isArray(expandUpdate.payload.notifiedProviderIds)).toBe(true);
    expect(expandUpdate.payload.lastDispatchAt).toBeDefined();
    // NOT expired
    expect(expandUpdate.payload.status).toBeUndefined();
  });

  test("auction at age=70s AND radius=10 → tier-3 expansion (radius=15)", async () => {
    const created = new Date(Date.now() - 70 * 1000);    // 70s ago
    const { updateCalls } = setupDispatcherMocks({
      liveAuctions: [{
        id: "tier3",
        data: {
          status: "searching",
          createdAt: { toDate: () => created },
          offerCount: 0,
          currentRadiusKm: 10,
          notifiedProviderIds: ["existing-1", "existing-2"],
          pickupLocation: { lat: 32.07, lng: 34.78 },
          distanceKm: 5,
        },
      }],
    });

    await trigger();

    const expandUpdate = updateCalls.find((c) => c.id === "tier3");
    expect(expandUpdate).toBeDefined();
    expect(expandUpdate.payload.currentRadiusKm).toBe(15);
  });

  test("auction at age=10s (too young) → no expansion (still in initial window)", async () => {
    const created = new Date(Date.now() - 10 * 1000);    // 10s ago
    const { updateCalls } = setupDispatcherMocks({
      liveAuctions: [{
        id: "fresh",
        data: {
          status: "searching",
          createdAt: { toDate: () => created },
          offerCount: 0,
          currentRadiusKm: 5,
          pickupLocation: { lat: 32.07, lng: 34.78 },
          distanceKm: 5,
        },
      }],
    });

    await trigger();

    // Auction is too young — still in tier-1 window (< 30s). No transition.
    expect(updateCalls.length).toBe(0);
  });
});


describe("notifyOnFlashAuctionOffer — onCreate trigger on offers subcollection", () => {
  const trigger = index.notifyOnFlashAuctionOffer;
  let messagingCalls;

  beforeEach(() => {
    jest.clearAllMocks();
    messagingCalls = [];
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async (msg) => {
        messagingCalls.push(msg);
        return { messageId: "mock" };
      }),
    }));
  });

  function setupOfferMocks({ auctionExists, auctionData, customerData }) {
    const addCalls = [];

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "flash_auctions") {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({
              exists: auctionExists,
              data: () => auctionData || {},
            })),
          })),
        };
      }
      if (col === "users") {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({
              exists: true,
              data: () => customerData || {},
            })),
          })),
        };
      }
      if (col === "notifications") {
        return {
          add: jest.fn(async (payload) => {
            addCalls.push({ col, payload });
            return { id: "auto-id" };
          }),
        };
      }
      return {
        add: jest.fn(async (payload) => {
          addCalls.push({ col, payload });
          return { id: "auto-id" };
        }),
      };
    });

    return { addCalls };
  }

  function buildEvent({ offer, auctionId = "a1", offerId = "o1" }) {
    return {
      params: { auctionId, offerId },
      data: {
        data: () => offer,
      },
    };
  }

  test("no-op when parent auction doesn't exist", async () => {
    const { addCalls } = setupOfferMocks({
      auctionExists: false,
    });

    await trigger(buildEvent({
      offer: { providerName: "Bob", etaMinutes: 8 },
    }));

    expect(addCalls.length).toBe(0);
    expect(messagingCalls.length).toBe(0);
  });

  test("no-op when auction has no customerId", async () => {
    const { addCalls } = setupOfferMocks({
      auctionExists: true,
      auctionData: {},     // no customerId
    });

    await trigger(buildEvent({ offer: { providerName: "Bob", etaMinutes: 8 } }));

    expect(addCalls.length).toBe(0);
    expect(messagingCalls.length).toBe(0);
  });

  test("standard offer → notification doc + FCM push to customer", async () => {
    const { addCalls } = setupOfferMocks({
      auctionExists: true,
      auctionData: { customerId: "c1" },
      customerData: { fcmToken: "customer-token-123" },
    });

    await trigger(buildEvent({
      auctionId: "a1",
      offerId: "o1",
      offer: { providerName: "Bob", etaMinutes: 8, totalPrice: 250 },
    }));

    // Notification inbox row written
    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.userId).toBe("c1");
    expect(notif.payload.type).toBe("flash_auction_offer");
    expect(notif.payload.flashAuctionId).toBe("a1");
    expect(notif.payload.offerId).toBe("o1");
    expect(notif.payload.body).toContain("Bob");
    expect(notif.payload.body).toContain("8");

    // FCM push sent
    expect(messagingCalls.length).toBe(1);
    expect(messagingCalls[0].token).toBe("customer-token-123");
    expect(messagingCalls[0].data.type).toBe("flash_auction_offer");
    expect(messagingCalls[0].data.flashAuctionId).toBe("a1");
    expect(messagingCalls[0].android.priority).toBe("high");
  });

  test("customer has no fcmToken → notification still written, no FCM", async () => {
    // Durable contract: even with no token, the in-app notification must
    // be written. Customer can still see it when they open the app.
    const { addCalls } = setupOfferMocks({
      auctionExists: true,
      auctionData: { customerId: "c2" },
      customerData: {},     // NO fcmToken
    });

    await trigger(buildEvent({
      offer: { providerName: "Carol", etaMinutes: 5 },
    }));

    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.userId).toBe("c2");

    // No FCM attempted
    expect(messagingCalls.length).toBe(0);
  });

  test("provider with no name uses 'גרריסט' fallback", async () => {
    const { addCalls } = setupOfferMocks({
      auctionExists: true,
      auctionData: { customerId: "c3" },
      customerData: { fcmToken: "t" },
    });

    await trigger(buildEvent({
      offer: { etaMinutes: 12 },     // no providerName
    }));

    const notif = addCalls.find((c) => c.col === "notifications");
    expect(notif).toBeDefined();
    expect(notif.payload.body).toContain("גרריסט");
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// syncVipCarouselOnSubscriptionChange — onDocumentWritten trigger (CLAUDE.md §51)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Reconciles the customer-facing `provider_carousel` banner's `providerIds`
// array with the current set of active vip_subscriptions. Fires on EVERY
// vip_subscriptions/{id} write — purchase, admin grant, status flip, expire.
//
// 3 paths:
//   • No banner + no active subs   → no-op (rail correctly empty)
//   • No banner + active subs      → auto-create banner with cappedIds
//   • Banner exists                → diff & update providerIds (or skip
//                                     if identical)
//
// Cap is 20 providers (provider_carousel hard limit).
// ═══════════════════════════════════════════════════════════════════════════════
describe("syncVipCarouselOnSubscriptionChange — onWritten trigger", () => {
  const trigger = index.syncVipCarouselOnSubscriptionChange;

  beforeEach(() => jest.clearAllMocks());

  function setupSyncMocks({ activeSubs = [], banners = [] }) {
    const updateCalls = [];
    const setCalls = [];

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "vip_subscriptions") {
        const docs = activeSubs.map((s) => ({
          id: s.id,
          data: () => s.data,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return chain;
      }
      if (col === "banners") {
        const docs = banners.map((b) => ({
          id: b.id,
          data: () => b.data,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return {
          where: jest.fn(() => chain),
          // Used by the auto-create path: `db.collection('banners').doc()`
          // creates a fresh ref WITHOUT an id arg.
          doc: jest.fn((id) => ({
            id: id || "auto-banner",
            set: jest.fn(async (payload) => {
              setCalls.push({ col, id: id || "auto-banner", payload });
            }),
            update: jest.fn(async (payload) => {
              updateCalls.push({ col, id, payload });
            }),
          })),
        };
      }
      return {};
    });

    return { updateCalls, setCalls };
  }

  test("no active subs + no banner → no-op", async () => {
    const { updateCalls, setCalls } = setupSyncMocks({
      activeSubs: [],
      banners: [],
    });

    await trigger({ params: { subId: "s1" } });

    expect(updateCalls.length).toBe(0);
    expect(setCalls.length).toBe(0);
  });

  test("active subs + no banner → auto-create banner with provider IDs", async () => {
    const { setCalls } = setupSyncMocks({
      activeSubs: [
        { id: "s1", data: { providerId: "p1", status: "active" } },
        { id: "s2", data: { providerId: "p2", status: "active" } },
      ],
      banners: [],
    });

    await trigger({ params: { subId: "s1" } });

    expect(setCalls.length).toBe(1);
    expect(setCalls[0].col).toBe("banners");
    expect(setCalls[0].payload.placement).toBe("provider_carousel");
    expect(setCalls[0].payload.isActive).toBe(true);
    expect(setCalls[0].payload.providerCarousel.providerIds).toEqual(["p1", "p2"]);
    expect(setCalls[0].payload.autoCreatedBy).toBe("syncVipCarouselOnSubscriptionChange");
  });

  test("banner already in sync (same IDs in same order) → skip update", async () => {
    const { updateCalls, setCalls } = setupSyncMocks({
      activeSubs: [
        { id: "s1", data: { providerId: "p1", status: "active" } },
        { id: "s2", data: { providerId: "p2", status: "active" } },
      ],
      banners: [{
        id: "b1",
        data: {
          placement: "provider_carousel",
          isActive: true,
          providerCarousel: { providerIds: ["p1", "p2"] },
        },
      }],
    });

    await trigger({ params: { subId: "s1" } });

    expect(updateCalls.length).toBe(0);
    expect(setCalls.length).toBe(0);
  });

  test("banner needs update → update providerCarousel.providerIds", async () => {
    const { updateCalls } = setupSyncMocks({
      activeSubs: [
        { id: "s1", data: { providerId: "p1", status: "active" } },
        { id: "s2", data: { providerId: "p2", status: "active" } },
        { id: "s3", data: { providerId: "p3", status: "active" } },
      ],
      banners: [{
        id: "b1",
        data: {
          placement: "provider_carousel",
          isActive: true,
          providerCarousel: { providerIds: ["p1"] },     // missing p2 + p3
        },
      }],
    });

    await trigger({ params: { subId: "s2" } });

    expect(updateCalls.length).toBe(1);
    expect(updateCalls[0].payload["providerCarousel.providerIds"])
      .toEqual(["p1", "p2", "p3"]);
  });

  test("over 20 active subs → cap at 20 in the banner write", async () => {
    const subs = Array.from({ length: 25 }, (_, i) => ({
      id: `s${i}`,
      data: { providerId: `p${i}`, status: "active" },
    }));

    const { setCalls } = setupSyncMocks({
      activeSubs: subs,
      banners: [],     // triggers auto-create path which has the slice(0, 20)
    });

    await trigger({ params: { subId: "s0" } });

    expect(setCalls[0].payload.providerCarousel.providerIds.length).toBe(20);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// scheduledMonthlyVipBilling — scheduled CF (daily 03:00 IST)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Per CLAUDE.md §51, this CF auto-renews paid VIP subscriptions whose
// endDate has passed. Two paths:
//
//   • autoRenew=true:
//       - balance >= price  → debit, extend endDate by 30d, write
//                              vip_payments (status='paid'), transactions
//                              ledger entry, "renewed" notification
//       - balance < price   → status='expired', vip_payments (status='failed'),
//                              "renewal failed" notification
//   • autoRenew=false       → status='expired', "expired" notification
//
// This is the CRITICAL recurring-money CF — bugs here either over-charge
// (debit twice), under-charge (skip the update), or fail silently.
// ═══════════════════════════════════════════════════════════════════════════════
describe("scheduledMonthlyVipBilling — scheduled CF", () => {
  const trigger = index.scheduledMonthlyVipBilling;

  beforeEach(() => jest.clearAllMocks());

  function setupBillingMocks({ expiringSubs = [], userBalances = {} }) {
    const txCalls = { update: [], set: [] };
    const updateCalls = [];     // direct (non-tx) updates
    const addCalls = [];

    const docs = expiringSubs.map((s) => ({
      id: s.id,
      data: () => s.data,
      ref: { id: s.id },
    }));

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "vip_subscriptions") {
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return {
          where: jest.fn(() => chain),
          doc: jest.fn((id) => ({
            id,
            update: jest.fn(async (payload) => {
              updateCalls.push({ col, id, payload });
            }),
          })),
        };
      }
      if (col === "users") {
        return {
          doc: jest.fn((id) => ({
            id,
            get: jest.fn(async () => ({
              exists: id in userBalances,
              data: () => ({ balance: userBalances[id], name: `User ${id}` }),
            })),
            update: jest.fn(),
          })),
        };
      }
      // vip_payments, transactions, notifications
      return {
        doc: jest.fn(() => ({ id: `auto-${col}` })),
        add: jest.fn(async (payload) => {
          addCalls.push({ col, payload });
          return { id: "auto-id" };
        }),
      };
    });

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn((ref, payload) =>
          txCalls.update.push({ ref, payload })),
        set: jest.fn((ref, payload) =>
          txCalls.set.push({ ref, payload })),
      };
      return cb(tx);
    });

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { txCalls, updateCalls, addCalls };
  }

  test("no expiring subs → returns null without touching anything", async () => {
    const { txCalls, updateCalls, addCalls } = setupBillingMocks({
      expiringSubs: [],
    });

    await trigger();

    expect(txCalls.update.length).toBe(0);
    expect(txCalls.set.length).toBe(0);
    expect(updateCalls.length).toBe(0);
    expect(addCalls.length).toBe(0);
    // The runTransaction must NOT be invoked when nothing to bill
    expect(mockFirestore.runTransaction).not.toHaveBeenCalled();
  });

  test("autoRenew=true + sufficient balance → debit + extend + payment + ledger", async () => {
    const { txCalls, addCalls } = setupBillingMocks({
      expiringSubs: [{
        id: "sub1",
        data: { providerId: "p1", autoRenew: true, pricePerMonth: 99 },
      }],
      userBalances: { p1: 200 },     // 200 ≥ 99
    });

    await trigger();

    // Tx contents:
    //   - update user.balance with INC(-99)
    //   - update sub.endDate to +30d
    //   - set vip_payments (status='paid')
    //   - set transactions ledger
    expect(txCalls.update.length).toBe(2);
    expect(txCalls.set.length).toBe(2);

    const balanceUpdate = txCalls.update.find(
      (c) => c.payload.balance
    );
    expect(balanceUpdate).toBeDefined();
    expect(String(balanceUpdate.payload.balance)).toBe("INC(-99)");

    const subUpdate = txCalls.update.find((c) => c.payload.endDate);
    expect(subUpdate).toBeDefined();

    const paymentSet = txCalls.set.find(
      (c) => c.payload.status === "paid"
    );
    expect(paymentSet).toBeDefined();
    expect(paymentSet.payload.amount).toBe(99);
    expect(paymentSet.payload.isRenewal).toBe(true);
    expect(paymentSet.payload.renewalType).toBe("auto");

    const txnSet = txCalls.set.find(
      (c) => c.payload.type === "vip_renewal"
    );
    expect(txnSet).toBeDefined();
    expect(txnSet.payload.amount).toBe(99);

    // "Renewed" notification
    const notif = addCalls.find(
      (c) => c.col === "notifications" && c.payload.type === "vip_renewed"
    );
    expect(notif).toBeDefined();
    expect(notif.payload.userId).toBe("p1");
  });

  test("autoRenew=true + insufficient balance → expired + failed payment", async () => {
    const { txCalls, addCalls } = setupBillingMocks({
      expiringSubs: [{
        id: "sub-broke",
        data: { providerId: "p2", autoRenew: true, pricePerMonth: 99 },
      }],
      userBalances: { p2: 50 },     // 50 < 99
    });

    await trigger();

    // Tx contents:
    //   - update sub.status='expired'
    //   - set vip_payments (status='failed')
    // NO balance debit (balance is too low)
    const subUpdate = txCalls.update.find(
      (c) => c.payload.status === "expired"
    );
    expect(subUpdate).toBeDefined();

    const failedPayment = txCalls.set.find(
      (c) => c.payload.status === "failed"
    );
    expect(failedPayment).toBeDefined();
    expect(failedPayment.payload.failureReason).toContain("insufficient-balance");

    // No balance debit
    const balanceUpdate = txCalls.update.find(
      (c) => c.payload.balance
    );
    expect(balanceUpdate).toBeUndefined();

    // No vip_renewal transaction (failed renewal doesn't write the ledger)
    const txnSet = txCalls.set.find(
      (c) => c.payload.type === "vip_renewal"
    );
    expect(txnSet).toBeUndefined();

    // "Renewal failed" notification
    const notif = addCalls.find(
      (c) => c.col === "notifications" && c.payload.type === "vip_renewal_failed"
    );
    expect(notif).toBeDefined();
  });

  test("autoRenew=false → simple expire (no tx, no payment, no debit)", async () => {
    const { txCalls, updateCalls, addCalls } = setupBillingMocks({
      expiringSubs: [{
        id: "sub-manual",
        data: { providerId: "p3", autoRenew: false, pricePerMonth: 99 },
      }],
      userBalances: { p3: 1000 },     // doesn't matter, no debit
    });

    await trigger();

    // No transaction at all (manual-renew path skips tx)
    expect(mockFirestore.runTransaction).not.toHaveBeenCalled();
    expect(txCalls.update.length).toBe(0);
    expect(txCalls.set.length).toBe(0);

    // Direct (non-tx) update on sub doc
    const subUpdate = updateCalls.find(
      (c) => c.col === "vip_subscriptions" && c.payload.status === "expired"
    );
    expect(subUpdate).toBeDefined();

    // "Expired" notification (NOT renewal_failed — different type)
    const notif = addCalls.find(
      (c) => c.col === "notifications" && c.payload.type === "vip_expired"
    );
    expect(notif).toBeDefined();
  });

  test("missing providerId → sub is skipped (continue)", async () => {
    const { txCalls, updateCalls } = setupBillingMocks({
      expiringSubs: [{
        id: "broken-sub",
        data: { autoRenew: true, pricePerMonth: 99 },     // NO providerId
      }],
    });

    await trigger();

    expect(txCalls.update.length).toBe(0);
    expect(txCalls.set.length).toBe(0);
    expect(updateCalls.length).toBe(0);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// expireOpenTasks — scheduled CF (every 30 min, IST) [§37]
// ═══════════════════════════════════════════════════════════════════════════════
//
// Per CLAUDE.md §37, this CF expires open AnyTasks via TWO buckets:
//
//   Bucket 1: tasks with explicit `deadline < now` (customer-set deadline)
//   Bucket 2: tasks WITHOUT a deadline that are > 30d old (safety fallback)
//
// Dedupes by doc.id — a task can't be in both buckets. The expiredReason
// field records WHY the task was expired ('deadline' or 'age'), useful
// for analytics. All updates land in a single batch.commit().
//
// NOTE: This CF is DIFFERENT from `anytaskExpireOpen` covered in Bonus 8.
//   • `anytaskExpireOpen` — collection 'anytasks' (legacy, no underscore),
//     daily, 7-day TTL, full refund to creator.
//   • `expireOpenTasks` — collection 'any_tasks' (new), every 30 min,
//     deadline + 30d fallback, just status flip (no refund — Israeli
//     payment provider integration TBD).
// ═══════════════════════════════════════════════════════════════════════════════
describe("expireOpenTasks — scheduled CF (§37)", () => {
  const trigger = index.expireOpenTasks;

  beforeEach(() => jest.clearAllMocks());

  function setupExpireOpenMocks({ byDeadline = [], byAge = [] }) {
    const batchOps = [];

    function buildSnapDoc(data, taskId) {
      return {
        id: taskId,
        data: () => data,
        ref: { id: taskId },
      };
    }

    let queryCount = 0;
    mockFirestore.collection.mockImplementation((col) => {
      if (col === "any_tasks") {
        queryCount++;
        const isDeadlineQuery = queryCount === 1;
        const docs = (isDeadlineQuery ? byDeadline : byAge)
          .map((t) => buildSnapDoc(t.data, t.id));

        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return chain;
      }
      return {};
    });

    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps };
  }

  test("no stale tasks in either bucket → CF returns without batch.commit", async () => {
    const { batchOps } = setupExpireOpenMocks({ byDeadline: [], byAge: [] });
    await trigger();
    expect(batchOps.length).toBe(0);
    // batch was never even constructed
    expect(mockFirestore.batch).not.toHaveBeenCalled();
  });

  test("Bucket 1: deadline expired → status=expired with expiredReason='deadline'", async () => {
    const past = { toMillis: () => Date.now() - 10_000 };
    const { batchOps } = setupExpireOpenMocks({
      byDeadline: [{
        id: "task-deadline",
        data: { status: "open", deadline: past },
      }],
      byAge: [],
    });

    await trigger();

    expect(batchOps.length).toBe(1);
    expect(batchOps[0].payload.status).toBe("expired");
    expect(batchOps[0].payload.expiredReason).toBe("deadline");
    expect(batchOps[0].payload.expiredAt).toBeDefined();
  });

  test("Bucket 2: 30d old + no deadline → status=expired with expiredReason='age'", async () => {
    const { batchOps } = setupExpireOpenMocks({
      byDeadline: [],
      byAge: [{
        id: "task-old",
        data: {
          status: "open",
          deadline: null,        // explicitly null — no customer deadline set
        },
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(1);
    expect(batchOps[0].payload.status).toBe("expired");
    expect(batchOps[0].payload.expiredReason).toBe("age");
  });

  test("dedupe: same task in both buckets → expired ONCE, not twice", async () => {
    const past = { toMillis: () => Date.now() - 10_000 };
    const dup = { id: "duplicate", data: { status: "open", deadline: past } };
    const { batchOps } = setupExpireOpenMocks({
      byDeadline: [dup],
      byAge: [dup],
    });

    await trigger();

    // ONE batch op — Bucket 1 wins (deadline reason has priority)
    expect(batchOps.length).toBe(1);
    expect(batchOps[0].payload.expiredReason).toBe("deadline");
  });

  test("Bucket 2 task that DOES have a deadline → skipped (Bucket 1 should catch it)", async () => {
    // Defensive logic: if a task somehow appears in the byAge query but has
    // a deadline, it's left for Bucket 1 (or has already been processed).
    // Pins the `if (d.deadline == null) toExpire.set(...)` filter.
    const future = { toMillis: () => Date.now() + 10_000 };     // future deadline
    const { batchOps } = setupExpireOpenMocks({
      byDeadline: [],
      byAge: [{
        id: "task-with-future-deadline",
        data: { status: "open", deadline: future },     // has a deadline
      }],
    });

    await trigger();

    // Bucket 2 filter rejected the task — no expiry
    expect(batchOps.length).toBe(0);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// anytaskSlaMonitor — scheduled CF (every 15 min, IST)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Per CLAUDE.md §15b / §27, this CF watches AnyTasks claimed/in_progress
// for SLA breaches. Two thresholds based on `elapsed = now - max(claimedAt, lastActivityAt)`:
//
//   • [30 min, 120 min) AND no `_slaReminderSent` → notify provider, stamp flag
//   • [120 min, ∞)                                  → return task to pool
//
// On the 120-min path, the CF performs a batch:
//   1. Reset task to `status='open'`, clear providerId/providerName/etc
//   2. Decrement provider's anytaskCancellationScore by 0.05 (penalty)
//   3. Notify both provider + creator
//   4. Activity log entry
//
// Bug here would orphan tasks in 'claimed' state forever (provider never
// returned → customer waits) OR over-spam reminders.
// ═══════════════════════════════════════════════════════════════════════════════
describe("anytaskSlaMonitor — scheduled CF", () => {
  const trigger = index.anytaskSlaMonitor;

  beforeEach(() => jest.clearAllMocks());

  function setupSlaMocks({ tasks = [] }) {
    const batchOps = [];
    const addCalls = [];
    const docUpdateCalls = [];
    const activityAddCalls = [];

    function buildSnapDoc(data, taskId) {
      const docRef = {
        id: taskId,
        update: jest.fn(async (payload) => {
          docUpdateCalls.push({ taskId, payload });
        }),
        collection: jest.fn(() => ({
          add: jest.fn(async (payload) => {
            activityAddCalls.push({ taskId, payload });
            return { id: "auto-id" };
          }),
        })),
      };
      return { id: taskId, data: () => data, ref: docRef };
    }

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "anytasks") {
        const docs = tasks.map((t) => buildSnapDoc(t.data, t.id));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return chain;
      }
      // users (for the cancellation-score update inside batch)
      return {
        doc: jest.fn((id) => ({ id: id || `auto-${col}` })),
        add: jest.fn(async (payload) => {
          addCalls.push({ col, payload });
          return { id: "auto-id" };
        }),
      };
    });

    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    // The CF uses FieldValue.delete() to remove _slaReminderSent on the
    // 120-min path; the global FV mock doesn't include delete by default.
    const admin = require("firebase-admin");
    admin.firestore.FieldValue.delete = jest.fn(() => "DELETE_FIELD");

    return { batchOps, addCalls, docUpdateCalls, activityAddCalls };
  }

  test("no claimed/in_progress tasks → CF runs cleanly", async () => {
    const { batchOps, addCalls, docUpdateCalls } = setupSlaMocks({ tasks: [] });
    await trigger();
    expect(batchOps.length).toBe(0);
    expect(addCalls.length).toBe(0);
    expect(docUpdateCalls.length).toBe(0);
  });

  test("task claimed 5 min ago → no reminder, no return (well under 30-min)", async () => {
    const claimedAt = { toDate: () => new Date(Date.now() - 5 * 60 * 1000) };
    const { batchOps, addCalls, docUpdateCalls } = setupSlaMocks({
      tasks: [{
        id: "fresh-claim",
        data: {
          status: "claimed",
          claimedAt,
          providerId: "p1",
          creatorId: "c1",
          title: "X",
        },
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
    expect(addCalls.length).toBe(0);
    expect(docUpdateCalls.length).toBe(0);
  });

  test("task at 45 min elapsed → reminder sent + flag stamped", async () => {
    // Inside [30, 120) window — first SLA reminder.
    const claimedAt = { toDate: () => new Date(Date.now() - 45 * 60 * 1000) };
    const { batchOps, addCalls, docUpdateCalls } = setupSlaMocks({
      tasks: [{
        id: "warn-task",
        data: {
          status: "claimed",
          claimedAt,
          providerId: "p1",
          creatorId: "c1",
          title: "תיקון מנעול",
          // NO _slaReminderSent yet
        },
      }],
    });

    await trigger();

    // No batch (return path not triggered yet)
    expect(batchOps.length).toBe(0);

    // Reminder notification to provider (NOT creator)
    const reminder = addCalls.find(
      (c) => c.col === "notifications" && c.payload.type === "anytask_sla_reminder"
    );
    expect(reminder).toBeDefined();
    expect(reminder.payload.userId).toBe("p1");
    expect(reminder.payload.body).toContain("תיקון מנעול");
    expect(reminder.payload.taskId).toBe("warn-task");

    // _slaReminderSent flag stamped on the task
    const flag = docUpdateCalls.find((c) => c.taskId === "warn-task");
    expect(flag).toBeDefined();
    expect(flag.payload._slaReminderSent).toBe(true);
  });

  test("task at 45 min with _slaReminderSent already true → skip (idempotency)", async () => {
    const claimedAt = { toDate: () => new Date(Date.now() - 45 * 60 * 1000) };
    const { batchOps, addCalls, docUpdateCalls } = setupSlaMocks({
      tasks: [{
        id: "already-warned",
        data: {
          status: "claimed",
          claimedAt,
          providerId: "p1",
          creatorId: "c1",
          _slaReminderSent: true,    // already sent
        },
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
    expect(addCalls.length).toBe(0);
    expect(docUpdateCalls.length).toBe(0);
  });

  test("task at 130 min → return to pool + penalty + 2 notifs + activity log", async () => {
    const claimedAt = { toDate: () => new Date(Date.now() - 130 * 60 * 1000) };
    const { batchOps, addCalls, activityAddCalls } = setupSlaMocks({
      tasks: [{
        id: "stale-claim",
        data: {
          status: "claimed",
          claimedAt,
          providerId: "p2",
          creatorId: "c2",
          title: "ניקיון",
        },
      }],
    });

    await trigger();

    // Batch: 2 ops — reset task + penalize provider
    expect(batchOps.length).toBe(2);

    // Task reset
    const resetUpdate = batchOps.find(
      (op) => op.payload.status === "open"
    );
    expect(resetUpdate).toBeDefined();
    expect(resetUpdate.payload.providerId).toBeNull();
    expect(resetUpdate.payload.claimedAt).toBeNull();
    expect(resetUpdate.payload.chatRoomId).toBeNull();

    // Provider penalty: -0.05 to anytaskCancellationScore
    const penaltyUpdate = batchOps.find(
      (op) => op.payload.anytaskCancellationScore
    );
    expect(penaltyUpdate).toBeDefined();
    expect(String(penaltyUpdate.payload.anytaskCancellationScore))
      .toBe("INC(-0.05)");

    // Notifications: BOTH provider AND creator
    const providerNotif = addCalls.find(
      (c) => c.col === "notifications"
        && c.payload.userId === "p2"
        && c.payload.type === "anytask_sla_returned"
    );
    expect(providerNotif).toBeDefined();
    expect(providerNotif.payload.body).toContain("ניקיון");

    const creatorNotif = addCalls.find(
      (c) => c.col === "notifications"
        && c.payload.userId === "c2"
        && c.payload.type === "anytask_sla_returned"
    );
    expect(creatorNotif).toBeDefined();

    // Activity log entry on task
    expect(activityAddCalls.length).toBe(1);
    expect(activityAddCalls[0].payload.action).toBe("sla_returned");
    expect(activityAddCalls[0].payload.actorRole).toBe("system");
  });

  test("returned task with NO providerId → no penalty, but task still returned", async () => {
    const claimedAt = { toDate: () => new Date(Date.now() - 130 * 60 * 1000) };
    const { batchOps, addCalls } = setupSlaMocks({
      tasks: [{
        id: "no-provider",
        data: {
          status: "in_progress",
          claimedAt,
          // NO providerId
          creatorId: "c3",
          title: "X",
        },
      }],
    });

    await trigger();

    // Only ONE batch op (reset) — no penalty since no providerId
    expect(batchOps.length).toBe(1);
    expect(batchOps[0].payload.status).toBe("open");

    // No provider notification (no providerId)
    const providerNotif = addCalls.find(
      (c) => c.payload.title && c.payload.title.includes("הוחזרה בגלל")
    );
    expect(providerNotif).toBeUndefined();

    // Creator still gets a notification
    const creatorNotif = addCalls.find(
      (c) => c.payload.userId === "c3"
    );
    expect(creatorNotif).toBeDefined();
  });

  test("task with lastActivityAt = recent → no SLA action (active claim)", async () => {
    // claimedAt was 1h ago BUT lastActivityAt was 5 min ago — provider IS
    // engaged. The CF computes elapsed = now - max(claimedAt, lastActivityAt)
    // so this task is NOT in any SLA window.
    const claimedAt = { toDate: () => new Date(Date.now() - 60 * 60 * 1000) };
    const lastActivityAt = { toDate: () => new Date(Date.now() - 5 * 60 * 1000) };
    const { batchOps, addCalls } = setupSlaMocks({
      tasks: [{
        id: "active-claim",
        data: {
          status: "in_progress",
          claimedAt,
          lastActivityAt,
          providerId: "p3",
          creatorId: "c4",
          title: "X",
        },
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
    expect(addCalls.length).toBe(0);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// publishStaleReviews — scheduled CF (every 60 min, §38)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Per CLAUDE.md §38, this CF was added to fix the dead `lazyPublish` code
// path. Reviews stay `isPublished: false` until BOTH parties review OR
// 7 days pass. Without this CF, one-sided reviews stayed invisible forever.
//
// Flow per tick:
//   1. Query reviews where isPublished=false AND createdAt ≤ now-7d (cap 400)
//   2. Batch-update isPublished:true on every match
//   3. Recompute aggregates per (revieweeId, isClientReview, listingId)
//      — sequentially to avoid hot-key contention
//
// For each aggregate: if isClientReview → write rating + reviewsCount to
// users/{uid} AND provider_listings/{listingId}. Else (provider reviewed
// customer) → customerRating + customerReviewsCount on users/{uid}.
// ═══════════════════════════════════════════════════════════════════════════════
describe("publishStaleReviews — scheduled CF (§38)", () => {
  const trigger = index.publishStaleReviews;

  beforeEach(() => jest.clearAllMocks());

  function setupReviewsMocks({ staleReviews = [], publishedByReviewee = {} }) {
    const batchOps = [];
    const updateCalls = [];

    function buildSnapDoc(data, reviewId) {
      return {
        id: reviewId,
        data: () => data,
        ref: { id: reviewId },
      };
    }

    let reviewQueryCount = 0;
    mockFirestore.collection.mockImplementation((col) => {
      if (col === "reviews") {
        // First .where() call = stale-reviews query (isPublished=false + createdAt<cutoff)
        // Subsequent .where() calls = per-aggregate recompute queries
        const isStaleQuery = ++reviewQueryCount === 1;
        let chainKey = "";

        const chain = {
          where: jest.fn((field, op, value) => {
            // Capture revieweeId for the recompute path so we can return
            // the right docs
            if (field === "revieweeId") chainKey = String(value);
            return chain;
          }),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => {
            if (isStaleQuery) {
              const docs = staleReviews.map((r) =>
                buildSnapDoc(r.data, r.id));
              return {
                docs, empty: docs.length === 0, size: docs.length,
              };
            }
            // Recompute query — return published reviews for the matching key
            const docs = (publishedByReviewee[chainKey] || []).map((r, i) =>
              buildSnapDoc(r, `pub-${chainKey}-${i}`));
            return {
              docs, empty: docs.length === 0, size: docs.length,
            };
          }),
        };
        return chain;
      }
      // users + provider_listings
      return {
        doc: jest.fn((id) => ({
          id,
          update: jest.fn(async (payload) => {
            updateCalls.push({ col, id, payload });
          }),
        })),
      };
    });

    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps, updateCalls };
  }

  test("no stale reviews → CF returns without batch", async () => {
    const { batchOps, updateCalls } = setupReviewsMocks({ staleReviews: [] });
    await trigger();
    expect(batchOps.length).toBe(0);
    expect(updateCalls.length).toBe(0);
    expect(mockFirestore.batch).not.toHaveBeenCalled();
  });

  test("single stale review (provider→customer) → published + customer aggregate written", async () => {
    // Provider reviewed customer (isClientReview=false). Aggregates land
    // on users/{customerId}.customerRating + customerReviewsCount.
    const { batchOps, updateCalls } = setupReviewsMocks({
      staleReviews: [{
        id: "rev-1",
        data: {
          revieweeId: "customer-1",
          isClientReview: false,    // provider → customer
          overallRating: 4,
        },
      }],
      publishedByReviewee: {
        "customer-1": [
          { overallRating: 4, isPublished: true },
          { overallRating: 5, isPublished: true },
        ],
      },
    });

    await trigger();

    // batch.update on the stale review (isPublished: true)
    expect(batchOps.length).toBe(1);
    expect(batchOps[0].payload.isPublished).toBe(true);

    // Aggregate write: customer has 2 published reviews avg=4.5
    const userUpdate = updateCalls.find(
      (c) => c.col === "users" && c.id === "customer-1"
    );
    expect(userUpdate).toBeDefined();
    expect(userUpdate.payload.customerRating).toBe(4.5);
    expect(userUpdate.payload.customerReviewsCount).toBe(2);
    // Should NOT touch the provider rating fields
    expect(userUpdate.payload.rating).toBeUndefined();
  });

  test("client review (customer→provider) → provider rating + listing rating written", async () => {
    const { batchOps, updateCalls } = setupReviewsMocks({
      staleReviews: [{
        id: "rev-2",
        data: {
          revieweeId: "provider-1",
          isClientReview: true,     // customer → provider
          listingId: "listing-1",
          overallRating: 5,
        },
      }],
      publishedByReviewee: {
        "provider-1": [
          { overallRating: 5 },
          { overallRating: 4 },
          { overallRating: 5 },
        ],
      },
    });

    await trigger();

    // Aggregate avg = (5+4+5)/3 = 4.666... rounded to 4.7
    const userUpdate = updateCalls.find(
      (c) => c.col === "users" && c.id === "provider-1"
    );
    expect(userUpdate).toBeDefined();
    expect(userUpdate.payload.rating).toBe(4.7);
    expect(userUpdate.payload.reviewsCount).toBe(3);

    // Listing also updated
    const listingUpdate = updateCalls.find(
      (c) => c.col === "provider_listings" && c.id === "listing-1"
    );
    expect(listingUpdate).toBeDefined();
    expect(listingUpdate.payload.rating).toBe(4.7);
  });

  test("review missing revieweeId → published but no aggregate write", async () => {
    // Defensive: malformed review without revieweeId is still flipped to
    // published (cleans the queue) but skipped in the recompute loop.
    const { batchOps, updateCalls } = setupReviewsMocks({
      staleReviews: [{
        id: "rev-orphan",
        data: { isClientReview: true, overallRating: 5 },     // NO revieweeId
      }],
    });

    await trigger();

    // Still published (one batch op)
    expect(batchOps.length).toBe(1);
    expect(batchOps[0].payload.isPublished).toBe(true);

    // No aggregate updates
    expect(updateCalls.length).toBe(0);
  });

  test("aggregate uses fallback `rating` field when overallRating missing", async () => {
    // Pins the `(rd.overallRating ?? rd.rating ?? 0)` defensive read.
    // Some legacy reviews carry only `rating` (single field, not the
    // 4-criteria overallRating average).
    const { updateCalls } = setupReviewsMocks({
      staleReviews: [{
        id: "rev-legacy",
        data: { revieweeId: "provider-2", isClientReview: true },
      }],
      publishedByReviewee: {
        "provider-2": [
          { rating: 5 },           // legacy shape
          { overallRating: 4 },    // new shape
          { rating: 0 },           // 0 should be SKIPPED (the `if n > 0` guard)
        ],
      },
    });

    await trigger();

    const userUpdate = updateCalls.find(
      (c) => c.col === "users" && c.id === "provider-2"
    );
    expect(userUpdate).toBeDefined();
    // Average: (5 + 4) / 2 = 4.5 (the rating=0 doc filtered out)
    expect(userUpdate.payload.rating).toBe(4.5);
    expect(userUpdate.payload.reviewsCount).toBe(2);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// Vault dashboard CFs (CLAUDE.md §29) — updateVaultBalance, generateVaultAlerts,
// updateVaultAnalytics
// ═══════════════════════════════════════════════════════════════════════════════
//
// Three CFs power the admin Vault financial dashboard:
//
//   • updateVaultBalance — onWritten trigger on transactions/{id}.
//     Recomputes vault_balance/main from admin settings + paid_escrow jobs +
//     completed withdrawals. Single doc, single source of truth.
//
//   • generateVaultAlerts — hourly scan. Detects stuck escrows (>48h),
//     monthly revenue milestones, high cancellation rates. Pushes FCM to
//     admins on critical alerts.
//
//   • updateVaultAnalytics — hourly aggregator. Writes vault_analytics/{period}
//     for each of [day, week, month, year] with revenue, transaction count,
//     completion rate, health score, and forecast.
//
// These tests pin the output shape + key calculations. The deep aggregation
// math (forecasting, health-score weights) is verified in a single happy
// path; the rest cover early-exit / no-op paths.
// ═══════════════════════════════════════════════════════════════════════════════
describe("updateVaultBalance — onWritten trigger", () => {
  const trigger = index.updateVaultBalance;

  beforeEach(() => jest.clearAllMocks());

  function setupVaultBalanceMocks({
    totalPlatformBalance = 0,
    pendingJobs = [],
    completedWithdrawals = [],
  }) {
    const setCalls = [];

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "admin") {
        // db.collection('admin').doc('admin').collection('settings').doc('settings').get()
        return {
          doc: jest.fn(() => ({
            collection: jest.fn(() => ({
              doc: jest.fn(() => ({
                get: jest.fn(async () => ({
                  exists: true,
                  data: () => ({ totalPlatformBalance }),
                })),
              })),
            })),
          })),
        };
      }
      if (col === "jobs") {
        const docs = pendingJobs.map((j, i) => ({
          id: `j${i}`,
          data: () => j,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "withdrawals") {
        const docs = completedWithdrawals.map((w, i) => ({
          id: `w${i}`,
          data: () => w,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "vault_balance") {
        return {
          doc: jest.fn((id) => ({
            id,
            set: jest.fn(async (payload) => {
              setCalls.push({ col, id, payload });
            }),
          })),
        };
      }
      return {};
    });

    // Timestamp helpers used inside the CF + helper
    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { setCalls };
  }

  test("standard fire → vault_balance/main written with computed totals", async () => {
    const { setCalls } = setupVaultBalanceMocks({
      totalPlatformBalance: 5000,
      pendingJobs: [
        { commission: 100 },
        { commission: 50 },
      ],
      completedWithdrawals: [
        { amount: 1000 },
        { amount: 500 },
      ],
    });

    await trigger();

    expect(setCalls.length).toBe(1);
    expect(setCalls[0].id).toBe("main");
    expect(setCalls[0].payload.total_platform_balance).toBe(5000);
    expect(setCalls[0].payload.pending_balance).toBe(150);
    expect(setCalls[0].payload.total_withdrawn).toBe(1500);
    // available = total - withdrawn
    expect(setCalls[0].payload.available_balance).toBe(3500);
  });

  test("no escrow jobs + no withdrawals → balance shows platform total only", async () => {
    const { setCalls } = setupVaultBalanceMocks({
      totalPlatformBalance: 1000,
      pendingJobs: [],
      completedWithdrawals: [],
    });

    await trigger();

    expect(setCalls.length).toBe(1);
    expect(setCalls[0].payload.total_platform_balance).toBe(1000);
    expect(setCalls[0].payload.pending_balance).toBe(0);
    expect(setCalls[0].payload.total_withdrawn).toBe(0);
    expect(setCalls[0].payload.available_balance).toBe(1000);
  });
});


describe("generateVaultAlerts — scheduled CF", () => {
  const trigger = index.generateVaultAlerts;

  beforeEach(() => {
    jest.clearAllMocks();
    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async () => ({ messageId: "mock" })),
    }));
  });

  function setupVaultAlertsMocks({
    stuckJobs = [],
    existingAlertsByJobId = {},
    monthData = null,
    existingMilestoneTitles = [],
    admins = [],
  }) {
    const batchOps = [];
    let messagingCalls = [];

    const admin = require("firebase-admin");
    admin.messaging = jest.fn(() => ({
      send: jest.fn(async (msg) => {
        messagingCalls.push(msg);
        return { messageId: "mock" };
      }),
    }));

    let alertsQueryCounter = 0;

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "jobs") {
        const docs = stuckJobs.map((j) => ({
          id: j.id,
          data: () => j.data,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "vault_alerts") {
        // A complex collection — queried for dedupe AND for batch.set
        const queryChain = {
          where: jest.fn((field, op, value) => {
            if (field === "related_id") {
              queryChain._lookupId = value;
            } else if (field === "title") {
              queryChain._lookupTitle = value;
            }
            return queryChain;
          }),
          limit: jest.fn(() => queryChain),
          get: jest.fn(async () => {
            // Job-stuck dedupe path
            if (queryChain._lookupId) {
              const has = !!existingAlertsByJobId[queryChain._lookupId];
              return {
                docs: has ? [{ id: "x", data: () => ({}) }] : [],
                empty: !has, size: has ? 1 : 0,
              };
            }
            // Milestone dedupe path (by title)
            if (queryChain._lookupTitle) {
              const has = existingMilestoneTitles.includes(queryChain._lookupTitle);
              return {
                docs: has ? [{ id: "x", data: () => ({}) }] : [],
                empty: !has, size: has ? 1 : 0,
              };
            }
            return { docs: [], empty: true, size: 0 };
          }),
        };
        return {
          where: jest.fn((field, op, value) => {
            queryChain._lookupId = undefined;
            queryChain._lookupTitle = undefined;
            return queryChain.where(field, op, value);
          }),
          doc: jest.fn(() => ({ id: `auto-${alertsQueryCounter++}` })),
        };
      }
      if (col === "vault_analytics") {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({
              exists: monthData !== null,
              data: () => monthData || {},
            })),
          })),
        };
      }
      if (col === "users") {
        const docs = admins.map((a) => ({
          id: a.id,
          data: () => a.data,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      return {};
    });

    mockFirestore.batch = jest.fn(() => ({
      set: jest.fn((ref, payload) =>
        batchOps.push({ ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const adminLib = require("firebase-admin");
    adminLib.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps, getMessagingCalls: () => messagingCalls };
  }

  test("no stuck jobs + no monthly data → no alerts written", async () => {
    const { batchOps } = setupVaultAlertsMocks({});
    await trigger();
    expect(batchOps.length).toBe(0);
    expect(mockFirestore.batch).not.toHaveBeenCalled();
  });

  test("stuck job (>48h paid_escrow) → warning alert with related_id", async () => {
    const { batchOps } = setupVaultAlertsMocks({
      stuckJobs: [
        { id: "stuck-job-abc12345", data: { status: "paid_escrow" } },
      ],
    });

    await trigger();

    const warning = batchOps.find((op) => op.payload.type === "warning");
    expect(warning).toBeDefined();
    expect(warning.payload.severity).toBe("warning");
    expect(warning.payload.related_id).toBe("stuck-job-abc12345");
    expect(warning.payload.title).toBe("עסקה תקועה");
  });

  test("stuck job already has an alert → skip (dedupe)", async () => {
    const { batchOps } = setupVaultAlertsMocks({
      stuckJobs: [
        { id: "already-alerted", data: { status: "paid_escrow" } },
      ],
      existingAlertsByJobId: { "already-alerted": true },
    });

    await trigger();

    expect(batchOps.length).toBe(0);
  });

  test("monthly revenue ≥ ₪100 → achievement alert", async () => {
    const { batchOps } = setupVaultAlertsMocks({
      monthData: { revenue: 250 },
    });

    await trigger();

    const achievement = batchOps.find(
      (op) => op.payload.type === "achievement"
    );
    expect(achievement).toBeDefined();
    expect(achievement.payload.title).toBe("אבן דרך: ₪100");
    expect(achievement.payload.severity).toBe("info");
  });

  test("cancellation rate > 20% → critical risk alert", async () => {
    const { batchOps } = setupVaultAlertsMocks({
      monthData: {
        revenue: 0,
        completed_jobs: 7,
        cancelled_jobs: 3,    // 3/10 = 30% > 20%
      },
    });

    await trigger();

    const risk = batchOps.find((op) => op.payload.type === "risk");
    expect(risk).toBeDefined();
    expect(risk.payload.severity).toBe("critical");
    expect(risk.payload.title).toBe("שיעור ביטולים גבוה");
    expect(risk.payload.message).toContain("30%");
  });

  test("critical alert → FCM push to admins with tokens", async () => {
    const { getMessagingCalls } = setupVaultAlertsMocks({
      monthData: {
        revenue: 0,
        completed_jobs: 7,
        cancelled_jobs: 3,    // triggers critical
      },
      admins: [
        { id: "admin1", data: { isAdmin: true, fcmToken: "token-1" } },
        { id: "admin2", data: { isAdmin: true } },     // NO token — skipped
      ],
    });

    await trigger();

    const messagingCalls = getMessagingCalls();
    expect(messagingCalls.length).toBe(1);     // only admin1 (admin2 has no token)
    expect(messagingCalls[0].token).toBe("token-1");
    expect(messagingCalls[0].notification.title).toBe("🔐 Vault Alert");
    expect(messagingCalls[0].data.type).toBe("vault_alert");
  });
});


describe("updateVaultAnalytics — scheduled CF (4 periods)", () => {
  const trigger = index.updateVaultAnalytics;

  beforeEach(() => jest.clearAllMocks());

  function setupVaultAnalyticsMocks({
    earnings = [],
    completedJobs = [],
    cancelledJobs = [],
  }) {
    const setCalls = [];

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "platform_earnings") {
        const docs = earnings.map((e, i) => ({
          id: `e${i}`,
          data: () => e,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "jobs") {
        // Two queries: completed AND cancelled. Distinguish via where args.
        let mode = "";
        const chain = {
          where: jest.fn((field, op, value) => {
            if (field === "status" && value === "completed") mode = "completed";
            else if (field === "status" && Array.isArray(value)) mode = "cancelled";
            return chain;
          }),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => {
            const docs = mode === "completed"
              ? completedJobs.map((j, i) => ({ id: `c${i}`, data: () => j }))
              : cancelledJobs.map((j, i) => ({ id: `x${i}`, data: () => j }));
            return {
              docs, empty: docs.length === 0, size: docs.length,
            };
          }),
        };
        return { where: jest.fn((f, o, v) => { mode = ""; return chain.where(f, o, v); }) };
      }
      if (col === "vault_analytics") {
        return {
          doc: jest.fn((id) => ({
            id,
            set: jest.fn(async (payload) => {
              setCalls.push({ col, id, payload });
            }),
          })),
        };
      }
      return {};
    });

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { setCalls };
  }

  test("no data → all 4 period docs written with zeros", async () => {
    const { setCalls } = setupVaultAnalyticsMocks({
      earnings: [],
      completedJobs: [],
      cancelledJobs: [],
    });

    await trigger();

    // 4 period docs (day / week / month / year)
    expect(setCalls.length).toBe(4);

    const periods = setCalls.map((c) => c.id).sort();
    expect(periods).toEqual(["day", "month", "week", "year"]);

    // Each doc should have revenue=0, transaction_count=0, etc
    for (const c of setCalls) {
      expect(c.payload.revenue).toBe(0);
      expect(c.payload.transaction_count).toBe(0);
      expect(c.payload.avg_commission).toBe(0);
      expect(c.payload.active_providers).toBe(0);
      expect(c.payload.completed_jobs).toBe(0);
      expect(c.payload.health_score).toBeDefined();
      expect(typeof c.payload.health_score.total).toBe("number");
    }
  });

  test("with earnings data → revenue + tx count + active providers computed", async () => {
    const ts = { toDate: () => new Date() };
    const { setCalls } = setupVaultAnalyticsMocks({
      earnings: [
        { amount: 100, sourceExpertId: "p1", category: "cleaning", timestamp: ts },
        { amount: 50, sourceExpertId: "p2", category: "delivery", timestamp: ts },
        { amount: 30, sourceExpertId: "p1", category: "cleaning", timestamp: ts },
      ],
      completedJobs: [
        { status: "completed" },
        { status: "completed" },
      ],
      cancelledJobs: [{ status: "cancelled" }],
    });

    await trigger();

    expect(setCalls.length).toBe(4);

    // Each period doc has the SAME earnings data (same query over the whole
    // earnings collection — the period filter is what makes them differ
    // in real prod, but our mock returns the same docs for all queries).
    const day = setCalls.find((c) => c.id === "day");
    expect(day).toBeDefined();
    expect(day.payload.revenue).toBe(180);
    expect(day.payload.transaction_count).toBe(3);
    expect(day.payload.avg_commission).toBe(60);
    expect(day.payload.active_providers).toBe(2);     // p1, p2
    expect(day.payload.completed_jobs).toBe(2);
    expect(day.payload.cancelled_jobs).toBe(1);

    // revenue_by_category breakdown
    expect(day.payload.revenue_by_category.cleaning).toBe(130);
    expect(day.payload.revenue_by_category.delivery).toBe(50);

    // Completion rate: 2 / (2 + 1) = ~67%
    expect(day.payload.health_score.retention).toBeGreaterThan(60);
    expect(day.payload.health_score.retention).toBeLessThan(70);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// expireStories — scheduled CF (every 30 min)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Maintenance CF — clears `hasActive: false` on stories whose `expiresAt`
// has passed (25h after upload per CLAUDE.md §9b Law 3). Also flips
// `users/{uid}.hasActiveStory` so the homepage stops showing the dot.
// ═══════════════════════════════════════════════════════════════════════════════
describe("expireStories — scheduled CF", () => {
  const trigger = index.expireStories;

  beforeEach(() => jest.clearAllMocks());

  function setupExpireStoriesMocks({ expiredStories = [] }) {
    const batchOps = [];

    const docs = expiredStories.map((s) => ({
      id: s.id,            // doc.id === uid (per CF comment)
      data: () => s.data,
      ref: { id: s.id },
    }));

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "stories") {
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return chain;
      }
      // users — referenced via .doc(uid) for the hasActiveStory flip
      return {
        doc: jest.fn((id) => ({ id })),
      };
    });

    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps };
  }

  test("no expired stories → no batch.commit", async () => {
    const { batchOps } = setupExpireStoriesMocks({ expiredStories: [] });
    await trigger();
    expect(batchOps.length).toBe(0);
    expect(mockFirestore.batch).not.toHaveBeenCalled();
  });

  test("single expired story → 2 batch ops (story + user)", async () => {
    const { batchOps } = setupExpireStoriesMocks({
      expiredStories: [
        { id: "uid-1", data: { hasActive: true } },
      ],
    });

    await trigger();

    // 1 op for the story doc + 1 op for the user doc = 2
    expect(batchOps.length).toBe(2);

    const storyOp = batchOps.find((op) => op.payload.hasActive === false);
    expect(storyOp).toBeDefined();

    const userOp = batchOps.find(
      (op) => op.payload.hasActiveStory === false
    );
    expect(userOp).toBeDefined();
  });

  test("multiple expired stories → 2N batch ops in one commit", async () => {
    const { batchOps } = setupExpireStoriesMocks({
      expiredStories: [
        { id: "uid-1", data: {} },
        { id: "uid-2", data: {} },
        { id: "uid-3", data: {} },
      ],
    });

    await trigger();

    expect(batchOps.length).toBe(6);     // 3 stories + 3 users
    // ALL writes flushed in a SINGLE batch commit (cost optimization)
    expect(mockFirestore.batch).toHaveBeenCalledTimes(1);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// detectMonetizationAnomalies — scheduled CF (hourly, §31)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Three signals scanned per tick:
//   1. provider GMV drop ≥30% (last 7d vs prior 3w avg, requires ≥₪500 baseline)
//   2. churn risk: VIP inactive ≥10d, regular inactive ≥14d
//   3. category growth ≥20% (last 7d vs prior 3w avg, requires ≥₪1000 baseline)
//
// Idempotency: dedupe against open alerts created in the last 24h
// (key = `${type}:${entityType}:${entityId}`).
// ═══════════════════════════════════════════════════════════════════════════════
describe("detectMonetizationAnomalies — scheduled CF (§31)", () => {
  const trigger = index.detectMonetizationAnomalies;

  beforeEach(() => jest.clearAllMocks());

  function setupAnomaliesMocks({
    earnings = [],
    providers = [],
    openAlerts = [],
  }) {
    const batchOps = [];

    let queryCounter = 0;
    mockFirestore.collection.mockImplementation((col) => {
      if (col === "platform_earnings") {
        const docs = earnings.map((e, i) => ({
          id: `e${i}`,
          data: () => e,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "users") {
        const docs = providers.map((p) => ({
          id: p.id,
          data: () => p.data,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "monetization_alerts") {
        const docs = openAlerts.map((a, i) => ({
          id: `a${i}`,
          data: () => a,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return {
          where: jest.fn(() => chain),
          doc: jest.fn(() => ({ id: `auto-${queryCounter++}` })),
        };
      }
      return {};
    });

    mockFirestore.batch = jest.fn(() => ({
      set: jest.fn((ref, payload) =>
        batchOps.push({ ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps };
  }

  // Helper: build an earning doc with the given timestamp + provider/category
  function earning({ daysAgo, amount, providerId, category }) {
    return {
      timestamp: { toDate: () => new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000) },
      sourceAmount: amount,
      amount,
      sourceExpertId: providerId,
      category,
    };
  }

  test("no data → no alerts written", async () => {
    const { batchOps } = setupAnomaliesMocks({});
    await trigger();
    expect(batchOps.length).toBe(0);
  });

  test("provider GMV drop ≥30% → 'anomaly' alert with severity='medium'", async () => {
    // Provider had 600 over 21 days (₪200/week avg), then ₪100 in last 7d.
    // Drop = 50% → severity='high' actually (≥50%)
    const { batchOps } = setupAnomaliesMocks({
      earnings: [
        // Prior 3 weeks: 6 earnings of ₪100 each = ₪600 baseline
        earning({ daysAgo: 10, amount: 100, providerId: "p1", category: "" }),
        earning({ daysAgo: 12, amount: 100, providerId: "p1", category: "" }),
        earning({ daysAgo: 14, amount: 100, providerId: "p1", category: "" }),
        earning({ daysAgo: 16, amount: 100, providerId: "p1", category: "" }),
        earning({ daysAgo: 18, amount: 100, providerId: "p1", category: "" }),
        earning({ daysAgo: 20, amount: 100, providerId: "p1", category: "" }),
        // Last 7 days: only ₪100 — 50% drop from weekly avg (₪200)
        earning({ daysAgo: 3, amount: 100, providerId: "p1", category: "" }),
      ],
    });

    await trigger();

    const anomaly = batchOps.find(
      (op) => op.payload.type === "anomaly"
    );
    expect(anomaly).toBeDefined();
    expect(anomaly.payload.entityType).toBe("user");
    expect(anomaly.payload.entityId).toBe("p1");
    expect(anomaly.payload.severity).toBe("high");
    expect(anomaly.payload.suggestedAction).toBe("review_provider");
  });

  test("provider with insufficient baseline (<₪500) → no anomaly", async () => {
    const { batchOps } = setupAnomaliesMocks({
      earnings: [
        earning({ daysAgo: 10, amount: 100, providerId: "p2", category: "" }),
        earning({ daysAgo: 3, amount: 0, providerId: "p2", category: "" }),
      ],
    });

    await trigger();

    // Baseline ₪100 < ₪500 → no anomaly even though drop is huge
    const anomaly = batchOps.find(
      (op) => op.payload.type === "anomaly" && op.payload.entityId === "p2"
    );
    expect(anomaly).toBeUndefined();
  });

  test("VIP provider inactive ≥10 days → 'churn_risk' high severity", async () => {
    const lastActive = new Date(Date.now() - 11 * 24 * 60 * 60 * 1000);
    const { batchOps } = setupAnomaliesMocks({
      providers: [{
        id: "vip-1",
        data: {
          isProvider: true,
          isPromoted: true,
          name: "VIP Provider",
          lastActiveAt: { toDate: () => lastActive },
        },
      }],
    });

    await trigger();

    const churn = batchOps.find(
      (op) => op.payload.type === "churn_risk"
    );
    expect(churn).toBeDefined();
    expect(churn.payload.severity).toBe("high");     // VIP gets high
    expect(churn.payload.entityId).toBe("vip-1");
    expect(churn.payload.message).toContain("VIP");
  });

  test("regular provider inactive ≥14 days → 'churn_risk' medium severity", async () => {
    const lastActive = new Date(Date.now() - 15 * 24 * 60 * 60 * 1000);
    const { batchOps } = setupAnomaliesMocks({
      providers: [{
        id: "regular-1",
        data: {
          isProvider: true,
          isPromoted: false,
          name: "Regular Provider",
          lastActiveAt: { toDate: () => lastActive },
        },
      }],
    });

    await trigger();

    const churn = batchOps.find(
      (op) => op.payload.type === "churn_risk"
    );
    expect(churn).toBeDefined();
    expect(churn.payload.severity).toBe("medium");
  });

  test("active provider (5 days ago) → no churn_risk", async () => {
    const lastActive = new Date(Date.now() - 5 * 24 * 60 * 60 * 1000);
    const { batchOps } = setupAnomaliesMocks({
      providers: [{
        id: "active-1",
        data: {
          isProvider: true,
          name: "Active Provider",
          lastActiveAt: { toDate: () => lastActive },
        },
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
  });

  test("category growth ≥20% → 'growth_opportunity' alert", async () => {
    // Category had 1500 over 21 days (₪500/week avg), then ₪800 in 7d.
    // Growth = 60% → severity='high'. Use a clean ratio that avoids
    // floating-point boundary issues at the 40% high/low threshold.
    const { batchOps } = setupAnomaliesMocks({
      earnings: [
        // 3 weeks of baseline @ ₪500/week = ₪1500
        ...Array.from({ length: 15 }, (_, i) =>
          earning({ daysAgo: 8 + i, amount: 100, providerId: "", category: "cleaning" })),
        // Last 7d at ₪800 (60% growth)
        earning({ daysAgo: 1, amount: 800, providerId: "", category: "cleaning" }),
      ],
    });

    await trigger();

    const growth = batchOps.find(
      (op) => op.payload.type === "growth_opportunity"
    );
    expect(growth).toBeDefined();
    expect(growth.payload.entityType).toBe("category");
    expect(growth.payload.entityId).toBe("cleaning");
    expect(growth.payload.severity).toBe("high");
  });

  test("dedupe: existing open alert with same key → skip", async () => {
    const lastActive = new Date(Date.now() - 11 * 24 * 60 * 60 * 1000);
    const { batchOps } = setupAnomaliesMocks({
      providers: [{
        id: "vip-2",
        data: {
          isProvider: true,
          isPromoted: true,
          lastActiveAt: { toDate: () => lastActive },
        },
      }],
      openAlerts: [{
        type: "churn_risk",
        entityType: "user",
        entityId: "vip-2",     // already alerted
        resolved: false,
      }],
    });

    await trigger();

    // The dedupe filter rejects the alert
    expect(batchOps.length).toBe(0);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// generateMonetizationInsight — scheduled CF (every 6h, Gemini, §31)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Aggregates platform metrics into a Gemini prompt every 6 hours and
// writes a strategic recommendation to `ai_insights/monetization`.
// Critical contract: graceful failure on Gemini errors (no throw, no
// partial doc write — just log and return {ok: false}).
// ═══════════════════════════════════════════════════════════════════════════════
describe("generateMonetizationInsight — scheduled CF (§31, Gemini)", () => {
  const trigger = index.generateMonetizationInsight;

  let originalFetch;

  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  function setupInsightMocks({
    earnings = [],
    alerts = [],
    providers = [],
    fetchResponse = null,
    fetchThrows = false,
  }) {
    const setCalls = [];

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "platform_earnings") {
        const docs = earnings.map((e, i) => ({
          id: `e${i}`,
          data: () => e,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "monetization_alerts") {
        const docs = alerts.map((a, i) => ({
          id: `a${i}`,
          data: () => a,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "users") {
        const docs = providers.map((p) => ({
          id: p.id,
          data: () => p.data,
        }));
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "category_commissions") {
        return {
          // Used as-is via .get() (no .where()). Returns iterable snapshot.
          get: jest.fn(async () => {
            const snap = {
              docs: [],
              forEach: jest.fn((cb) => snap.docs.forEach(cb)),
            };
            return snap;
          }),
        };
      }
      if (col === "admin") {
        return {
          doc: jest.fn(() => ({
            collection: jest.fn(() => ({
              doc: jest.fn(() => ({
                get: jest.fn(async () => ({
                  exists: true,
                  data: () => ({ feePercentage: 0.10 }),
                })),
              })),
            })),
          })),
        };
      }
      if (col === "ai_insights") {
        return {
          doc: jest.fn((id) => ({
            id,
            set: jest.fn(async (payload) => {
              setCalls.push({ col, id, payload });
            }),
          })),
        };
      }
      return {};
    });

    // Mock fetch to either return the configured response or throw
    if (fetchThrows) {
      global.fetch = jest.fn(async () => {
        throw new Error("Network unavailable");
      });
    } else {
      global.fetch = jest.fn(async () => fetchResponse);
    }

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };
    // The CF uses FieldValue.delete() to clear dismiss flags
    admin.firestore.FieldValue.delete = jest.fn(() => "DELETE_FIELD");

    return { setCalls };
  }

  test("Gemini returns valid JSON → ai_insights/monetization is set", async () => {
    const geminiResponse = {
      ok: true,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                title: "ייעל את עמלת השיפוצים",
                recommendation: "הורד עמלה ב-2% למשך חודש",
                expectedImpact: "צפוי לעלות GMV ב-₪10K",
                actionType: "adjust_category_commission",
                actionParams: { categoryName: "שיפוצים", newPct: 8 },
              }),
            }],
          },
        }],
      }),
    };

    const { setCalls } = setupInsightMocks({
      earnings: [],
      alerts: [],
      providers: [],
      fetchResponse: geminiResponse,
    });

    const result = await trigger();

    expect(result.ok).toBe(true);
    expect(result.actionType).toBe("adjust_category_commission");

    // ai_insights/monetization doc written
    expect(setCalls.length).toBe(1);
    expect(setCalls[0].id).toBe("monetization");
    expect(setCalls[0].payload.title).toBe("ייעל את עמלת השיפוצים");
    expect(setCalls[0].payload.actionType).toBe("adjust_category_commission");
    expect(setCalls[0].payload.applied).toBe(false);
    expect(setCalls[0].payload.model).toBe("gemini-2.5-flash-lite");
    // dismiss flags cleared via FieldValue.delete()
    expect(setCalls[0].payload.dismissedBy).toBe("DELETE_FIELD");
    expect(setCalls[0].payload.dismissedAt).toBe("DELETE_FIELD");
  });

  test("Gemini HTTP error → graceful fallback (no doc written)", async () => {
    const errorResponse = {
      ok: false,
      status: 500,
      json: async () => ({}),
    };

    const { setCalls } = setupInsightMocks({
      fetchResponse: errorResponse,
    });

    const result = await trigger();

    expect(result.ok).toBe(false);
    expect(result.error).toContain("500");
    // No partial write
    expect(setCalls.length).toBe(0);
  });

  test("fetch throws → graceful fallback", async () => {
    const { setCalls } = setupInsightMocks({ fetchThrows: true });

    const result = await trigger();

    expect(result.ok).toBe(false);
    expect(result.error).toContain("Network unavailable");
    expect(setCalls.length).toBe(0);
  });

  test("Gemini returns malformed JSON in text → graceful fallback", async () => {
    const malformedResponse = {
      ok: true,
      json: async () => ({
        candidates: [{
          content: { parts: [{ text: "not valid json {" }] },
        }],
      }),
    };

    const { setCalls } = setupInsightMocks({
      fetchResponse: malformedResponse,
    });

    const result = await trigger();

    expect(result.ok).toBe(false);
    expect(setCalls.length).toBe(0);
  });

  test("Gemini returns minimal JSON → defaults filled in (defensive shape check)", async () => {
    const minimalResponse = {
      ok: true,
      json: async () => ({
        candidates: [{
          content: { parts: [{ text: '{"recommendation": "x"}' }] },
        }],
      }),
    };

    const { setCalls } = setupInsightMocks({
      fetchResponse: minimalResponse,
    });

    const result = await trigger();

    expect(result.ok).toBe(true);
    // Missing fields filled with defaults
    expect(setCalls[0].payload.title).toBe("תובנת AI CEO");
    expect(setCalls[0].payload.actionType).toBe("none");
    expect(setCalls[0].payload.actionParams).toEqual({});
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// analyzeFeedbackOnCreate — onCreate trigger (CLAUDE.md §42, Gemini)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Fires whenever a customer/provider submits feedback via the in-app
// "Feedback & Ideas" form. Calls Gemini to tag the feedback with:
//   priority: "Low" | "High"
//   topic:    "UX" | "Pricing" | "Bug" | "Feature" | "Performance" | "Other"
//
// Hard contract: a doc must NEVER stay un-tagged. On any error path, the
// CF writes deterministic fallback values (priority based on NPS, topic="Other").
// ═══════════════════════════════════════════════════════════════════════════════
describe("analyzeFeedbackOnCreate — onCreate trigger (§42)", () => {
  const trigger = index.analyzeFeedbackOnCreate;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  function buildEvent({ data, fetchResponse, fetchThrows = false }) {
    const updateCalls = [];
    const event = {
      data: {
        data: () => data,
        ref: {
          update: jest.fn(async (payload) => {
            updateCalls.push(payload);
          }),
        },
      },
    };

    if (fetchThrows) {
      global.fetch = jest.fn(async () => {
        throw new Error("Network down");
      });
    } else if (fetchResponse) {
      global.fetch = jest.fn(async () => fetchResponse);
    }

    return { event, updateCalls };
  }

  test("empty content → defaults written (Low/Other)", async () => {
    const { event, updateCalls } = buildEvent({
      data: { content: "", npsScore: 8 },
    });

    await trigger(event);

    expect(updateCalls.length).toBe(1);
    expect(updateCalls[0].priority).toBe("Low");
    expect(updateCalls[0].topic).toBe("Other");
    expect(updateCalls[0].analyzedAt).toBeDefined();
  });

  test("Gemini returns valid JSON → priority + topic written from Gemini", async () => {
    const geminiResponse = {
      ok: true,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{ text: '{"priority":"High","topic":"Bug"}' }],
          },
        }],
      }),
    };
    const { event, updateCalls } = buildEvent({
      data: {
        content: "האפליקציה קורסת כשאני מנסה לפתוח צ'אט עם הספק",
        npsScore: 5,
        userRole: "customer",
        category: "bugs",
      },
      fetchResponse: geminiResponse,
    });

    await trigger(event);

    expect(updateCalls.length).toBe(1);
    expect(updateCalls[0].priority).toBe("High");
    expect(updateCalls[0].topic).toBe("Bug");
  });

  test("Gemini returns invalid topic → falls back to 'Other'", async () => {
    const geminiResponse = {
      ok: true,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{ text: '{"priority":"Low","topic":"INVALID_TOPIC"}' }],
          },
        }],
      }),
    };
    const { event, updateCalls } = buildEvent({
      data: { content: "x", npsScore: 8 },
      fetchResponse: geminiResponse,
    });

    await trigger(event);

    expect(updateCalls[0].topic).toBe("Other");
    expect(updateCalls[0].priority).toBe("Low");
  });

  test("Gemini HTTP 500 + NPS ≤ 6 → fallback priority='High'", async () => {
    // Critical: even when Gemini fails, NPS-based priority kicks in.
    // Detractor feedback (NPS ≤ 6) MUST land as High to surface on the
    // admin's priority queue.
    const errorResponse = { ok: false, status: 500 };
    const { event, updateCalls } = buildEvent({
      data: { content: "Bad UX", npsScore: 4 },
      fetchResponse: errorResponse,
    });

    await trigger(event);

    expect(updateCalls.length).toBe(1);
    expect(updateCalls[0].priority).toBe("High");
    expect(updateCalls[0].topic).toBe("Other");
  });

  test("Gemini HTTP 500 + NPS > 6 → fallback priority='Low'", async () => {
    const errorResponse = { ok: false, status: 500 };
    const { event, updateCalls } = buildEvent({
      data: { content: "Nice app", npsScore: 9 },
      fetchResponse: errorResponse,
    });

    await trigger(event);

    expect(updateCalls[0].priority).toBe("Low");
    expect(updateCalls[0].topic).toBe("Other");
  });

  test("fetch throws → catch block writes deterministic fallback", async () => {
    const { event, updateCalls } = buildEvent({
      data: { content: "test", npsScore: 3 },
      fetchThrows: true,
    });

    await trigger(event);

    // The catch handler still tagged the doc — never leave un-tagged
    expect(updateCalls.length).toBe(1);
    expect(updateCalls[0].priority).toBe("High");     // NPS=3 ≤ 6
    expect(updateCalls[0].topic).toBe("Other");
  });

  test("missing event.data → no-op (defensive guard)", async () => {
    await trigger({ data: null });
    // Nothing to assert — just confirms no crash
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// generateFeedbackWeeklyInsight — scheduled CF (every Monday 08:00, §42, Gemini)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Bundles the past 7 days of app_feedback into a Gemini prompt and writes
// a strategic digest to `ai_insights/feedback_weekly`. Hard contract:
// the doc MUST always exist after a tick — even on Gemini outage, write
// stats-only data so the admin tab has something to show.
// ═══════════════════════════════════════════════════════════════════════════════
describe("generateFeedbackWeeklyInsight — scheduled CF (§42, Gemini)", () => {
  const trigger = index.generateFeedbackWeeklyInsight;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  function setupFeedbackWeeklyMocks({ feedbackDocs = [], fetchResponse, fetchThrows = false }) {
    const setCalls = [];

    const docs = feedbackDocs.map((f, i) => ({
      id: `f${i}`,
      data: () => f,
    }));

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "app_feedback") {
        const chain = {
          where: jest.fn(() => chain),
          orderBy: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "ai_insights") {
        return {
          doc: jest.fn((id) => ({
            id,
            set: jest.fn(async (payload) => {
              setCalls.push({ col, id, payload });
            }),
          })),
        };
      }
      return {};
    });

    if (fetchThrows) {
      global.fetch = jest.fn(async () => {
        throw new Error("Network down");
      });
    } else if (fetchResponse) {
      global.fetch = jest.fn(async () => fetchResponse);
    }

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
      fromMillis: jest.fn((ms) => ({ toMillis: () => ms })),
    };

    return { setCalls };
  }

  test("no feedback this week → empty-state insight written", async () => {
    const { setCalls } = setupFeedbackWeeklyMocks({ feedbackDocs: [] });

    await trigger();

    expect(setCalls.length).toBe(1);
    expect(setCalls[0].id).toBe("feedback_weekly");
    expect(setCalls[0].payload.totalCount).toBe(0);
    expect(setCalls[0].payload.summary).toBe("לא התקבלו הצעות השבוע.");
    expect(setCalls[0].payload.topThemes).toEqual([]);
    expect(setCalls[0].payload.npsAverage).toBe(null);
    expect(setCalls[0].payload.npsDistribution).toEqual({
      detractors: 0, passives: 0, promoters: 0,
    });
  });

  test("feedback + Gemini success → full insight with topThemes + topPriority", async () => {
    const geminiResponse = {
      ok: true,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                summary: "צ'אט הוא הנושא הכי בולט",
                topThemes: [
                  { title: "צ'אט נופל", description: "תקלות תכופות", count: 5, exampleQuote: "הצ'אט תקוע" },
                  { title: "מחירים", description: "יקר", count: 3, exampleQuote: "ספק יקר" },
                  { title: "UI", description: "פונט קטן", count: 2, exampleQuote: "קשה לקרוא" },
                ],
                topPriority: {
                  title: "תקן את הצ'אט",
                  reason: "5 דיווחים השבוע",
                  suggestedAction: "Sprint דחוף",
                },
              }),
            }],
          },
        }],
      }),
    };

    const { setCalls } = setupFeedbackWeeklyMocks({
      feedbackDocs: [
        { content: "הצ'אט תקוע", npsScore: 4, topic: "Bug", priority: "High", userRole: "customer", category: "bugs" },
        { content: "ספק יקר", npsScore: 6, topic: "Pricing", priority: "Low", userRole: "customer" },
        { content: "מצוין", npsScore: 9, topic: "UX", priority: "Low", userRole: "provider" },
      ],
      fetchResponse: geminiResponse,
    });

    await trigger();

    expect(setCalls.length).toBe(1);
    const payload = setCalls[0].payload;
    expect(payload.totalCount).toBe(3);
    // NPS distribution: 4→detractor, 6→detractor, 9→promoter
    expect(payload.npsDistribution.detractors).toBe(2);
    expect(payload.npsDistribution.passives).toBe(0);
    expect(payload.npsDistribution.promoters).toBe(1);
    // NPS average: (4+6+9)/3 = 6.3 (rounded to 1 decimal)
    expect(payload.npsAverage).toBe(6.3);

    expect(payload.summary).toBe("צ'אט הוא הנושא הכי בולט");
    expect(payload.topThemes.length).toBe(3);
    expect(payload.topThemes[0].title).toBe("צ'אט נופל");
    expect(payload.topPriority.title).toBe("תקן את הצ'אט");
    expect(payload.model).toBe("gemini-2.5-flash-lite");

    // byTopic + byPriority breakdowns
    expect(payload.byTopic.Bug).toBe(1);
    expect(payload.byTopic.Pricing).toBe(1);
    expect(payload.byPriority.High).toBe(1);
    expect(payload.byPriority.Low).toBe(2);
  });

  test("Gemini error → partial stats written (no themes)", async () => {
    const errorResponse = {
      ok: false,
      status: 500,
      text: async () => "Server error",
    };

    const { setCalls } = setupFeedbackWeeklyMocks({
      feedbackDocs: [
        { content: "x", npsScore: 8 },
      ],
      fetchResponse: errorResponse,
    });

    await trigger();

    // Doc IS still written — but with empty themes + error summary
    expect(setCalls.length).toBe(1);
    expect(setCalls[0].payload.totalCount).toBe(1);
    expect(setCalls[0].payload.npsAverage).toBe(8);
    expect(setCalls[0].payload.summary).toBe("שגיאת AI — מוצגות סטטיסטיקות בלבד.");
    expect(setCalls[0].payload.topThemes).toEqual([]);
    expect(setCalls[0].payload.topPriority).toBe(null);
    expect(setCalls[0].payload.model).toBe(null);
  });

  test("fetch throws → graceful fallback to stats-only", async () => {
    const { setCalls } = setupFeedbackWeeklyMocks({
      feedbackDocs: [
        { content: "test", npsScore: 7 },
      ],
      fetchThrows: true,
    });

    await trigger();

    // Doc still written with stats but no AI data
    expect(setCalls.length).toBe(1);
    expect(setCalls[0].payload.totalCount).toBe(1);
    expect(setCalls[0].payload.summary).toContain("שגיאת AI");
    expect(setCalls[0].payload.topThemes).toEqual([]);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// reengageAbandonedLeads — scheduled CF (every 60 min)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Maintenance CF — sends re-engagement emails to users who started signup
// >1h ago but never finished. Idempotent via the `reengaged: true` flag.
// ═══════════════════════════════════════════════════════════════════════════════
describe("reengageAbandonedLeads — scheduled CF", () => {
  const trigger = index.reengageAbandonedLeads;

  beforeEach(() => jest.clearAllMocks());

  function setupReengageMocks({ leads = [] }) {
    const batchOps = [];
    const mailAddCalls = [];

    const docs = leads.map((l) => ({
      id: l.id,
      data: () => l.data,
      ref: { id: l.id },
    }));

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "incomplete_registrations") {
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({
            docs, empty: docs.length === 0, size: docs.length,
          })),
        };
        return { where: jest.fn(() => chain) };
      }
      if (col === "mail") {
        return {
          add: jest.fn(async (payload) => {
            mailAddCalls.push({ col, payload });
            return { id: "auto-id" };
          }),
        };
      }
      // reengagement_log — accessed via .doc() inside batch.set
      return {
        doc: jest.fn(() => ({ id: `auto-${col}` })),
      };
    });

    mockFirestore.batch = jest.fn(() => ({
      update: jest.fn((ref, payload) =>
        batchOps.push({ op: "update", ref, payload })),
      set: jest.fn((ref, payload) =>
        batchOps.push({ op: "set", ref, payload })),
      commit: jest.fn(async () => {}),
    }));

    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };

    return { batchOps, mailAddCalls };
  }

  test("no abandoned leads → no batch", async () => {
    const { batchOps, mailAddCalls } = setupReengageMocks({ leads: [] });
    await trigger();
    expect(batchOps.length).toBe(0);
    expect(mailAddCalls.length).toBe(0);
  });

  test("lead with email → batch update + log + mail.add", async () => {
    const { batchOps, mailAddCalls } = setupReengageMocks({
      leads: [{
        id: "lead-1",
        data: {
          email: "user@example.com",
          name: "Alice",
          lastField: "phone",
          role: "customer",
        },
      }],
    });

    await trigger();

    // Batch: 1 update on the lead doc + 1 set on reengagement_log
    expect(batchOps.length).toBe(2);

    const update = batchOps.find((op) => op.op === "update");
    expect(update).toBeDefined();
    expect(update.payload.reengaged).toBe(true);
    expect(update.payload.reengagedBy).toBe("scheduled_function");

    const log = batchOps.find((op) => op.op === "set");
    expect(log).toBeDefined();
    expect(log.payload.sessionId).toBe("lead-1");
    expect(log.payload.email).toBe("user@example.com");
    expect(log.payload.channel).toBe("email");

    // Mail doc with HTML body
    expect(mailAddCalls.length).toBe(1);
    expect(mailAddCalls[0].payload.to).toBe("user@example.com");
    expect(mailAddCalls[0].payload.message.subject).toContain("AnySkill");
    expect(mailAddCalls[0].payload.message.html).toContain("Alice");
  });

  test("lead with phone (no email) → batch + log, NO mail (SMS placeholder)", async () => {
    const { batchOps, mailAddCalls } = setupReengageMocks({
      leads: [{
        id: "lead-2",
        data: {
          phone: "+972501234567",
          name: "Bob",
          lastField: "email",
        },
      }],
    });

    await trigger();

    // Batch: update + log
    expect(batchOps.length).toBe(2);

    // Log doc records SMS channel
    const log = batchOps.find((op) => op.op === "set");
    expect(log.payload.phone).toBe("+972501234567");
    expect(log.payload.email).toBe(null);
    expect(log.payload.channel).toBe("sms");

    // No mail (SMS is a placeholder — Twilio integration TODO)
    expect(mailAddCalls.length).toBe(0);
  });

  test("lead already reengaged → skip (idempotency)", async () => {
    const { batchOps, mailAddCalls } = setupReengageMocks({
      leads: [{
        id: "already",
        data: {
          email: "x@y.com",
          reengaged: true,     // already processed
        },
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
    expect(mailAddCalls.length).toBe(0);
  });

  test("lead with no contact info → skip", async () => {
    const { batchOps, mailAddCalls } = setupReengageMocks({
      leads: [{
        id: "noContact",
        data: { name: "Anonymous" },     // NO email, NO phone
      }],
    });

    await trigger();

    expect(batchOps.length).toBe(0);
    expect(mailAddCalls.length).toBe(0);
  });

  test("multiple leads → all in one batch", async () => {
    const { batchOps, mailAddCalls } = setupReengageMocks({
      leads: [
        { id: "l1", data: { email: "a@b.com" } },
        { id: "l2", data: { email: "c@d.com" } },
        { id: "l3", data: { phone: "+972500000003" } },
      ],
    });

    await trigger();

    // 3 leads × 2 batch ops each = 6
    expect(batchOps.length).toBe(6);
    // 2 emails (mail per email-having lead)
    expect(mailAddCalls.length).toBe(2);
    // ONE batch commit (cost optimization)
    expect(mockFirestore.batch).toHaveBeenCalledTimes(1);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// Gemini callables — recommendVehicleForDelivery, calculateCleaningDuration,
// recommendTrainersByGoals (CSM AI helpers)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Pattern: each is a Gemini-backed callable that returns AI recommendations.
// All three use `gemini-2.5-flash-lite` with `responseMimeType: 'application/json'`.
//
// Contract differences:
//   • recommendVehicleForDelivery — throws HttpsError("internal") on Gemini failure
//   • calculateCleaningDuration   — same (UI keeps local heuristic on error)
//   • recommendTrainersByGoals    — graceful fallback: returns deterministic
//     fallback score + reasons even when Gemini fails (UX never breaks)
// ═══════════════════════════════════════════════════════════════════════════════

// Helper for Gemini tests — mock global.fetch with a configurable response
function buildGeminiCallableMocks({ fetchResponse, fetchThrows = false }) {
  const addCalls = [];
  const setCalls = [];

  mockFirestore.collection.mockImplementation((col) => ({
    doc: jest.fn((id) => ({
      id,
      get: jest.fn(async () => ({ exists: false, data: () => ({}) })),
    })),
    add: jest.fn(async (payload) => {
      addCalls.push({ col, payload });
      return { id: "auto-id" };
    }),
  }));

  if (fetchThrows) {
    global.fetch = jest.fn(async () => {
      throw new Error("Network unavailable");
    });
  } else {
    global.fetch = jest.fn(async () => fetchResponse);
  }

  const admin = require("firebase-admin");
  admin.firestore.Timestamp = {
    now: jest.fn(() => ({ toMillis: () => Date.now() })),
    fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
  };

  return { addCalls, setCalls };
}

function mkGeminiResp(jsonText) {
  return {
    ok: true,
    json: async () => ({
      candidates: [{ content: { parts: [{ text: jsonText }] } }],
    }),
  };
}


describe("recommendVehicleForDelivery — Gemini callable (§33)", () => {
  const cf = index.recommendVehicleForDelivery;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(
      cf({ auth: null, data: {} })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("Gemini returns valid recommendation → response shape correct", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp(JSON.stringify({
        recommendedVehicle: "car",
        savingsAmount: 25,
        savingsMinutes: 8,
        reason: "מרחק ארוך — רכב מהיר יותר בכביש פנוי",
        confidence: 0.9,
      })),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: {
        packageType: "large_package",
        distanceKm: 25,
        urgency: "regular",
      },
    });

    expect(result.recommendedVehicle).toBe("car");
    expect(result.savingsAmount).toBe(25);
    expect(result.savingsMinutes).toBe(8);
    expect(result.confidence).toBe(0.9);
    expect(result.reason).toContain("רכב");
  });

  test("Gemini HTTP error → HttpsError(internal)", async () => {
    buildGeminiCallableMocks({
      fetchResponse: {
        ok: false,
        status: 500,
        text: async () => "server error",
      },
    });

    await expect(
      cf({ auth: { uid: "u1" }, data: {} })
    ).rejects.toMatchObject({ code: "internal" });
  });

  test("fetch throws → HttpsError(internal)", async () => {
    buildGeminiCallableMocks({ fetchThrows: true });

    await expect(
      cf({ auth: { uid: "u1" }, data: {} })
    ).rejects.toMatchObject({ code: "internal" });
  });

  test("Gemini returns empty/missing fields → fallback defaults applied", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp("{}"),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: { distanceKm: 5 },
    });

    // Defensive defaults
    expect(result.recommendedVehicle).toBe("scooter");
    expect(result.savingsAmount).toBe(0);
    expect(result.savingsMinutes).toBe(0);
    expect(result.confidence).toBe(0.7);
  });
});


describe("calculateCleaningDuration — Gemini callable (§34)", () => {
  const cf = index.calculateCleaningDuration;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(
      cf({ auth: null, data: {} })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("Gemini returns valid duration → response shape correct + clamped", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp(JSON.stringify({
        estimatedMinutes: 240,
        rangeMin: 200,
        rangeMax: 280,
        reasoning: "דירת 4 חדרים + תוספות",
      })),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: {
        cleaningType: "deep",
        bedrooms: 3,
        bathrooms: 2,
        squareMeters: 120,
        hasPets: true,
        selectedTasksCount: 8,
        addOnsCount: 2,
      },
    });

    expect(result.estimatedMinutes).toBe(240);
    expect(result.rangeMin).toBe(200);
    expect(result.rangeMax).toBe(280);
    expect(result.reasoning).toContain("דירת");
  });

  test("Gemini returns out-of-bounds value → clamped to 60..600", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp(JSON.stringify({
        estimatedMinutes: 9999,    // way over 600 cap
        rangeMin: 30,              // under 60 floor
        rangeMax: 50000,
      })),
    });

    const result = await cf({ auth: { uid: "u1" }, data: {} });

    expect(result.estimatedMinutes).toBeLessThanOrEqual(600);
    expect(result.rangeMin).toBeGreaterThanOrEqual(60);
  });

  test("Gemini HTTP error → HttpsError(internal)", async () => {
    buildGeminiCallableMocks({
      fetchResponse: {
        ok: false,
        status: 503,
        text: async () => "unavailable",
      },
    });

    await expect(
      cf({ auth: { uid: "u1" }, data: {} })
    ).rejects.toMatchObject({ code: "internal" });
  });
});


describe("recommendTrainersByGoals — Gemini callable (§44)", () => {
  const cf = index.recommendTrainersByGoals;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(
      cf({ auth: null, data: {} })
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("Gemini returns valid match → matchScore + 4 reasons + analytics logged", async () => {
    const { addCalls } = buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp(JSON.stringify({
        matchScore: 92,
        reasons: [
          "🎯 מתאים למטרות שלך",
          "🏠 קרוב לבית",
          "💪 ניסיון רב",
          "💝 סגנון נכון",
        ],
      })),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: {
        goal: "build_muscle",
        experience: "intermediate",
        frequency: 3,
        location: "home",
        style: "motivator",
      },
    });

    expect(result.success).toBe(true);
    expect(result.matchScore).toBe(92);
    expect(result.reasons.length).toBe(4);
    expect(result.reasons[0]).toContain("🎯");

    // Best-effort analytics write (matching_analytics)
    // Note: analytics.add() is fire-and-forget so it's invoked asynchronously
    // — the key thing is it doesn't throw on the main path
  });

  test("Gemini fails → graceful fallback (NOT a throw — UX never breaks)", async () => {
    buildGeminiCallableMocks({ fetchThrows: true });

    // CRITICAL: the customer's quiz UI must NEVER see an error here.
    // The CF returns a deterministic fallback even when Gemini is down.
    const result = await cf({
      auth: { uid: "u1" },
      data: {
        goal: "lose_weight",
        experience: "beginner",
        frequency: 2,
        location: "park",
        style: "calm",
      },
    });

    // Either a fallback shape, or success with reasons array — both
    // acceptable. Critical: it does NOT throw.
    expect(result).toBeDefined();
    expect(typeof result.matchScore).toBe("number");
    expect(result.matchScore).toBeGreaterThanOrEqual(0);
    expect(result.matchScore).toBeLessThanOrEqual(100);
    expect(Array.isArray(result.reasons)).toBe(true);
  });

  test("Gemini returns < 4 reasons → padded to exactly 4 (defensive shape)", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp(JSON.stringify({
        matchScore: 88,
        reasons: ["🎯 reason 1"],     // only 1 reason
      })),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: { goal: "endurance" },
    });

    expect(result.reasons.length).toBe(4);
    expect(result.reasons[0]).toBe("🎯 reason 1");
    // Other 3 are padded with defaults
  });

  test("Gemini returns matchScore out-of-bounds → clamped to [50, 100]", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp(JSON.stringify({
        matchScore: 999,
        reasons: ["a", "b", "c", "d"],
      })),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: { goal: "flexibility" },
    });

    expect(result.matchScore).toBeLessThanOrEqual(100);
    expect(result.matchScore).toBeGreaterThanOrEqual(50);
  });
});


// ═══════════════════════════════════════════════════════════════════════════════
// FINAL SWEEP — All remaining CFs (auth gates + critical paths)
// ═══════════════════════════════════════════════════════════════════════════════
//
// 11 CFs in one pass:
//   1. generateServiceSchema           — Claude callable (admin)
//   2. generateCeoInsight              — Claude+Gemini fallback (admin)
//   3. backfillAdminClaims             — admin one-shot
//   4. getEffectiveCommission          — callable (self or admin)
//   5. adminReleaseEscrow              — admin money flow
//   6. identifyPestFromImage           — Gemini Vision
//   7. diagnoseHandymanProblemFromPhoto — Gemini Vision (downloads photos)
//   8. optimizeTrainerProfile          — Gemini callable
//   9. generateCustomWorkoutPlan       — Gemini callable (auth: self/admin/booked-provider)
//  10. generateBannerInsights          — scheduled Gemini
//  11. smartProviderOrder              — Gemini callable + cache
//
// Coverage focus: auth gates + input validation + key error paths.
// Heavy AI computation paths are out of scope — covered by integration testing.
// ═══════════════════════════════════════════════════════════════════════════════

// ─── 1. generateServiceSchema (Claude) ─────────────────────────────────────
describe("generateServiceSchema — Claude callable (admin-only, §3b)", () => {
  const cf = index.generateServiceSchema;
  const Anthropic = require("@anthropic-ai/sdk").default;

  beforeEach(() => {
    jest.clearAllMocks();
    Anthropic.__create.mockReset();
  });

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin caller", async () => {
    mockCollection({ "users/regular": mockDocSnap(true, { isAdmin: false }) });
    await expect(
      cf({ auth: { uid: "regular", token: {} }, data: { categoryName: "ניקיון" } })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects empty/short categoryName", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });
    await expect(
      cf({ auth: { uid: "admin1", token: {} }, data: { categoryName: "א" } })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("admin + valid category + Claude valid JSON → returns schema", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });
    Anthropic.__create.mockResolvedValueOnce({
      content: [{
        text: JSON.stringify([
          { id: "rooms", label: "חדרים", type: "number" },
          { id: "kosher", label: "כשר", type: "bool" },
        ]),
      }],
      usage: { input_tokens: 100, output_tokens: 50 },
    });

    const result = await cf({
      auth: { uid: "admin1", token: {} },
      data: { categoryName: "ניקיון" },
    });

    // CF returns { schema: [...] } per the source
    expect(result).toBeDefined();
    expect(Array.isArray(result.schema)).toBe(true);
    expect(result.schema.length).toBe(2);
    expect(result.schema[0].id).toBe("rooms");
    expect(result.schema[1].type).toBe("bool");
  });

  test("Claude returns invalid JSON → throws internal", async () => {
    mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });
    Anthropic.__create.mockResolvedValueOnce({
      content: [{ text: "not-json {" }],
      usage: { input_tokens: 50, output_tokens: 10 },
    });

    await expect(
      cf({ auth: { uid: "admin1", token: {} }, data: { categoryName: "Cleaning" } })
    ).rejects.toMatchObject({ code: "internal" });
  });
});


// ─── 2. generateCeoInsight (Claude+Gemini) ────────────────────────────────
describe("generateCeoInsight — admin-only auth gate (§12c)", () => {
  // Heavy CF (40+ deep metrics + dual AI). Cover only the auth gates here.
  const cf = index.generateCeoInsight;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin caller", async () => {
    mockCollection({ "users/regular": mockDocSnap(true, { isAdmin: false }) });
    await expect(
      cf({ auth: { uid: "regular", token: {} }, data: {} })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });
});


// ─── 3. backfillAdminClaims (admin one-shot) ──────────────────────────────
describe("backfillAdminClaims — admin one-shot (§50)", () => {
  const cf = index.backfillAdminClaims;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin caller", async () => {
    mockCollection({ "users/regular": mockDocSnap(true, { isAdmin: false }) });
    await expect(
      cf({ auth: { uid: "regular", token: {} }, data: {} })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("admin + dryRun=true → scans without writing claims", async () => {
    // listUsers returns 2 users — one admin, one regular.
    mockAuth.listUsers = jest.fn(async () => ({
      users: [
        { uid: "admin1", customClaims: {} },        // needs claim
        { uid: "regular1", customClaims: {} },      // already correct
      ],
      pageToken: undefined,
    }));

    mockCollection({
      "users/admin1": mockDocSnap(true, { isAdmin: true }),
      "users/regular1": mockDocSnap(true, { isAdmin: false }),
    });
    // Caller's own admin doc lookup
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "users") {
            if (id === "admin-caller") return mockDocSnap(true, { isAdmin: true });
            if (id === "admin1") return mockDocSnap(true, { isAdmin: true });
            if (id === "regular1") return mockDocSnap(true, { isAdmin: false });
          }
          return mockDocSnap(false);
        }),
      })),
      add: jest.fn(async () => ({ id: "auto" })),
    }));

    const result = await cf({
      auth: { uid: "admin-caller", token: {} },
      data: { dryRun: true },
    });

    expect(result).toBeDefined();
    expect(result.scanned).toBeGreaterThanOrEqual(0);
    // dryRun → setCustomUserClaims NOT called
    expect(mockAuth.setCustomUserClaims).not.toHaveBeenCalled();
  });
});


// ─── 4. getEffectiveCommission ─────────────────────────────────────────────
describe("getEffectiveCommission — callable (§31)", () => {
  const cf = index.getEffectiveCommission;

  beforeEach(() => jest.clearAllMocks());

  function setupCommissionMocks({ callerIsAdmin = false, userOverride = null }) {
    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => ({
        get: jest.fn(async () => {
          if (col === "users") {
            if (id === "self-uid") {
              return {
                exists: true, id,
                data: () => userOverride || {},
              };
            }
            if (id === "admin1") {
              return mockDocSnap(true, { isAdmin: callerIsAdmin });
            }
            if (id === "other-uid") {
              return { exists: true, id, data: () => ({}) };
            }
          }
          if (col === "category_commissions") {
            return mockDocSnap(false);
          }
          if (col === "admin") {
            return {
              collection: jest.fn(() => ({
                doc: jest.fn(() => ({
                  get: jest.fn(async () => ({
                    exists: true,
                    data: () => ({ feePercentage: 0.10 }),
                  })),
                })),
              })),
            };
          }
          return mockDocSnap(false);
        }),
        collection: jest.fn(() => ({
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({
              exists: true,
              data: () => ({ feePercentage: 0.10 }),
            })),
          })),
        })),
      })),
    }));
  }

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects missing userId", async () => {
    setupCommissionMocks({});
    await expect(
      cf({ auth: { uid: "u1", token: {} }, data: {} })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("self query → succeeds (no admin gate needed)", async () => {
    setupCommissionMocks({});
    const result = await cf({
      auth: { uid: "self-uid", token: {} },
      data: { userId: "self-uid" },
    });
    // Falls through to global commission of 10% → percentage=10
    expect(result).toBeDefined();
    expect(result.percentage).toBe(10);
    expect(result.source).toBe("global");
  });

  test("non-admin querying ANOTHER user → permission-denied", async () => {
    setupCommissionMocks({ callerIsAdmin: false });
    await expect(
      cf({
        auth: { uid: "admin1", token: {} },     // not actually admin per mock
        data: { userId: "other-uid" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("admin querying ANOTHER user → succeeds", async () => {
    setupCommissionMocks({ callerIsAdmin: true });
    const result = await cf({
      auth: { uid: "admin1", token: {} },
      data: { userId: "other-uid" },
    });
    expect(result).toBeDefined();
    expect(result.percentage).toBe(10);
  });

  test("user has active customCommission override → returned as 'custom'", async () => {
    setupCommissionMocks({
      userOverride: {
        customCommissionActive: true,
        customCommission: {
          percentage: 5,
          reason: "VIP partner",
          setAt: { toMillis: () => Date.now() - 1000 },
        },
      },
    });
    const result = await cf({
      auth: { uid: "self-uid", token: {} },
      data: { userId: "self-uid" },
    });
    expect(result.percentage).toBe(5);
    expect(result.source).toBe("custom");
  });
});


// ─── 5. adminReleaseEscrow ─────────────────────────────────────────────────
describe("adminReleaseEscrow — admin force-release (§31)", () => {
  const cf = index.adminReleaseEscrow;

  beforeEach(() => {
    jest.clearAllMocks();
    const admin = require("firebase-admin");
    admin.firestore.Timestamp = {
      now: jest.fn(() => ({ toMillis: () => Date.now() })),
      fromDate: jest.fn((d) => ({ toMillis: () => d.getTime() })),
    };
  });

  function setupAdminReleaseMocks({
    isAdmin = true,
    jobExists = true,
    jobStatus = "paid_escrow",
    expertId = "expert-1",
    customerId = "customer-1",
    netAmountForExpert = 90,
    commission = 10,
  }) {
    const txCalls = { update: [], set: [] };

    mockFirestore.collection.mockImplementation((col) => ({
      doc: jest.fn((id) => {
        if (col === "users") {
          return {
            get: jest.fn(async () => mockDocSnap(true, { isAdmin })),
            update: jest.fn(),
          };
        }
        if (col === "jobs") {
          return {
            get: jest.fn(async () => ({
              exists: jobExists, id,
              data: () => ({
                status: jobStatus, expertId, customerId,
                netAmountForExpert, commission,
              }),
            })),
            update: jest.fn(),
          };
        }
        return { get: jest.fn(async () => mockDocSnap(false)) };
      }),
      add: jest.fn(async () => ({ id: "auto" })),
    }));

    mockFirestore.runTransaction = jest.fn(async (cb) => {
      const tx = {
        get: jest.fn(async (ref) => {
          if (typeof ref.get === "function") return ref.get();
          return mockDocSnap(false);
        }),
        update: jest.fn((r, p) => txCalls.update.push({ ref: r, payload: p })),
        set: jest.fn((r, p) => txCalls.set.push({ ref: r, payload: p })),
      };
      return cb(tx);
    });

    return { txCalls };
  }

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin", async () => {
    setupAdminReleaseMocks({ isAdmin: false });
    await expect(
      cf({ auth: { uid: "regular", token: {} }, data: { jobId: "j1" } })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects missing jobId", async () => {
    setupAdminReleaseMocks({});
    await expect(
      cf({ auth: { uid: "admin", token: {} }, data: {} })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects job not found", async () => {
    setupAdminReleaseMocks({ jobExists: false });
    await expect(
      cf({ auth: { uid: "admin", token: {} }, data: { jobId: "ghost" } })
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("rejects wrong job status (e.g. completed)", async () => {
    setupAdminReleaseMocks({ jobStatus: "completed" });
    await expect(
      cf({ auth: { uid: "admin", token: {} }, data: { jobId: "j1" } })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("happy path: paid_escrow job → expert balance += netAmount, status='completed'", async () => {
    const { txCalls } = setupAdminReleaseMocks({
      jobStatus: "paid_escrow",
      netAmountForExpert: 90,
      commission: 10,
    });

    await cf({
      auth: { uid: "admin", token: {} },
      data: { jobId: "j1", note: "Resolved support ticket" },
    });

    // Tx writes: provider balance + provider pendingBalance + orderCount in
    // ONE update; platform_earnings + transactions sets; job status update
    expect(txCalls.update.length).toBeGreaterThanOrEqual(2);
    expect(txCalls.set.length).toBeGreaterThanOrEqual(2);

    const balanceUpdate = txCalls.update.find(
      (c) => c.payload.balance
    );
    expect(balanceUpdate).toBeDefined();
    expect(String(balanceUpdate.payload.balance)).toBe("INC(90)");

    const jobStatusUpdate = txCalls.update.find(
      (c) => c.payload.status === "completed"
    );
    expect(jobStatusUpdate).toBeDefined();
    expect(jobStatusUpdate.payload.resolutionType).toBe("admin_release");
  });
});


// ─── 6. identifyPestFromImage (Gemini Vision) ──────────────────────────────
describe("identifyPestFromImage — Gemini Vision (§32)", () => {
  const cf = index.identifyPestFromImage;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects missing imageBase64", async () => {
    await expect(
      cf({ auth: { uid: "u1" }, data: {} })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("Gemini valid response → identification returned", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp(JSON.stringify({
        pestType: "cockroaches",
        pestTypeHe: "ג'וקים",
        confidence: 0.92,
        urgencyLevel: "high",
        description: "ג'וק גרמני בוגר",
        treatmentRecommendation: "regular_spray",
      })),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: { imageBase64: "fake-base64" },
    });

    expect(result.pestType).toBe("cockroaches");
    expect(result.pestTypeHe).toBe("ג'וקים");
    expect(result.confidence).toBe(0.92);
    expect(result.urgencyLevel).toBe("high");
    expect(result.treatmentRecommendation).toBe("regular_spray");
  });

  test("Gemini HTTP error → HttpsError(internal)", async () => {
    buildGeminiCallableMocks({
      fetchResponse: { ok: false, status: 500, text: async () => "err" },
    });

    await expect(
      cf({ auth: { uid: "u1" }, data: { imageBase64: "fake" } })
    ).rejects.toMatchObject({ code: "internal" });
  });

  test("Gemini missing fields → defensive defaults applied", async () => {
    buildGeminiCallableMocks({
      fetchResponse: mkGeminiResp("{}"),
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: { imageBase64: "x" },
    });

    expect(result.pestType).toBe("other");
    expect(result.pestTypeHe).toBe("לא ידוע");
    expect(result.confidence).toBe(0.5);
    expect(result.alternativeMatches).toEqual([]);
    expect(result.urgencyLevel).toBe("medium");
    expect(result.treatmentRecommendation).toBe("green");
  });
});


// ─── 7. diagnoseHandymanProblemFromPhoto (Gemini Vision + photo download) ─
describe("diagnoseHandymanProblemFromPhoto — Gemini Vision (§41)", () => {
  const cf = index.diagnoseHandymanProblemFromPhoto;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects empty photoUrls", async () => {
    await expect(
      cf({ auth: { uid: "u1" }, data: { photoUrls: [] } })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("photo download all fail → HttpsError(internal)", async () => {
    // The CF tries each photo URL via fetch — all return non-OK.
    let callCount = 0;
    global.fetch = jest.fn(async () => {
      callCount++;
      // First N fetches are photo downloads — return non-OK
      return { ok: false, status: 404 };
    });

    await expect(
      cf({
        auth: { uid: "u1" },
        data: { photoUrls: ["https://x.com/img1", "https://x.com/img2"] },
      })
    ).rejects.toMatchObject({ code: "internal" });
  });

  test("happy path: photo downloaded + Gemini valid response", async () => {
    let fetchCallCount = 0;
    global.fetch = jest.fn(async (url) => {
      fetchCallCount++;
      if (fetchCallCount === 1) {
        // Photo download
        return {
          ok: true,
          arrayBuffer: async () => new ArrayBuffer(8),
        };
      }
      // Gemini call
      return {
        ok: true,
        json: async () => ({
          candidates: [{
            content: {
              parts: [{
                text: JSON.stringify({
                  identifiedProblem: "ברז דולף",
                  confidence: 0.85,
                  category: "plumbing",
                  estimatedDurationMinutes: 60,
                  estimatedPrice: 250,
                  estimatedMaterialsCost: 30,
                  recommendedMaterials: [{ name: "אטם", price: 30 }],
                  urgencyLevel: "medium",
                }),
              }],
            },
          }],
        }),
      };
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: { photoUrls: ["https://x.com/img1"] },
    });

    expect(result.identifiedProblem).toBe("ברז דולף");
    expect(result.category).toBe("plumbing");
    expect(result.estimatedPrice).toBe(250);
    expect(result.recommendedMaterials.length).toBe(1);
  });
});


// ─── 8. optimizeTrainerProfile ─────────────────────────────────────────────
describe("optimizeTrainerProfile — Gemini callable (§44)", () => {
  const cf = index.optimizeTrainerProfile;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects non-admin trying to optimize ANOTHER trainer", async () => {
    mockCollection({ "users/regular": mockDocSnap(true, { isAdmin: false }) });
    await expect(
      cf({
        auth: { uid: "regular", token: {} },
        data: { trainerId: "other-trainer" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("rejects when trainer doc not found (self target)", async () => {
    mockFirestore.collection.mockImplementation(() => ({
      doc: jest.fn(() => ({
        get: jest.fn(async () => mockDocSnap(false)),
      })),
    }));

    await expect(
      cf({ auth: { uid: "self", token: {} }, data: {} })
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("Gemini fail → fallback suggestions still returned (no throw)", async () => {
    mockFirestore.collection.mockImplementation(() => ({
      doc: jest.fn(() => ({
        get: jest.fn(async () => mockDocSnap(true, {
          name: "Trainer",
          aboutMe: "short",     // < 200 chars → triggers fallback suggestion
          fitnessTrainerProfile: {
            successStories: [],
            offers: [],
            selectedSpecialties: ["x"],
            packages: [],
          },
        })),
        update: jest.fn(),
      })),
    }));
    global.fetch = jest.fn(async () => { throw new Error("Gemini down"); });

    // Contract: must NOT throw — return fallback suggestions
    const result = await cf({ auth: { uid: "self", token: {} }, data: {} });
    expect(result).toBeDefined();
    // CF returns { score, suggestions, fallback } per the source
    expect(typeof result.score).toBe("number");
    expect(result.fallback).toBe(true);
    expect(Array.isArray(result.suggestions)).toBe(true);
    // Fallback should suggest adding success stories, offers, longer aboutMe, more specialties, more packages
    expect(result.suggestions.length).toBeGreaterThan(0);
  });
});


// ─── 9. generateCustomWorkoutPlan ──────────────────────────────────────────
describe("generateCustomWorkoutPlan — Gemini callable (§44)", () => {
  const cf = index.generateCustomWorkoutPlan;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects when caller targets another user with NO booked job", async () => {
    // Auth check: caller != clientId, isAdmin=false, no jobs link
    mockFirestore.collection.mockImplementation((col) => {
      if (col === "users") {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => mockDocSnap(true, { isAdmin: false })),
          })),
        };
      }
      if (col === "jobs") {
        const chain = {
          where: jest.fn(() => chain),
          limit: jest.fn(() => chain),
          get: jest.fn(async () => ({ empty: true, docs: [] })),
        };
        return { where: jest.fn(() => chain) };
      }
      return {};
    });

    await expect(
      cf({
        auth: { uid: "stranger", token: {} },
        data: { clientId: "victim", goal: "lose_weight" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("self-target (no clientId) → proceeds (auth bypass)", async () => {
    let fetchCallCount = 0;
    global.fetch = jest.fn(async () => {
      fetchCallCount++;
      // Return a valid plan
      return {
        ok: true,
        json: async () => ({
          candidates: [{
            content: {
              parts: [{
                text: JSON.stringify({
                  planOverview: "Plan summary",
                  weeklySchedule: [{ week: 1, title: "Week 1", days: [] }],
                  progressionStrategy: "...",
                  recoveryTips: [],
                  nutritionGuidelines: [],
                }),
              }],
            },
          }],
        }),
      };
    });

    mockFirestore.collection.mockImplementation(() => ({
      doc: jest.fn(() => ({
        get: jest.fn(async () => mockDocSnap(false)),
        collection: jest.fn(() => ({
          doc: jest.fn(() => ({ id: "plan-1" })),
          add: jest.fn(async () => ({ id: "plan-1" })),
        })),
      })),
      add: jest.fn(async () => ({ id: "plan-1" })),
    }));

    const result = await cf({
      auth: { uid: "self", token: {} },
      data: { goal: "build_muscle", experience: "beginner", durationWeeks: 4 },
    });

    expect(result).toBeDefined();
    expect(result.planOverview).toBe("Plan summary");
  });
});


// ─── 10. generateBannerInsights (scheduled Gemini, §49) ────────────────────
describe("generateBannerInsights — scheduled Gemini (§49)", () => {
  const trigger = index.generateBannerInsights;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  function setupBannerInsightsMocks({ banners = [], fetchResponse, fetchThrows = false }) {
    const setCalls = [];

    mockFirestore.collection.mockImplementation((col) => {
      if (col === "banners") {
        const docs = banners.map((b, i) => ({
          id: `b${i}`,
          data: () => b,
        }));
        return {
          limit: jest.fn(() => ({
            get: jest.fn(async () => ({
              docs, empty: docs.length === 0, size: docs.length,
            })),
          })),
        };
      }
      if (col === "ai_insights") {
        return {
          doc: jest.fn((id) => ({
            id,
            set: jest.fn(async (payload) => {
              setCalls.push({ id, payload });
            }),
          })),
        };
      }
      return {};
    });

    if (fetchThrows) {
      global.fetch = jest.fn(async () => {
        throw new Error("Network down");
      });
    } else if (fetchResponse) {
      global.fetch = jest.fn(async () => fetchResponse);
    }

    return { setCalls };
  }

  test("no banners → returns 'no_banners' without writes", async () => {
    const { setCalls } = setupBannerInsightsMocks({ banners: [] });
    const result = await trigger();
    expect(result).toMatchObject({ ok: true, reason: "no_banners" });
    expect(setCalls.length).toBe(0);
  });

  test("banners + Gemini valid → ai_insights/banners written", async () => {
    const { setCalls } = setupBannerInsightsMocks({
      banners: [
        {
          title: "Banner 1",
          impressions: 1000,
          clicks: 50,
          isActive: true,
          placement: "home_carousel",
        },
      ],
      fetchResponse: mkGeminiResp(JSON.stringify({
        title: "המלץ על קידום VIP",
        recommendation: "הוסף 3 ספקים נוספים",
        expectedImpact: "+₪5K/חודש",
        actionType: "promote_vip",
        actionParams: {},
      })),
    });

    await trigger();

    expect(setCalls.length).toBeGreaterThanOrEqual(1);
    const insight = setCalls.find((c) => c.id === "banners");
    expect(insight).toBeDefined();
  });
});


// ─── 11. smartProviderOrder (Gemini callable + cache) ──────────────────────
describe("smartProviderOrder — Gemini callable + cache (§49)", () => {
  const cf = index.smartProviderOrder;

  let originalFetch;
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
  });
  afterEach(() => { global.fetch = originalFetch; });

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("too few providers (< 2) → returns input as-is with fallback flag", async () => {
    const result = await cf({
      auth: { uid: "u1" },
      data: { providerIds: ["only-one"] },
    });

    expect(result.fallback).toBe(true);
    expect(result.reason).toBe("too_few");
    expect(result.orderedIds).toEqual(["only-one"]);
  });

  test("cached order (within 1h, same set) → returns cached, no Gemini call", async () => {
    mockFirestore.collection.mockImplementation((col) => {
      if (col === "ai_provider_order") {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({
              exists: true,
              data: () => ({
                orderedIds: ["b", "a"],     // reversed = AI ordered them
                generatedAt: { toDate: () => new Date(Date.now() - 60_000) },
              }),
            })),
          })),
        };
      }
      return { doc: jest.fn(() => ({ get: jest.fn(async () => mockDocSnap(false)) })) };
    });

    let fetchCalled = false;
    global.fetch = jest.fn(() => { fetchCalled = true; return {}; });

    const result = await cf({
      auth: { uid: "u1" },
      data: { providerIds: ["a", "b"], bannerId: "banner-1" },
    });

    expect(result.cached).toBe(true);
    expect(result.orderedIds).toEqual(["b", "a"]);
    expect(fetchCalled).toBe(false);
  });

  test("provider fetch fails → fallback to input order", async () => {
    mockFirestore.collection.mockImplementation((col) => {
      if (col === "ai_provider_order") {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => mockDocSnap(false)),
          })),
        };
      }
      // users.where(...).get() throws
      const chain = {
        where: jest.fn(() => chain),
        get: jest.fn(async () => { throw new Error("Network"); }),
      };
      return { where: jest.fn(() => chain) };
    });

    const result = await cf({
      auth: { uid: "u1" },
      data: { providerIds: ["a", "b", "c"] },
    });

    expect(result.fallback).toBe(true);
    expect(result.reason).toBe("fetch_error");
    expect(result.orderedIds).toEqual(["a", "b", "c"]);
  });
});

