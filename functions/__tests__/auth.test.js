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

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentCreated: jest.fn(() => jest.fn()),
  onDocumentUpdated: jest.fn(() => jest.fn()),
}));
jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: jest.fn(() => jest.fn()),
}));
jest.mock("firebase-functions/params", () => ({
  defineSecret: jest.fn(() => ({ value: () => "test-secret" })),
}));
jest.mock("@anthropic-ai/sdk", () => ({
  default: class MockAnthropic {},
}));

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

  test("rejects missing required fields", async () => {
    await expect(
      ppr({ auth: { uid: "u1" }, data: { jobId: "j1" } })
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects caller who is not the customer", async () => {
    mockCollection({
      "jobs/j1": mockDocSnap(true, {
        customerId: "real-customer",
        expertId: "e1",
        status: "paid_escrow",
      }),
    });

    await expect(
      ppr({
        auth: { uid: "not-the-customer" },
        data: { jobId: "j1", expertId: "e1", totalAmount: 100 },
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
