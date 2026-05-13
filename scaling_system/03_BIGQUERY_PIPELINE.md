# 🟠 Milestone 3: BigQuery Analytics Pipeline

**Activate when:** DAU > 50,000 OR Dashboard load > 2s  
**Duration:** 3-4 Claude Code sessions (~15-20 hours)  
**Additional cost:** +$30-100/month  
**Prerequisites:** Milestones 1-2 completed  

---

## 📋 FOR CLAUDE CODE: EXECUTE THIS PROMPT

Only run when `CURRENT_STATUS.md` confirms:
- `active_milestone: 2` with `status: completed`
- At least one Milestone 3 trigger is true

---

## 🎯 WHAT TO BUILD

Set up BigQuery pipeline so the Performance Dashboard reads aggregated metrics instead of Firestore directly.

### Step 1: User Setup (Tell User)

Instruct Avihai:
1. Enable APIs: **BigQuery API**, **Cloud Pub/Sub API**, **Cloud Dataflow API**
2. Approve billing (~$30-100/month)

### Step 2: Create BigQuery Dataset

```bash
# Run these gcloud commands (instruct user)
bq mk --dataset --location=us-central1 anyskill:analytics

bq mk --table anyskill:analytics.metrics_1min \
  timestamp:TIMESTAMP,metric_name:STRING,value:FLOAT,tags:JSON

bq mk --table anyskill:analytics.metrics_1hour \
  timestamp:TIMESTAMP,metric_name:STRING,avg_value:FLOAT,max_value:FLOAT,min_value:FLOAT

bq mk --table anyskill:analytics.metrics_1day \
  date:DATE,metric_name:STRING,total:FLOAT,avg:FLOAT

bq mk --table anyskill:analytics.user_events \
  timestamp:TIMESTAMP,user_id:STRING,event_type:STRING,metadata:JSON

bq mk --table anyskill:analytics.api_latency \
  timestamp:TIMESTAMP,endpoint:STRING,p50:FLOAT,p95:FLOAT,p99:FLOAT

bq mk --table anyskill:analytics.errors \
  timestamp:TIMESTAMP,error_type:STRING,service:STRING,count:INTEGER

bq mk --table anyskill:analytics.business_metrics \
  date:DATE,revenue:FLOAT,bookings:INTEGER,new_users:INTEGER,churn:INTEGER
```

### Step 3: Create Pub/Sub Topics

```bash
gcloud pubsub topics create performance-metrics-raw
gcloud pubsub topics create performance-metrics-aggregated
gcloud pubsub topics create business-events
gcloud pubsub topics create errors-stream

# Create subscriptions with BigQuery sink
gcloud pubsub subscriptions create metrics-to-bq \
  --topic=performance-metrics-aggregated \
  --bigquery-table=anyskill.analytics.metrics_1min
```

### Step 4: Create Aggregation Cloud Function

```typescript
// functions/src/analytics/aggregateToBigQuery.ts

import * as functions from "firebase-functions";
import { BigQuery } from "@google-cloud/bigquery";

const bigquery = new BigQuery();

export const aggregateMetricsToBigQuery = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async (context) => {
    const now = new Date();
    const oneMinuteAgo = new Date(now.getTime() - 60000);
    
    // Aggregate errors from last minute
    const errorsSnap = await admin.firestore()
      .collection("error_logs")
      .where("timestamp", ">=", oneMinuteAgo)
      .where("timestamp", "<", now)
      .get();
    
    const errorsByService = new Map<string, number>();
    errorsSnap.docs.forEach((doc) => {
      const data = doc.data();
      const service = data.service || "unknown";
      errorsByService.set(service, (errorsByService.get(service) || 0) + 1);
    });
    
    // Insert into BigQuery
    const rows = Array.from(errorsByService.entries()).map(
      ([service, count]) => ({
        timestamp: now.toISOString(),
        error_type: "runtime_error",
        service,
        count,
      })
    );
    
    if (rows.length > 0) {
      await bigquery
        .dataset("analytics")
        .table("errors")
        .insert(rows);
    }
    
    // Aggregate business metrics (daily)
    if (now.getHours() === 0 && now.getMinutes() === 0) {
      await aggregateDailyBusinessMetrics(now);
    }
    
    return null;
  });

async function aggregateDailyBusinessMetrics(now: Date): Promise<void> {
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  
  // Revenue
  const earningsSnap = await admin.firestore()
    .collection("platform_earnings")
    .where("date", ">=", yesterday)
    .where("date", "<", now)
    .get();
  const revenue = earningsSnap.docs.reduce(
    (sum, doc) => sum + (doc.data().amount || 0), 0
  );
  
  // Bookings
  const bookingsSnap = await admin.firestore()
    .collection("jobs")
    .where("createdAt", ">=", yesterday)
    .where("createdAt", "<", now)
    .count()
    .get();
  
  // Insert to BigQuery
  await bigquery
    .dataset("analytics")
    .table("business_metrics")
    .insert([{
      date: yesterday.toISOString().split("T")[0],
      revenue,
      bookings: bookingsSnap.data().count,
      new_users: 0, // Calculate similarly
      churn: 0,
    }]);
}
```

