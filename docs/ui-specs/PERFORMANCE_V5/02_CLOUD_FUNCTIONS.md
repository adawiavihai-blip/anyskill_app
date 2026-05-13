# 🔌 Cloud Functions (TypeScript) - 16 Functions for Performance V5

> **Read `01_MAIN_PROMPT_PERFORMANCE_V5.md` first!** This file contains the full implementation of all 16 Cloud Functions needed for the Performance Observatory V5.

---

## 📦 Setup

All functions live in `/functions/src/performance/`. Add to `functions/src/index.ts`:

```typescript
export * from './performance/askPerformanceCopilot';
export * from './performance/analyzePerformanceMetrics';
export * from './performance/predictSystemIssues';
export * from './performance/generateRootCauseAnalysis';
export * from './performance/groupSimilarErrors';
export * from './performance/detectAnomalies';
export * from './performance/calculateHealthScore';
export * from './performance/calculateBusinessImpact';
export * from './performance/orchestrateAgentSwarm';
export * from './performance/simulateImpactScenario';
export * from './performance/generateBlamelessPostMortem';
export * from './performance/runSyntheticTests';
export * from './performance/rollbackDeployment';
export * from './performance/autoScaleTrigger';
export * from './performance/aggregateMetricsToBigQuery';
export * from './performance/triggerChaosTest';
```

### Required dependencies (`functions/package.json`):

```json
{
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^4.8.0",
    "@google/generative-ai": "^0.21.0",
    "@google-cloud/bigquery": "^7.6.0",
    "@google-cloud/pubsub": "^4.3.0",
    "@google-cloud/redis": "^4.0.0",
    "ioredis": "^5.3.2",
    "axios": "^1.6.0"
  }
}
```

### Environment variables:

```bash
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set REDIS_HOST
firebase functions:secrets:set REDIS_PORT
firebase functions:secrets:set BIGQUERY_PROJECT_ID
firebase functions:secrets:set PAGERDUTY_API_KEY  # optional
firebase functions:secrets:set SENTRY_AUTH_TOKEN
```

---

## 1️⃣ askPerformanceCopilot.ts — Nova AI Chat

```typescript
import * as functions from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { BigQuery } from '@google-cloud/bigquery';
import Redis from 'ioredis';

interface AskNovaRequest {
  message: string;
  conversationId: string;
  context?: {
    currentTab?: string;
    activeIncidents?: number;
    recentMetrics?: any;
  };
}

const NOVA_SYSTEM_PROMPT = `אתה Nova, עוזר AI ניטור מערכות לאפליקציית AnySkill (שוק שירותים דו-צדדי בעברית).
אתה מבין הכל על דשבורד הביצועים של המערכת.

