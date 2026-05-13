# 🔴 Milestone 4: Sharding + Multi-Region

**Activate when:** DAU > 500,000 OR peak writes > 8,000/sec  
**Duration:** 5-6 Claude Code sessions (~25-35 hours)  
**Additional cost:** +$300-1,000/month  
**Prerequisites:** Milestones 1-3 completed  

---

## 📋 FOR CLAUDE CODE: EXECUTE THIS PROMPT

⚠️ **WARNING:** This is a MAJOR infrastructure change. Requires careful planning.  
Only run when all previous milestones are stable for 3+ months.

---

## 🎯 WHAT TO BUILD

### Step 1: Firestore Sharding

Split hot collections into 10 shards to distribute load.

**Collections to shard:**
1. `experts` → `experts_shard_0` through `experts_shard_9`
2. `bookings` → `bookings_2026_04`, `bookings_2026_05`, etc. (by month)
3. `chats` → `chats_shard_0` through `chats_shard_9`
4. `notifications` → `notifications_shard_0` through `notifications_shard_9`

### Step 2: Migration Strategy

**Zero-downtime migration using dual-write pattern:**

```typescript
// functions/src/migration/shardMigration.ts

/**
 * Phase 1: Dual-write (write to both old and new)
 * Duration: 1 week
 */
export const dualWriteExpert = functions.firestore
  .document("experts/{expertId}")
  .onWrite(async (change, context) => {
    const data = change.after.data();
    if (!data) return;
    
    const expertId = context.params.expertId;
    const shardId = hashToShard(expertId, 10);
    
    // Write to new shard
    await admin.firestore()
      .collection(`experts_shard_${shardId}`)
      .doc(expertId)
      .set(data);
  });

function hashToShard(id: string, shardCount: number): number {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = ((hash << 5) - hash) + id.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash) % shardCount;
}

/**
 * Phase 2: Backfill (migrate existing data)
 */
export const backfillExperts = functions.https.onCall(async (data, context) => {
  // Only allow admin
  if (!context.auth?.token.admin) {
    throw new functions.https.HttpsError("permission-denied", "Admin only");
  }
  
  const snap = await admin.firestore().collection("experts").get();
  const batch = admin.firestore().batch();
  
  snap.docs.forEach((doc) => {
    const shardId = hashToShard(doc.id, 10);
    const newRef = admin.firestore()
      .collection(`experts_shard_${shardId}`)
      .doc(doc.id);
    batch.set(newRef, doc.data());
  });
  
  await batch.commit();
  return { migrated: snap.docs.length };
});

/**
 * Phase 3: Update reads to use shards
 */
export const searchExpertsSharded = functions.https.onCall(async (data) => {
  const { category, city } = data;
  
  // Query ALL shards in parallel
  const promises = [];
  for (let i = 0; i < 10; i++) {
    promises.push(
      admin.firestore()
        .collection(`experts_shard_${i}`)
        .where("category", "==", category)
        .where("city", "==", city)
        .limit(5)
        .get()
    );
  }
  
  const snapshots = await Promise.all(promises);
  const results = snapshots.flatMap(snap => 
    snap.docs.map(doc => ({ id: doc.id, ...doc.data() }))
  );
  
  return results.slice(0, 50);
});
```

### Step 3: Multi-Region Deployment

**Deploy Cloud Run to multiple regions:**

```bash
# Primary: Israel (closest)
gcloud run deploy anyskill-api \
  --region=europe-west3 \
  --image=gcr.io/anyskill/api:latest

# Secondary: US
gcloud run deploy anyskill-api \
  --region=us-central1 \
  --image=gcr.io/anyskill/api:latest

# Tertiary: Asia
gcloud run deploy anyskill-api \
  --region=asia-southeast1 \
  --image=gcr.io/anyskill/api:latest

# Global Load Balancer
gcloud compute url-maps create anyskill-lb \
  --default-service=anyskill-backend-service
```

### Step 4: CloudFlare CDN

Set up CloudFlare in front for global CDN:

1. Add domain to CloudFlare
2. Configure caching rules:
   - Static assets: Cache 1 year
   - API responses: Cache 5 min (with revalidation)
   - HTML: No cache
3. Enable: Auto-minify, Brotli, HTTP/3, WebP

### Step 5: Data Replication Strategy

Firestore already has multi-region replication automatically when you choose `nam5` or `eur3` location. If not, migrate:

```bash
# Check current location
gcloud firestore databases describe --database="(default)"

# If not multi-region, create new one
gcloud firestore databases create \
  --database=anyskill-multiregion \
  --location=eur3 \
  --type=firestore-native
```

### Step 6: Circuit Breakers

Add circuit breaker pattern for resilience:

```typescript
// functions/src/resilience/circuitBreaker.ts

import CircuitBreaker from "opossum";

const expertSearchOptions = {
  timeout: 3000,
  errorThresholdPercentage: 50,
  resetTimeout: 30000,
};

const searchBreaker = new CircuitBreaker(
  searchExpertsSharded,
  expertSearchOptions
);

searchBreaker.fallback(() => ({
  results: [],
  fromFallback: true,
  message: "Search temporarily unavailable, showing cached results",
}));

export const resilientSearch = functions.https.onCall((data) => {
  return searchBreaker.fire(data);
});
```

### Step 7: Update Performance Dashboard

Add new widgets:

- **Regional status map** - show health of each region
- **Shard distribution** - show load across shards
- **Circuit breaker states** - which circuits are open/closed
- **Failover history** - when did failovers occur

---

## ✅ ACCEPTANCE CRITERIA

- [ ] All hot collections sharded (10× shards)
- [ ] Zero downtime during migration
- [ ] Multi-region deployment active
- [ ] CloudFlare CDN configured
- [ ] Circuit breakers on all external calls
- [ ] Dashboard shows regional health
- [ ] Peak writes distributed across shards
- [ ] Can handle 50K writes/sec total

---

## 📝 UPDATE CURRENT_STATUS.md

```yaml
active_milestone: 4
status: "completed"
has_sharding: true
has_multi_region: true
has_cdn: true
has_circuit_breakers: true
max_writes_per_sec: 100000

next_milestone: 5
next_milestone_trigger: "DAU > 5M"
```

---

**Cost impact:** +$300-1,000/month  
**Benefit:** Handle 500K-5M DAU globally  
**Next:** Milestone 5 for true enterprise features
