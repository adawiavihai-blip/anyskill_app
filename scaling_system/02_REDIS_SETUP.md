# 🟡 Milestone 2: Redis Cache Layer

**Activate when:** DAU > 10,000 OR Firestore cost > $200/month  
**Duration:** 1 Claude Code session (~4-6 hours)  
**Additional cost:** +$25-50/month  
**Prerequisites:** Milestone 1 completed  

---

## 📋 FOR CLAUDE CODE: EXECUTE THIS PROMPT

Only run this when `CURRENT_STATUS.md` triggers indicate Milestone 2 is needed.

---

## 🎯 WHAT TO BUILD

Add a Redis caching layer to reduce Firestore reads by 60-80%.

### Step 1: User Setup (Tell User)

Instruct Avihai to:
1. Go to Google Cloud Console
2. Enable **Memorystore for Redis API**
3. Create Redis instance:
   - Name: `anyskill-redis-cache`
   - Tier: Basic (cheapest) or Standard (HA)
   - Capacity: Start with 1GB
   - Region: Same as Firestore
4. Note down the Redis IP address

### Step 2: Install Dependencies

```bash
cd functions
npm install ioredis @types/ioredis
```

### Step 3: Create Redis Service

```typescript
// functions/src/services/redis_service.ts

import Redis from "ioredis";
import * as functions from "firebase-functions";

let redisClient: Redis | null = null;

export function getRedisClient(): Redis {
  if (!redisClient) {
    const redisHost = functions.config().redis.host;
    const redisPort = functions.config().redis.port || 6379;
    
    redisClient = new Redis({
      host: redisHost,
      port: redisPort,
      maxRetriesPerRequest: 3,
      retryStrategy: (times) => Math.min(times * 50, 2000),
    });
    
    redisClient.on("error", (err) => {
      console.error("Redis error:", err);
    });
  }
  
  return redisClient;
}

// Cache wrapper
export async function cacheGet<T>(
  key: string,
  ttlSeconds: number,
  fetcher: () => Promise<T>
): Promise<T> {
  const redis = getRedisClient();
  
  // Try cache first
  try {
    const cached = await redis.get(key);
    if (cached) {
      return JSON.parse(cached);
    }
  } catch (err) {
    console.warn("Redis read failed, falling back to source:", err);
  }
  
  // Fetch from source
  const data = await fetcher();
  
  // Store in cache (non-blocking)
  redis.setex(key, ttlSeconds, JSON.stringify(data))
    .catch((err) => console.warn("Redis write failed:", err));
  
  return data;
}

export async function cacheInvalidate(pattern: string): Promise<void> {
  const redis = getRedisClient();
  const keys = await redis.keys(pattern);
  if (keys.length > 0) {
    await redis.del(...keys);
  }
}
```

### Step 4: Apply Caching to Hot Endpoints

Identify the top 5 most-called endpoints and add caching:

```typescript
// Example: Search experts (very hot endpoint)

export const searchExperts = functions.https.onCall(async (data, context) => {
  const { category, city } = data;
  const cacheKey = `experts:${category}:${city}`;
  
  return cacheGet(
    cacheKey,
    600, // 10 minutes TTL
    async () => {
      // Original Firestore query
      const snap = await admin.firestore()
        .collection("experts")
        .where("category", "==", category)
        .where("city", "==", city)
        .where("isActive", "==", true)
        .limit(50)
        .get();
      
      return snap.docs.map(d => ({ id: d.id, ...d.data() }));
    }
  );
});
```

**Endpoints to cache (priority order):**

1. **Expert search** - TTL: 10 min
2. **User profile** - TTL: 1 hour
3. **Category list** - TTL: 1 day
4. **Provider profile** - TTL: 15 min
5. **Popular services** - TTL: 1 hour

### Step 5: Cache Invalidation on Writes

When data changes, invalidate cache:

```typescript
export const onExpertUpdate = functions.firestore
  .document("experts/{expertId}")
  .onWrite(async (change, context) => {
    const data = change.after.data();
    if (data) {
      // Invalidate all searches for this category/city
      await cacheInvalidate(`experts:${data.category}:*`);
      await cacheInvalidate(`experts:*:${data.city}`);
    }
  });
```

### Step 6: Update Performance Dashboard

Add Redis metrics to the dashboard:

```dart
// In performance_tab.dart, add new widget:

class RedisStatsWidget extends StatelessWidget {
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: firestore.collection('performance_metrics')
        .doc('redis').snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return Container();
        
        final stats = snap.data!.data() as Map;
        final hitRate = stats['hit_rate'] ?? 0;
        final savedReads = stats['saved_firestore_reads'] ?? 0;
        final savedCost = stats['saved_cost_usd'] ?? 0;
        
        return PerformanceCard(
          child: Column(
            children: [
              Text("⚡ Redis Cache", style: cardTitle),
              Text("Hit Rate: $hitRate%"),
              Text("Saved reads: $savedReads"),
              Text("חסכון: \$$savedCost/חודש"),
            ],
          ),
        );
      },
    );
  }
}
```

### Step 7: Monitor Redis Health

Add a scheduled function to track Redis performance:

```typescript
export const trackRedisStats = functions.pubsub
  .schedule("every 10 minutes")
  .onRun(async () => {
    const redis = getRedisClient();
    const info = await redis.info("stats");
    
    // Parse hit rate from INFO command
    const hitRate = parseRedisHitRate(info);
    const savedReads = parseRedisSavedReads(info);
    
    await admin.firestore()
      .collection("performance_metrics")
      .doc("redis")
      .set({
        hit_rate: hitRate,
        saved_firestore_reads: savedReads,
        saved_cost_usd: savedReads * 0.00006, // $0.06 per 1K reads
        last_updated: admin.firestore.FieldValue.serverTimestamp(),
      });
  });
```

---

## ✅ ACCEPTANCE CRITERIA

- [ ] Redis instance running on GCP
- [ ] 5 hot endpoints cached
- [ ] Cache invalidation working
- [ ] Hit rate > 60% after 1 week
- [ ] Dashboard shows Redis stats
- [ ] Firestore reads reduced by 40%+
- [ ] `flutter analyze`: 0 issues

---

## 📝 UPDATE CURRENT_STATUS.md

```yaml
active_milestone: 2
milestone_name: "Redis Cache Layer"
status: "completed"
completed_date: "YYYY-MM-DD"

has_redis: true
redis_hit_rate: 75  # initial

next_milestone: 3
next_milestone_trigger: "DAU > 50K OR Dashboard load > 2s"
```

---

**Cost impact:** +$25-50/month  
**Benefit:** 60-80% Firestore read reduction  
**Next:** Wait for Milestone 3 triggers