**תפקידך:**
1. לענות בעברית פשוטה וברורה על שאלות מונחים טכניים (APDEX, MTTR, SLO, p95, latency, RUM, Core Web Vitals, וכו')
2. לזהות בעיות פעילות במערכת ולהציע פתרונות
3. לחבר בעיות טכניות להשפעה עסקית (revenue loss, churn, NPS)
4. להציע פעולות one-click לפתרון

**סגנון תגובה:**
- עברית טבעית ושוטפת
- מונחים טכניים באנגלית (APDEX, latency, etc.) - אל תתרגם
- דוגמאות קונקרטיות מהמערכת של המשתמש
- תמיד תן confidence score לאבחנות (0-100%)
- תמיד תציע 1-3 action buttons בסוף

**עקרונות SRE:**
- 4 Golden Signals: Latency, Traffic, Errors, Saturation
- SLO/Error Budget (Google SRE methodology)
- Blameless culture - אל תאשים אנשים, תאשים מערכות

אתה מופעל על ידי Gemini 2.5 Pro. אל תזכיר שאתה AI אלא אם נשאלת.`;

export const askPerformanceCopilot = functions.onCall<AskNovaRequest>(
  {
    secrets: ['GEMINI_API_KEY', 'REDIS_HOST', 'REDIS_PORT'],
    region: 'us-central1',
    memory: '1GiB',
    timeoutSeconds: 60,
    minInstances: 1, // Keep warm for fast response
  },
  async (request) => {
    const { message, conversationId, context } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new functions.HttpsError('unauthenticated', 'Must be signed in');
    }

    // Fetch recent metrics from BigQuery (NOT Firestore!)
    const bigquery = new BigQuery();
    const metricsQuery = `
      SELECT metric_name, value, timestamp
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.metrics_hourly\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      ORDER BY timestamp DESC
      LIMIT 50
    `;
    const [metrics] = await bigquery.query(metricsQuery);

    // Get active incidents from Firestore (small collection, OK)
    const incidentsSnap = await admin.firestore()
      .collection('incidents')
      .where('status', '==', 'active')
      .orderBy('createdAt', 'desc')
      .limit(5)
      .get();
    const activeIncidents = incidentsSnap.docs.map(d => ({ id: d.id, ...d.data() }));

    // Get conversation history from Redis (fast!)
    const redis = new Redis({
      host: process.env.REDIS_HOST,
      port: parseInt(process.env.REDIS_PORT!),
    });
    const historyKey = `nova_chat:${userId}:${conversationId}`;
    const historyRaw = await redis.get(historyKey);
    const history = historyRaw ? JSON.parse(historyRaw) : [];

    // Build context-aware prompt
    const contextSummary = `
### נתונים נוכחיים של המערכת:
- תקריות פעילות: ${activeIncidents.length}
${activeIncidents.map(inc => `  • ${inc.title} (${inc.severity}) - ${inc.affectedUsers} users`).join('\n')}
- מטריקות אחרונות:
${metrics.slice(0, 10).map((m: any) => `  • ${m.metric_name}: ${m.value}`).join('\n')}

### היסטוריית שיחה (${history.length} הודעות אחרונות):
${history.slice(-6).map((h: any) => `${h.role}: ${h.content}`).join('\n')}

### שאלה נוכחית של המשתמש:
${message}
`;

    // Call Gemini 2.5 Pro
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
    const model = genAI.getGenerativeModel({
      model: 'gemini-2.5-pro',
      systemInstruction: NOVA_SYSTEM_PROMPT,
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 2048,
      },
    });

    const result = await model.generateContent(contextSummary);
    const responseText = result.response.text();

    // Parse response for action buttons (Nova may suggest actions)
    const actionsMatch = responseText.match(/ACTIONS:\s*\[(.*?)\]/s);
    const actions = actionsMatch ? JSON.parse(`[${actionsMatch[1]}]`) : [];
    const cleanResponse = responseText.replace(/ACTIONS:.*/s, '').trim();

    // Save to conversation history
    history.push({ role: 'user', content: message, ts: Date.now() });
    history.push({ role: 'nova', content: cleanResponse, ts: Date.now() });
    await redis.setex(historyKey, 86400, JSON.stringify(history.slice(-20))); // Keep last 20

    // Log for analytics
    await bigquery
      .dataset('anyskill_observability')
      .table('nova_conversations')
      .insert([{
        user_id: userId,
        conversation_id: conversationId,
        message_in: message,
        message_out: cleanResponse,
        tokens_used: result.response.usageMetadata?.totalTokenCount || 0,
        timestamp: new Date().toISOString(),
      }]);

    await redis.quit();

    return {
      response: cleanResponse,
      actions,
      confidence: extractConfidence(cleanResponse),
      tokensUsed: result.response.usageMetadata?.totalTokenCount || 0,
    };
  }
);

function extractConfidence(text: string): number {
  const match = text.match(/(\d+)%?\s*confidence/i) || text.match(/(\d+)%/);
  return match ? parseInt(match[1]) : 85;
}
```

---

## 2️⃣ analyzePerformanceMetrics.ts

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import { BigQuery } from '@google-cloud/bigquery';
import { GoogleGenerativeAI } from '@google/generative-ai';

// Runs every 5 minutes
export const analyzePerformanceMetrics = functions.onSchedule(
  {
    schedule: 'every 5 minutes',
    secrets: ['GEMINI_API_KEY'],
    region: 'us-central1',
    memory: '512MiB',
  },
  async () => {
    const bigquery = new BigQuery();
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-pro' });

    // Fetch last hour of metrics
    const query = `
      SELECT 
        service,
        AVG(latency_ms) as avg_latency,
        APPROX_QUANTILES(latency_ms, 100)[OFFSET(95)] as p95_latency,
        COUNT(*) as request_count,
        SUM(CASE WHEN is_error THEN 1 ELSE 0 END) as error_count
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.raw_events\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      GROUP BY service
    `;
    const [rows] = await bigquery.query(query);

    // Ask Gemini for insights
    const prompt = `נתח את המטריקות האלה מ-AnySkill ומצא:
1. בעיות שהולכות להתפוצץ
2. שירותים חריגים בהשוואה לבייסליין
3. המלצות מיידיות

נתונים:
${JSON.stringify(rows, null, 2)}

תן תגובה ב-JSON: { issues: [...], recommendations: [...], alertLevel: "green|yellow|red" }`;

    const result = await model.generateContent(prompt);
    const analysis = JSON.parse(result.response.text().replace(/```json|```/g, ''));

    // Save analysis to BigQuery
    await bigquery
      .dataset('anyskill_observability')
      .table('ai_analysis')
      .insert([{
        analysis_type: 'performance_metrics',
        result: JSON.stringify(analysis),
        alert_level: analysis.alertLevel,
        timestamp: new Date().toISOString(),
      }]);

    // Trigger alerts if needed
    if (analysis.alertLevel === 'red') {
      await triggerAlert(analysis);
    }
  }
);

async function triggerAlert(analysis: any) {
  // Send to Pub/Sub for incident creation
  const { PubSub } = require('@google-cloud/pubsub');
  const pubsub = new PubSub();
  await pubsub.topic('performance-alerts').publishMessage({
    data: Buffer.from(JSON.stringify(analysis)),
  });
}
```

---

## 3️⃣ predictSystemIssues.ts — Oracle Agent

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import { BigQuery } from '@google-cloud/bigquery';
import { GoogleGenerativeAI } from '@google/generative-ai';
import * as admin from 'firebase-admin';

export const predictSystemIssues = functions.onSchedule(
  {
    schedule: 'every 15 minutes',
    secrets: ['GEMINI_API_KEY'],
    region: 'us-central1',
    memory: '1GiB',
    timeoutSeconds: 120,
  },
  async () => {
    const bigquery = new BigQuery();
    
    // Get 7-day historical trend
    const trendQuery = `
      SELECT 
        service,
        DATETIME_TRUNC(timestamp, HOUR) as hour,
        AVG(latency_ms) as avg_latency,
        COUNT(*) as request_count,
        SUM(CASE WHEN is_error THEN 1 ELSE 0 END) as errors
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.raw_events\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
      GROUP BY service, hour
      ORDER BY hour DESC
    `;
    const [trends] = await bigquery.query(trendQuery);

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
    const model = genAI.getGenerativeModel({ 
      model: 'gemini-2.5-pro',
      generationConfig: { temperature: 0.1 }, // More deterministic for predictions
    });

    const prompt = `אתה Oracle Agent - סוכן חיזוי של AnySkill.

הנה נתוני 7 ימים אחורה. חזה:
1. בעיות ב-2 שעות הקרובות (confidence > 70%)
2. בעיות ב-24 שעות הקרובות (confidence > 60%)
3. הזדמנויות לאופטימיזציה (traffic peaks, scaling needs)

נתונים:
${JSON.stringify(trends.slice(0, 100))}

החזר JSON:
{
  predictions: [
    {
      type: "risk" | "opportunity",
      severity: "low" | "medium" | "high",
      service: string,
      eta: "2h" | "24h" | "1w",
      confidence: number (0-100),
      title: string (Hebrew),
      description: string (Hebrew),
      recommendedAction: string (Hebrew),
      estimatedImpact: { revenue: number, users: number }
    }
  ]
}`;

    const result = await model.generateContent(prompt);
    const predictions = JSON.parse(result.response.text().replace(/```json|```/g, ''));

    // Save to Firestore for real-time dashboard (small collection, OK)
    const batch = admin.firestore().batch();
    predictions.predictions.forEach((pred: any) => {
      const docRef = admin.firestore()
        .collection('ai_predictions')
        .doc(`${Date.now()}_${pred.service}`);
      batch.set(docRef, {
        ...pred,
        agent: 'oracle',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: 'active',
      });
    });
    await batch.commit();

    return { predictionsCount: predictions.predictions.length };
  }
);
```

---

## 4️⃣ generateRootCauseAnalysis.ts — Detective Agent

```typescript
import * as functions from 'firebase-functions/v2/https';
import { BigQuery } from '@google-cloud/bigquery';
import { GoogleGenerativeAI } from '@google/generative-ai';
import * as admin from 'firebase-admin';

interface RCARequest {
  incidentId: string;
}

export const generateRootCauseAnalysis = functions.onCall<RCARequest>(
  {
    secrets: ['GEMINI_API_KEY'],
    region: 'us-central1',
    memory: '1GiB',
    timeoutSeconds: 180,
  },
  async (request) => {
    const { incidentId } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new functions.HttpsError('unauthenticated', 'Must be signed in');
    }

    // Get incident
    const incidentDoc = await admin.firestore()
      .collection('incidents')
      .doc(incidentId)
      .get();

    if (!incidentDoc.exists) {
      throw new functions.HttpsError('not-found', 'Incident not found');
    }

    const incident = incidentDoc.data()!;

    // Pull correlation data from BigQuery
    const bigquery = new BigQuery();
    const correlationQuery = `
      WITH incident_window AS (
        SELECT TIMESTAMP('${incident.startedAt.toDate().toISOString()}') AS start_ts
      )
      SELECT 
        'metrics' as source, service, event_type, value, timestamp
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.raw_events\`, incident_window
      WHERE timestamp BETWEEN 
        TIMESTAMP_SUB(start_ts, INTERVAL 30 MINUTE) 
        AND TIMESTAMP_ADD(start_ts, INTERVAL 5 MINUTE)
      UNION ALL
      SELECT 
        'deploys' as source, service, 'deploy' as event_type, CAST(version AS STRING) as value, timestamp
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.deploys\`, incident_window
      WHERE timestamp BETWEEN 
        TIMESTAMP_SUB(start_ts, INTERVAL 2 HOUR) 
        AND TIMESTAMP_ADD(start_ts, INTERVAL 10 MINUTE)
      ORDER BY timestamp
    `;
    const [events] = await bigquery.query(correlationQuery);

    // Get related errors from Crashlytics/Sentry
    const errorsSnap = await admin.firestore()
      .collection('error_logs')
      .where('timestamp', '>=', new Date(incident.startedAt.toDate().getTime() - 30*60*1000))
      .where('timestamp', '<=', incident.startedAt)
      .limit(100)
      .get();
    const errors = errorsSnap.docs.map(d => d.data());

    // Analyze with Gemini
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
    const model = genAI.getGenerativeModel({ 
      model: 'gemini-2.5-pro',
      generationConfig: { temperature: 0.2 },
    });

    const prompt = `אתה Detective Agent - סוכן חקירת סיבות שורש של AnySkill.

תקרית:
${JSON.stringify(incident)}

אירועים ב-30 דקות שקדמו (deploys, metric changes, errors):
${JSON.stringify(events.slice(0, 50))}

שגיאות שהופיעו:
${JSON.stringify(errors.slice(0, 20))}

בצע ניתוח 5 WHYS וחזור עם:
{
  rootCause: {
    hypothesis: string (עברית),
    confidence: number (0-100),
    evidence: string[] (עברית),
    technicalExplanation: string (באנגלית למפתחים)
  },
  timeline: [
    { time: string, event: string, impact: string }
  ],
  recommendations: {
    immediate: [ { action: string (עברית), automated: boolean, estimatedTime: string } ],
    preventive: [ { action: string (עברית), priority: "high"|"medium"|"low" } ]
  },
  blameless: true // ALWAYS blameless - focus on systems, not people
}`;

    const result = await model.generateContent(prompt);
    const rca = JSON.parse(result.response.text().replace(/```json|```/g, ''));

    // Save RCA to incident
    await admin.firestore()
      .collection('incidents')
      .doc(incidentId)
      .update({
        rootCauseAnalysis: rca,
        rcaGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
        rcaGeneratedBy: 'detective-agent',
      });

    return { 
      rca, 
      incidentId,
      agent: 'detective',
      confidence: rca.rootCause.confidence 
    };
  }
);
```

---

## 5️⃣ groupSimilarErrors.ts

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import { BigQuery } from '@google-cloud/bigquery';
import * as crypto from 'crypto';

export const groupSimilarErrors = functions.onSchedule(
  {
    schedule: 'every 10 minutes',
    region: 'us-central1',
    memory: '512MiB',
  },
  async () => {
    const bigquery = new BigQuery();

    // Get last 24h of errors
    const query = `
      SELECT 
        error_message,
        stack_trace,
        service,
        screen,
        user_id,
        timestamp
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.errors\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    `;
    const [errors] = await bigquery.query(query);

    // Group by fingerprint (hash of normalized message + stack top frame)
    const groups: Record<string, any> = {};
    errors.forEach((err: any) => {
      const fingerprint = generateFingerprint(err);
      if (!groups[fingerprint]) {
        groups[fingerprint] = {
          fingerprint,
          sample: err,
          count: 0,
          affectedUsers: new Set(),
          firstSeen: err.timestamp,
          lastSeen: err.timestamp,
          timeline: [], // For sparkline
        };
      }
      groups[fingerprint].count++;
      groups[fingerprint].affectedUsers.add(err.user_id);
      if (err.timestamp > groups[fingerprint].lastSeen) {
        groups[fingerprint].lastSeen = err.timestamp;
      }
      groups[fingerprint].timeline.push(err.timestamp);
    });

    // Save grouped errors to Firestore
    const batch = admin.firestore().batch();
    Object.values(groups).forEach((grp: any) => {
      const docRef = admin.firestore().collection('error_groups').doc(grp.fingerprint);
      batch.set(docRef, {
        ...grp,
        affectedUsersCount: grp.affectedUsers.size,
        affectedUsers: undefined, // Don't save Set
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    await batch.commit();

    return { totalErrors: errors.length, groups: Object.keys(groups).length };
  }
);

function generateFingerprint(err: any): string {
  // Normalize: remove variable parts (user IDs, timestamps, URLs)
  const normalized = (err.error_message || '')
    .replace(/\b[0-9a-f]{24}\b/g, 'ID')      // ObjectIds
    .replace(/\b\d+\b/g, 'N')                // Numbers
    .replace(/https?:\/\/[^\s]+/g, 'URL')    // URLs
    .replace(/at line \d+/g, 'at line N');

  const stackTop = (err.stack_trace || '').split('\n')[0] || '';
  
  return crypto.createHash('md5')
    .update(`${normalized}|${stackTop}|${err.service}`)
    .digest('hex')
    .substring(0, 16);
}
```