### Step 5: Update Dashboard to Read from BigQuery

```typescript
// functions/src/dashboard/fetchMetrics.ts

export const fetchDashboardMetrics = functions.https.onCall(async (data) => {
  const { timeRange } = data; // "1h" | "24h" | "7d" | "30d"
  
  // Use cache first (Redis from Milestone 2)
  const cacheKey = `dashboard:metrics:${timeRange}`;
  
  return cacheGet(cacheKey, 60, async () => {
    // Query BigQuery instead of Firestore!
    const query = `
      SELECT 
        TIMESTAMP_TRUNC(timestamp, MINUTE) as bucket,
        metric_name,
        AVG(value) as avg_value,
        APPROX_QUANTILES(value, 100)[OFFSET(95)] as p95
      FROM \`anyskill.analytics.metrics_1min\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      GROUP BY bucket, metric_name
      ORDER BY bucket DESC
      LIMIT 1000
    `;
    
    const [rows] = await bigquery.query({ query });
    return rows;
  });
});
```

### Step 6: Create Materialized Views

```sql
-- Run in BigQuery console
CREATE MATERIALIZED VIEW anyskill.analytics.dashboard_summary AS
SELECT 
  DATE(timestamp) as date,
  metric_name,
  AVG(value) as avg_value,
  MAX(value) as max_value,
  COUNT(*) as data_points
FROM `anyskill.analytics.metrics_1min`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date, metric_name;
```

### Step 7: Update Flutter Dashboard

Update all widgets that showed loading spinners from Milestone 1 to now show real data:

```dart
class GoldenSignalsWidget extends StatelessWidget {
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: FirebaseFunctions.instance
        .httpsCallable('fetchDashboardMetrics')
        .call({'timeRange': '1h'}),
      builder: (ctx, snap) {
        if (!snap.hasData) return LoadingCard();
        
        final data = snap.data!.data;
        return Row(
          children: [
            LatencyGauge(p95: data['latency_p95']),
            TrafficChart(data: data['traffic_per_minute']),
            ErrorRateCard(rate: data['error_rate']),
            SaturationBars(cpu: data['cpu'], memory: data['memory']),
          ],
        );
      },
    );
  }
}
```

---

## ✅ ACCEPTANCE CRITERIA

- [ ] BigQuery dataset + 7 tables created
- [ ] Pub/Sub topics working
- [ ] Aggregation function running every minute
- [ ] Dashboard reads from BigQuery (not Firestore)
- [ ] Dashboard load time < 500ms
- [ ] Materialized views created
- [ ] Cost increase within estimate ($30-100/mo)

---

## 📝 UPDATE CURRENT_STATUS.md

```yaml
active_milestone: 3
status: "completed"
has_bigquery_pipeline: true
dashboard_load_time_ms: 200  # new reduced value

next_milestone: 4
next_milestone_trigger: "DAU > 500K OR writes > 8K/sec"
```

---

**Cost impact:** +$30-100/month  
**Benefit:** Dashboard loads in <500ms at any scale  
**Next:** Milestone 4 when write pressure grows