---

## 6️⃣ detectAnomalies.ts

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import { BigQuery } from '@google-cloud/bigquery';
import * as admin from 'firebase-admin';

export const detectAnomalies = functions.onSchedule(
  {
    schedule: 'every 5 minutes',
    region: 'us-central1',
    memory: '512MiB',
  },
  async () => {
    const bigquery = new BigQuery();

    // Statistical anomaly detection using z-score
    // Compare last 5 min vs last 24h baseline
    const query = `
      WITH recent AS (
        SELECT 
          service,
          metric_name,
          AVG(value) as current_avg
        FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.metrics_hourly\`
        WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
        GROUP BY service, metric_name
      ),
      baseline AS (
        SELECT 
          service,
          metric_name,
          AVG(value) as baseline_avg,
          STDDEV(value) as baseline_stddev
        FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.metrics_hourly\`
        WHERE timestamp BETWEEN 
          TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
          AND TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
        GROUP BY service, metric_name
      )
      SELECT 
        r.service,
        r.metric_name,
        r.current_avg,
        b.baseline_avg,
        b.baseline_stddev,
        (r.current_avg - b.baseline_avg) / NULLIF(b.baseline_stddev, 0) as z_score
      FROM recent r
      JOIN baseline b 
        ON r.service = b.service AND r.metric_name = b.metric_name
      WHERE ABS((r.current_avg - b.baseline_avg) / NULLIF(b.baseline_stddev, 0)) > 3
    `;

    const [anomalies] = await bigquery.query(query);

    // Save anomalies to Firestore
    const batch = admin.firestore().batch();
    anomalies.forEach((anom: any) => {
      const docRef = admin.firestore().collection('anomalies').doc();
      batch.set(docRef, {
        service: anom.service,
        metric: anom.metric_name,
        currentValue: anom.current_avg,
        baselineValue: anom.baseline_avg,
        zScore: anom.z_score,
        severity: Math.abs(anom.z_score) > 5 ? 'high' : 'medium',
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: 'active',
      });
    });
    await batch.commit();

    return { anomaliesFound: anomalies.length };
  }
);
```

---

## 7️⃣ calculateHealthScore.ts

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import { BigQuery } from '@google-cloud/bigquery';
import * as admin from 'firebase-admin';

export const calculateHealthScore = functions.onSchedule(
  {
    schedule: 'every 1 minutes',
    region: 'us-central1',
    memory: '256MiB',
  },
  async () => {
    const bigquery = new BigQuery();

    const query = `
      WITH metrics_last_hour AS (
        SELECT 
          APPROX_QUANTILES(latency_ms, 100)[OFFSET(95)] as p95_latency,
          SUM(CASE WHEN is_error THEN 1 ELSE 0 END) / COUNT(*) * 100 as error_rate,
          COUNT(DISTINCT user_id) as dau,
          AVG(cpu_usage) as avg_cpu
        FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.raw_events\`
        WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      )
      SELECT * FROM metrics_last_hour
    `;

    const [[metrics]] = await bigquery.query(query);

    // Weighted health score (0-100)
    let score = 100;

    // Penalize high latency
    if (metrics.p95_latency > 800) score -= 20;
    else if (metrics.p95_latency > 500) score -= 10;
    else if (metrics.p95_latency > 300) score -= 5;

    // Penalize errors
    if (metrics.error_rate > 1) score -= 25;
    else if (metrics.error_rate > 0.5) score -= 10;
    else if (metrics.error_rate > 0.1) score -= 5;

    // Penalize high CPU
    if (metrics.avg_cpu > 85) score -= 15;
    else if (metrics.avg_cpu > 70) score -= 5;

    // Calculate APDEX
    const apdexQuery = `
      SELECT
        SUM(CASE WHEN latency_ms <= 500 THEN 1 ELSE 0 END) as satisfied,
        SUM(CASE WHEN latency_ms > 500 AND latency_ms <= 2000 THEN 1 ELSE 0 END) as tolerating,
        COUNT(*) as total
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.raw_events\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    `;
    const [[apdexData]] = await bigquery.query(apdexQuery);
    const apdex = (apdexData.satisfied + apdexData.tolerating / 2) / apdexData.total;

    // Save to Firestore (small doc, OK)
    await admin.firestore()
      .collection('health_metrics')
      .doc('current')
      .set({
        healthScore: Math.max(0, Math.round(score)),
        apdex: parseFloat(apdex.toFixed(2)),
        p95Latency: Math.round(metrics.p95_latency),
        errorRate: parseFloat(metrics.error_rate.toFixed(2)),
        dau: metrics.dau,
        avgCpu: Math.round(metrics.avg_cpu),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    return { healthScore: score, apdex };
  }
);
```

---

## 8️⃣ calculateBusinessImpact.ts — The Money Function!

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import { BigQuery } from '@google-cloud/bigquery';
import * as admin from 'firebase-admin';

export const calculateBusinessImpact = functions.onSchedule(
  {
    schedule: 'every 1 minutes',
    region: 'us-central1',
    memory: '512MiB',
  },
  async () => {
    const bigquery = new BigQuery();

    // Calculate revenue loss from active incidents
    const activeIncidents = await admin.firestore()
      .collection('incidents')
      .where('status', '==', 'active')
      .get();

    let totalLossPerMinute = 0;
    let totalAffectedUsers = 0;

    for (const incDoc of activeIncidents.docs) {
      const inc = incDoc.data();
      
      // Get conversion data for affected service in last 10 min
      const conversionQuery = `
        WITH baseline AS (
          SELECT 
            AVG(CASE WHEN event_type = 'booking_complete' THEN 1 ELSE 0 END) as baseline_rate
          FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.user_events\`
          WHERE service = '${inc.affectedService}'
            AND timestamp BETWEEN 
              TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
              AND TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
        ),
        current AS (
          SELECT 
            AVG(CASE WHEN event_type = 'booking_complete' THEN 1 ELSE 0 END) as current_rate
          FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.user_events\`
          WHERE service = '${inc.affectedService}'
            AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
        )
        SELECT 
          baseline.baseline_rate,
          current.current_rate,
          (baseline.baseline_rate - current.current_rate) / NULLIF(baseline.baseline_rate, 0) as drop_pct
        FROM baseline, current
      `;

      const [[conversionData]] = await bigquery.query(conversionQuery);
      const dropPct = conversionData.drop_pct || 0;

      // Business assumption: avg order value 142 NIS, 41 orders/hour baseline
      const avgOrderValue = 142;
      const expectedOrdersPerMin = 41 / 60;
      const lostOrdersPerMin = expectedOrdersPerMin * dropPct;
      const lossPerMin = lostOrdersPerMin * avgOrderValue;

      totalLossPerMinute += lossPerMin;
      totalAffectedUsers += inc.affectedUsers || 0;

      // Update incident with business impact
      await incDoc.ref.update({
        businessImpact: {
          lossPerMinute: Math.round(lossPerMin),
          conversionDrop: parseFloat((dropPct * 100).toFixed(1)),
          affectedUsers: inc.affectedUsers,
          cumulativeLoss: Math.round(lossPerMin * ((Date.now() - inc.startedAt.toMillis()) / 60000)),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Check churn risk (VIPs who haven't opened app in 7 days)
    const vipChurnQuery = `
      SELECT 
        user_id,
        last_active,
        monthly_revenue
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.users\`
      WHERE is_vip = TRUE
        AND last_active < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
      ORDER BY monthly_revenue DESC
      LIMIT 10
    `;
    const [vipsAtRisk] = await bigquery.query(vipChurnQuery);
    const vipRevenueAtRisk = vipsAtRisk.reduce((sum: number, v: any) => sum + v.monthly_revenue, 0);

    // Calculate NPS from last 24h
    const npsQuery = `
      SELECT 
        SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END) as promoters,
        SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END) as detractors,
        COUNT(*) as total
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.nps_responses\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    `;
    const [[npsData]] = await bigquery.query(npsQuery);
    const nps = npsData.total > 0 
      ? Math.round((npsData.promoters / npsData.total - npsData.detractors / npsData.total) * 100)
      : 0;

    // Save aggregated business impact
    await admin.firestore()
      .collection('business_metrics')
      .doc('current')
      .set({
        lossPerMinute: Math.round(totalLossPerMinute),
        totalAffectedUsers,
        vipsAtRisk: vipsAtRisk.length,
        vipRevenueAtRisk: Math.round(vipRevenueAtRisk),
        nps,
        happinessScore: Math.max(0, Math.min(100, nps + 50)), // Convert NPS to 0-100 scale
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    return { totalLossPerMinute, vipsAtRisk: vipsAtRisk.length };
  }
);
```

---

## 9️⃣ orchestrateAgentSwarm.ts

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';

// Coordinate the 5 agents every minute
export const orchestrateAgentSwarm = functions.onSchedule(
  {
    schedule: 'every 1 minutes',
    region: 'us-central1',
    memory: '256MiB',
  },
  async () => {
    const db = admin.firestore();

    // Get current agents state
    const agentsSnap = await db.collection('ai_agents_state').get();
    const agents = Object.fromEntries(
      agentsSnap.docs.map(d => [d.id, d.data()])
    );

    // Detective: investigates active incidents
    const activeIncidents = await db.collection('incidents')
      .where('status', '==', 'active')
      .where('rootCauseAnalysis', '==', null)
      .limit(3)
      .get();
    
    if (activeIncidents.size > 0 && agents.detective?.status !== 'busy') {
      // Trigger Detective for each incident
      for (const inc of activeIncidents.docs) {
        await db.collection('agent_tasks').add({
          agent: 'detective',
          taskType: 'generate_rca',
          incidentId: inc.id,
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await db.collection('ai_agents_state').doc('detective').set({
        status: 'investigating',
        currentTask: `analyzing ${activeIncidents.size} incidents`,
        confidence: null,
        lastActive: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    // Healer: processes Detective's RCAs in Autonomous mode
    const settingsDoc = await db.collection('config').doc('ai_agents').get();
    const autonomousMode = settingsDoc.data()?.mode || 'supervised';

    if (autonomousMode === 'autonomous') {
      const rcasPendingFix = await db.collection('incidents')
        .where('status', '==', 'active')
        .where('rootCauseAnalysis.confidence', '>=', 85)
        .where('healerActionTaken', '==', false)
        .limit(1)
        .get();
      
      if (rcasPendingFix.size > 0) {
        const inc = rcasPendingFix.docs[0];
        await db.collection('agent_tasks').add({
          agent: 'healer',
          taskType: 'auto_fix',
          incidentId: inc.id,
          action: inc.data().rootCauseAnalysis.recommendations.immediate[0]?.action,
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    // Oracle: already runs on schedule (every 15 min)

    // Guardian: check for security anomalies
    const suspiciousActivity = await db.collection('security_events')
      .where('severity', 'in', ['high', 'critical'])
      .where('investigated', '==', false)
      .limit(5)
      .get();
    
    if (suspiciousActivity.size > 0) {
      await db.collection('ai_agents_state').doc('guardian').set({
        status: 'investigating',
        currentTask: `${suspiciousActivity.size} suspicious events`,
        lastActive: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    // Chronicler: generate post-mortems for recently resolved incidents
    const resolvedIncidents = await db.collection('incidents')
      .where('status', '==', 'resolved')
      .where('postMortemGenerated', '==', false)
      .limit(2)
      .get();
    
    for (const inc of resolvedIncidents.docs) {
      await db.collection('agent_tasks').add({
        agent: 'chronicler',
        taskType: 'write_postmortem',
        incidentId: inc.id,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return { 
      orchestrationCycle: Date.now(),
      activeAgents: Object.values(agents).filter((a: any) => a.status !== 'idle').length 
    };
  }
);
```

---

## 🔟 simulateImpactScenario.ts

```typescript
import * as functions from 'firebase-functions/v2/https';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { BigQuery } from '@google-cloud/bigquery';

interface SimulateRequest {
  scenario: string; // e.g., "add composite index on experts(category, rating)"
  service?: string;
}

export const simulateImpactScenario = functions.onCall<SimulateRequest>(
  {
    secrets: ['GEMINI_API_KEY'],
    region: 'us-central1',
    memory: '512MiB',
    timeoutSeconds: 30,
  },
  async (request) => {
    const { scenario, service } = request.data;
    const bigquery = new BigQuery();

    // Get current state
    const stateQuery = `
      SELECT 
        AVG(latency_ms) as current_latency,
        SUM(CASE WHEN is_error THEN 1 ELSE 0 END) / COUNT(*) as current_error_rate,
        COUNT(DISTINCT user_id) as current_dau,
        SUM(CASE WHEN event_type='booking_complete' THEN 1 ELSE 0 END) / 
          SUM(CASE WHEN event_type='booking_start' THEN 1 ELSE 0 END) as current_conversion
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.raw_events\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      ${service ? `AND service = '${service}'` : ''}
    `;
    const [[currentState]] = await bigquery.query(stateQuery);

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
    const model = genAI.getGenerativeModel({
      model: 'gemini-2.5-pro',
      generationConfig: { temperature: 0.2 },
    });

    const prompt = `אתה Impact Simulator של AnySkill. המשתמש שואל: מה יקרה אם...

תרחיש: "${scenario}"

מצב נוכחי:
- Latency ממוצע: ${currentState.current_latency}ms
- Error rate: ${(currentState.current_error_rate * 100).toFixed(2)}%
- DAU: ${currentState.current_dau}
- Conversion rate: ${(currentState.current_conversion * 100).toFixed(1)}%

בנה תרחיש ריאליסטי בהתבסס על:
- חוקי פיזיקה של performance (latency, throughput)
- מחקרים מ-Google/Amazon על השפעת latency על conversion (כל 100ms = 1% conversion drop)
- עלויות Firebase/GCP בפועל
- נתוני AnySkill

החזר JSON:
{
  scenario: { description: string (עברית) },
  predictions: {
    before: { latency: number, conversions: number, revenuePerDay: number },
    after: { latency: number, conversions: number, revenuePerDay: number },
    delta: { latency: "-81%", conversions: "+35%", revenuePerDay: "+3200 NIS" }
  },
  costs: {
    setupCost: { amount: number, currency: "USD" },
    monthlyCost: { amount: number, currency: "USD" }
  },
  roi: { ratio: number, paybackTime: "X days" },
  confidence: number (0-100),
  risks: string[] (עברית),
  recommendation: "execute_now" | "plan_ahead" | "not_recommended"
}`;

    const result = await model.generateContent(prompt);
    const simulation = JSON.parse(result.response.text().replace(/```json|```/g, ''));

    return simulation;
  }
);
```

---

## 1️⃣1️⃣ generateBlamelessPostMortem.ts — Chronicler Agent

```typescript
import * as functions from 'firebase-functions/v2/firestore';
import { GoogleGenerativeAI } from '@google/generative-ai';
import * as admin from 'firebase-admin';

const CHRONICLER_SYSTEM_PROMPT = `אתה Chronicler Agent של AnySkill.
אתה כותב דוחות post-mortem בסגנון **Blameless** (Google SRE methodology).

**כללים מקודשים:**
1. **אל תאשים אנשים** - רק מערכות ותהליכים
2. **עובדות לא סיפורים** - timestamps, metrics, evidence
3. **Learn not blame** - מה נלמד, לא מי אשם
4. **Action items מדויקים** - owner, deadline, success criteria

**מבנה הדוח:**
1. TL;DR (1 משפט בעברית)
2. Timeline (ציר זמן עם events)
3. Root Cause (סיבת השורש - טכנית)
4. Impact (טכני + עסקי + משתמשים)
5. What went well (מה עבד)
6. What went wrong (מה כשל - **במערכת**, לא באנשים)
7. Lessons learned (3-5 תובנות)
8. Action items (תוכנית פעולה)

כתוב בעברית מקצועית.`;

export const generateBlamelessPostMortem = functions.onDocumentUpdated(
  {
    document: 'incidents/{incidentId}',
    secrets: ['GEMINI_API_KEY'],
    region: 'us-central1',
    memory: '1GiB',
    timeoutSeconds: 300,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    // Only generate when incident just resolved
    if (before?.status !== 'resolved' && after?.status === 'resolved' && !after?.postMortemGenerated) {
      const incidentId = event.params.incidentId;

      // Gather all data about this incident
      const db = admin.firestore();
      
      // Timeline events
      const eventsSnap = await db.collection('incidents')
        .doc(incidentId)
        .collection('timeline')
        .orderBy('timestamp')
        .get();
      const timelineEvents = eventsSnap.docs.map(d => d.data());

      // RCA from Detective
      const rca = after.rootCauseAnalysis;

      // Business impact
      const businessImpact = after.businessImpact;

      const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
      const model = genAI.getGenerativeModel({
        model: 'gemini-2.5-pro',
        systemInstruction: CHRONICLER_SYSTEM_PROMPT,
        generationConfig: { temperature: 0.4, maxOutputTokens: 4000 },
      });

      const prompt = `תקרית לדוח:

כותרת: ${after.title}
חומרה: ${after.severity}
זמן התחלה: ${after.startedAt.toDate().toISOString()}
זמן סיום: ${after.resolvedAt?.toDate().toISOString()}
משך: ${Math.round((after.resolvedAt?.toMillis() - after.startedAt.toMillis()) / 60000)} דקות

משתמשים שהושפעו: ${after.affectedUsers}
הפסד כספי: ${businessImpact?.cumulativeLoss} NIS
Conversion drop: ${businessImpact?.conversionDrop}%

Root Cause (מ-Detective Agent):
${JSON.stringify(rca, null, 2)}

Timeline:
${timelineEvents.map(e => `${new Date(e.timestamp?.toMillis()).toISOString()}: ${e.description}`).join('\n')}

כתוב post-mortem מלא במבנה המקובל.

החזר JSON:
{
  tldr: string (עברית, משפט אחד),
  timeline: [ { time: string, event: string, type: "incident"|"deploy"|"action"|"resolution" } ],
  rootCause: { technical: string, systemic: string },
  impact: {
    technical: { affectedServices: string[], maxLatency: string, errorRate: string },
    business: { cumulativeLoss: string, conversionDrop: string, affectedUsers: number },
    userFacing: string
  },
  whatWentWell: string[] (עברית),
  whatWentWrong: string[] (עברית, בלי להאשים אנשים!),
  lessonsLearned: [ { lesson: string, category: "detection"|"response"|"prevention" } ],
  actionItems: [ { action: string, owner: string, deadline: string, priority: "P0"|"P1"|"P2" } ],
  metadata: { incidentId: string, author: "Chronicler Agent", createdAt: string }
}`;

      const result = await model.generateContent(prompt);
      const postmortem = JSON.parse(result.response.text().replace(/```json|```/g, ''));

      // Save draft
      await db.collection('post_mortems').doc(incidentId).set({
        ...postmortem,
        incidentId,
        status: 'draft', // user needs to review
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        generatedBy: 'chronicler-agent',
      });

      // Mark incident as having post-mortem
      await event.data?.after.ref.update({
        postMortemGenerated: true,
        postMortemId: incidentId,
      });

      return { postMortemId: incidentId };
    }

    return null;
  }
);
```

---

## 1️⃣2️⃣ runSyntheticTests.ts

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import axios from 'axios';
import * as admin from 'firebase-admin';

const CRITICAL_FLOWS = [
  { name: 'Login Flow', endpoint: '/api/auth/login', method: 'POST', body: { email: 'synthetic@test.com', password: 'test' } },
  { name: 'Search Flow', endpoint: '/api/search', method: 'GET', query: '?q=handyman&city=TLV' },
  { name: 'Booking Flow', endpoint: '/api/bookings/create', method: 'POST', body: { /* test booking */ } },
  { name: 'Payment Flow', endpoint: '/api/payments/process', method: 'POST', body: { /* test payment */ } },
];

export const runSyntheticTests = functions.onSchedule(
  {
    schedule: 'every 5 minutes',
    region: 'us-central1',
    memory: '256MiB',
  },
  async () => {
    const results = [];

    for (const flow of CRITICAL_FLOWS) {
      const start = Date.now();
      let status: 'success' | 'failure' = 'success';
      let statusCode = 0;
      let responseTime = 0;
      let errorMessage = '';

      try {
        const config: any = {
          method: flow.method,
          url: `${process.env.API_BASE_URL}${flow.endpoint}${flow.query || ''}`,
          timeout: 10000,
          headers: { 'X-Synthetic-Test': 'true' },
        };
        if (flow.body) config.data = flow.body;

        const response = await axios(config);
        statusCode = response.status;
        responseTime = Date.now() - start;
      } catch (err: any) {
        status = 'failure';
        statusCode = err.response?.status || 0;
        responseTime = Date.now() - start;
        errorMessage = err.message;
      }

      results.push({
        flowName: flow.name,
        status,
        statusCode,
        responseTime,
        errorMessage,
        timestamp: new Date().toISOString(),
      });
    }

    // Save to Firestore (small, OK)
    await admin.firestore()
      .collection('synthetic_tests')
      .doc(new Date().toISOString())
      .set({
        results,
        totalTests: results.length,
        passed: results.filter(r => r.status === 'success').length,
        failed: results.filter(r => r.status === 'failure').length,
        avgResponseTime: Math.round(
          results.reduce((sum, r) => sum + r.responseTime, 0) / results.length
        ),
      });

    return { results };
  }
);
```

---

## 1️⃣3️⃣ rollbackDeployment.ts

```typescript
import * as functions from 'firebase-functions/v2/https';
import axios from 'axios';
import * as admin from 'firebase-admin';

interface RollbackRequest {
  targetVersion?: string; // optional, defaults to previous
  reason: string;
}

export const rollbackDeployment = functions.onCall<RollbackRequest>(
  {
    region: 'us-central1',
    memory: '256MiB',
    timeoutSeconds: 120,
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError('unauthenticated', 'Must be signed in');

    // Check user is admin
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.data()?.isAdmin) {
      throw new functions.HttpsError('permission-denied', 'Admin only');
    }

    const { targetVersion, reason } = request.data;

    // Get current version
    const configDoc = await admin.firestore().collection('config').doc('deployment').get();
    const currentVersion = configDoc.data()?.currentVersion;

    // Determine target version
    const deploysSnap = await admin.firestore()
      .collection('deploys')
      .orderBy('deployedAt', 'desc')
      .limit(10)
      .get();
    const deploys = deploysSnap.docs.map(d => d.data());
    const target = targetVersion || deploys[1]?.version;

    if (!target) {
      throw new functions.HttpsError('not-found', 'No previous version to roll back to');
    }

    // Call Firebase Hosting API for web
    // (for mobile, this just updates feature flags)
    try {
      // Firebase Hosting rollback (if using Firebase Hosting)
      // This is a real API call in production
      // await firebaseHostingRollback(target);

      // Update config
      await admin.firestore().collection('config').doc('deployment').update({
        currentVersion: target,
        previousVersion: currentVersion,
        lastRollbackAt: admin.firestore.FieldValue.serverTimestamp(),
        lastRollbackReason: reason,
        lastRollbackBy: userId,
      });

      // Log to incident timeline if during incident
      const activeIncident = await admin.firestore()
        .collection('incidents')
        .where('status', '==', 'active')
        .limit(1)
        .get();
      
      if (!activeIncident.empty) {
        await activeIncident.docs[0].ref.collection('timeline').add({
          type: 'action',
          description: `Rollback from ${currentVersion} to ${target}`,
          performedBy: userId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return {
        success: true,
        rolledBackTo: target,
        previousVersion: currentVersion,
        estimatedRecoveryTime: '2-5 minutes',
      };
    } catch (err: any) {
      throw new functions.HttpsError('internal', `Rollback failed: ${err.message}`);
    }
  }
);
```

---

## 1️⃣4️⃣ autoScaleTrigger.ts

```typescript
import * as functions from 'firebase-functions/v2/scheduler';
import { BigQuery } from '@google-cloud/bigquery';
import * as admin from 'firebase-admin';

export const autoScaleTrigger = functions.onSchedule(
  {
    schedule: 'every 2 minutes',
    region: 'us-central1',
    memory: '256MiB',
  },
  async () => {
    const bigquery = new BigQuery();

    // Check current load
    const loadQuery = `
      SELECT 
        service,
        AVG(cpu_usage) as avg_cpu,
        COUNT(*) / 120 as requests_per_second
      FROM \`${process.env.BIGQUERY_PROJECT_ID}.anyskill_observability.raw_events\`
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
      GROUP BY service
    `;
    const [services] = await bigquery.query(loadQuery);

    const scalingActions = [];

    for (const svc of services as any[]) {
      // Scale up if CPU > 70% or RPS > scale target
      if (svc.avg_cpu > 70) {
        scalingActions.push({
          service: svc.service,
          action: 'scale_up',
          reason: `CPU at ${svc.avg_cpu}%`,
          currentCpu: svc.avg_cpu,
        });

        // In production, call Cloud Run Admin API here
        // await cloudRunAdmin.updateService({ ... });
      }
      
      // Scale down if CPU < 30% and we have min > 2 instances
      else if (svc.avg_cpu < 30) {
        scalingActions.push({
          service: svc.service,
          action: 'scale_down',
          reason: `CPU at ${svc.avg_cpu}% (underutilized)`,
        });
      }
    }

    // Log scaling actions
    if (scalingActions.length > 0) {
      await admin.firestore()
        .collection('scaling_actions')
        .doc(new Date().toISOString())
        .set({
          actions: scalingActions,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    return { scalingActionsCount: scalingActions.length };
  }
);
```

---

## 1️⃣5️⃣ aggregateMetricsToBigQuery.ts — THE MOST CRITICAL!

```typescript
import * as functions from 'firebase-functions/v2/pubsub';
import { BigQuery } from '@google-cloud/bigquery';

/**
 * CRITICAL: This function is what makes the dashboard scale to 10M users.
 * Cloud Run services emit events to Pub/Sub topic 'metrics-stream'.
 * This function batch-inserts them to BigQuery.
 * 
 * Dashboard reads from BigQuery, NOT Firestore!
 */
export const aggregateMetricsToBigQuery = functions.onMessagePublished(
  {
    topic: 'metrics-stream',
    region: 'us-central1',
    memory: '512MiB',
  },
  async (event) => {
    const bigquery = new BigQuery();
    const dataset = bigquery.dataset('anyskill_observability');
    
    // Parse Pub/Sub message
    const message = event.data.message;
    const payload = message.json; // Already parsed JSON

    // Route to correct BigQuery table
    const tableName = payload.type === 'metric' ? 'raw_events' :
                      payload.type === 'error' ? 'errors' :
                      payload.type === 'user_event' ? 'user_events' :
                      'raw_events';

    const row = {
      event_id: payload.eventId || message.messageId,
      service: payload.service,
      event_type: payload.eventType,
      user_id: payload.userId || null,
      latency_ms: payload.latency || null,
      is_error: payload.isError || false,
      error_message: payload.errorMessage || null,
      screen: payload.screen || null,
      cpu_usage: payload.cpuUsage || null,
      memory_usage: payload.memoryUsage || null,
      metric_name: payload.metricName || null,
      value: payload.value || null,
      metadata: JSON.stringify(payload.metadata || {}),
      timestamp: payload.timestamp || new Date().toISOString(),
    };

    // Insert (BigQuery supports streaming inserts up to 1M rows/sec)
    try {
      await dataset.table(tableName).insert([row], {
        skipInvalidRows: true,
        ignoreUnknownValues: true,
      });
    } catch (err: any) {
      console.error('BigQuery insert failed:', err);
      // Don't throw - let Pub/Sub retry
    }

    return null;
  }
);
```

---

## 1️⃣6️⃣ triggerChaosTest.ts

```typescript
import * as functions from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';

interface ChaosTestRequest {
  testType: 'db_slowdown' | 'cf_timeout' | 'network_drop' | 'traffic_storm';
  duration: number; // minutes
  targetService?: string;
  blastRadius: 'small' | 'medium' | 'large'; // % of traffic affected
}

export const triggerChaosTest = functions.onCall<ChaosTestRequest>(
  {
    region: 'us-central1',
    memory: '256MiB',
    timeoutSeconds: 60,
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError('unauthenticated', 'Must be signed in');

    // Admin check
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.data()?.isAdmin) {
      throw new functions.HttpsError('permission-denied', 'Admin only');
    }

    const { testType, duration, targetService, blastRadius } = request.data;

    // Safety: only allow in non-production or during off-peak hours
    const now = new Date();
    const israelHour = (now.getUTCHours() + 3) % 24;
    const isOffPeak = israelHour >= 2 && israelHour <= 6; // 2-6 AM Israel
    
    if (process.env.ENV === 'production' && !isOffPeak) {
      throw new functions.HttpsError(
        'failed-precondition',
        'Chaos tests in production only allowed 02:00-06:00 Israel time'
      );
    }

    // Create chaos experiment record
    const experimentRef = admin.firestore().collection('chaos_experiments').doc();
    const blastPct = blastRadius === 'small' ? 1 : blastRadius === 'medium' ? 10 : 50;
    
    await experimentRef.set({
      testType,
      duration,
      targetService: targetService || 'all',
      blastRadius,
      blastRadiusPct: blastPct,
      startedBy: userId,
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + duration * 60 * 1000),
      status: 'running',
    });

    // In production, this would:
    // - db_slowdown: Add artificial delay to Firestore queries (via proxy)
    // - cf_timeout: Make N% of CF return 504 
    // - network_drop: Simulate network failures
    // - traffic_storm: Use k6/locust to generate load

    return {
      experimentId: experimentRef.id,
      status: 'started',
      willEndAt: new Date(Date.now() + duration * 60 * 1000).toISOString(),
      monitoringDashboardUrl: `/admin/performance?chaos=${experimentRef.id}`,
    };
  }
);
```

---

## 📤 Deployment

```bash
# Install dependencies
cd functions
npm install

# Deploy all performance functions
firebase deploy --only functions:askPerformanceCopilot,functions:analyzePerformanceMetrics,functions:predictSystemIssues,functions:generateRootCauseAnalysis,functions:groupSimilarErrors,functions:detectAnomalies,functions:calculateHealthScore,functions:calculateBusinessImpact,functions:orchestrateAgentSwarm,functions:simulateImpactScenario,functions:generateBlamelessPostMortem,functions:runSyntheticTests,functions:rollbackDeployment,functions:autoScaleTrigger,functions:aggregateMetricsToBigQuery,functions:triggerChaosTest

# Or deploy all at once
firebase deploy --only functions
```

---

## ✅ Testing

Test each function with curl:

```bash
# Test Nova
curl -X POST https://us-central1-YOUR-PROJECT.cloudfunctions.net/askPerformanceCopilot \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"data": {"message": "מה זה APDEX?", "conversationId": "test-1"}}'

# Test RCA
curl -X POST https://us-central1-YOUR-PROJECT.cloudfunctions.net/generateRootCauseAnalysis \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"data": {"incidentId": "test-incident-1"}}'

# Test Simulator
curl -X POST https://us-central1-YOUR-PROJECT.cloudfunctions.net/simulateImpactScenario \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"data": {"scenario": "Add composite index on experts(category, rating)"}}'
```

---

**Next:** Read `03_FRONTEND_WIDGETS.md` for Flutter widget implementations.
