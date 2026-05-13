# 🌐 Localization (Hebrew RTL) - Performance Observatory V5

> Complete Hebrew strings file with tooltips explaining every technical term.

---

## 📋 Implementation

Create `lib/l10n/performance_observatory_he.dart`:

```dart
/// Performance Observatory V5 - Hebrew Localization
/// 
/// Covers all UI strings + explanatory tooltips for technical terms.
/// Technical acronyms (APDEX, MTTR, SLO, p95) kept in English but explained in Hebrew tooltips.
class PerformanceObservatoryL10n {
  // Private constructor - use static access
  PerformanceObservatoryL10n._();

  // ═══════════════════════════════════════════════════════════
  // 📋 HEADER & NAVIGATION
  // ═══════════════════════════════════════════════════════════
  
  static const String title = 'Performance Observatory';
  static const String subtitle = 'v5.0 SCALE-READY · מוכן ל-10M משתמשים';
  static const String liveIndicator = 'LIVE · 2s';
  static const String multiRegion = 'Multi-Region: IL · US · EU · AU';
  static const String commandPalette = '⌘K · חיפוש בכל הדשבורד';
  static const String voiceControl = 'שליטה קולית';
  static const String askNova = 'Nova · Scale-Aware';
  static const String autonomousModeSupervised = 'Autonomous Mode: Supervised';
  static const String autonomousModeRecommend = 'Autonomous Mode: Recommend';
  static const String autonomousModeFull = 'Autonomous Mode: Autonomous';
  
  // ═══════════════════════════════════════════════════════════
  // 🎯 SCALE READINESS SCORE
  // ═══════════════════════════════════════════════════════════
  
  static const String scaleReadiness = 'Scale Readiness Score';
  static const String scaleReadinessSubtitle = 'האם המערכת מוכנה לגידול? · Gemini ML prediction';
  static const String scaleReadinessScoreLabel = 'SCORE';
  static const String scaleReadinessStatus = 'מוכן ל-500K · לא מוכן ל-10M';
  static const String whatsNeeded = 'מה עוד צריך לפני 10M users:';
  static const String firestoreAutoScaling = 'Firestore Auto-scaling';
  static const String firestoreAutoScalingDesc = 'מוכן · עד 1M connections';
  static const String cdnMultiRegion = 'CDN Multi-Region';
  static const String cdnMultiRegionDesc = 'פעיל · 4 regions';
  static const String redisCacheLayer = 'Redis Cache Layer';
  static const String redisCacheLayerDesc = 'חלקי · חסר עבור 5 endpoints';
  static const String firestoreSharding = 'Firestore Sharding';
  static const String firestoreShardingDesc = 'לא מוגדר · קריטי ל-10M!';
  static const String bigqueryPipeline = 'BigQuery Analytics Pipeline';
  static const String bigqueryPipelineDesc = 'Dashboard קורא ישירות מ-Firestore!';
  static const String fix = 'תקן';
  static const String fixNow = 'תקן עכשיו';
  static const String critical = 'קריטי!';
  static const String tenMillionPlan = '📋 תוכנית ל-10M';
  
  // ═══════════════════════════════════════════════════════════
  // 🏗️ ARCHITECTURE LIVE VIEW
  // ═══════════════════════════════════════════════════════════
  
  static const String architectureLiveView = 'Architecture Live View · Data Flow';
  static const String edgeLayer = 'EDGE';
  static const String computeLayer = 'COMPUTE';
  static const String dataLayer = 'DATA';
  static const String analyticsLayer = 'ANALYTICS';
  static const String usersLayer = 'USERS';
  static const String cacheHits = 'Cache hits (מהיר!)';
  static const String dbReads = 'DB reads (איטי)';
  static const String events = 'Events';
  static const String metricsStream = 'Metrics stream';
  static const String userTraffic = 'User traffic';
  
  // ═══════════════════════════════════════════════════════════
  // 💸 COST PROJECTION
  // ═══════════════════════════════════════════════════════════
  
  static const String costProjection = 'Cost Projection · תחזית עלויות ל-scale';
  static const String today = 'היום';
  static const String perDay = '/יום';
  static const String perMonth = '/חודש';
  static const String perUserPerMonth = '/user/month';
  static const String dauCount = 'DAU';
  static const String with10MUsers = '10M DAU · עם optimizations';
  static const String costSavings = 'Nova: חישוב עלויות ל-10M users:';
  static const String optimizationOption = '💡 אפטימיזציה';
  
  // ═══════════════════════════════════════════════════════════
  // 📊 TOP KPI STRIP
  // ═══════════════════════════════════════════════════════════
  
  static const String healthScore = 'HEALTH';
  static const String apdex = 'APDEX';
  static const String mttr = 'MTTR';
  static const String deployFreq = 'DEPLOY';
  static const String mrr = 'MRR';
  static const String dau = 'DAU';
  static const String excellent = 'מצוין';
  static const String eliteDora = 'Elite DORA';
  
  // ═══════════════════════════════════════════════════════════
  // 💼 BUSINESS IMPACT
  // ═══════════════════════════════════════════════════════════
  
  static const String businessImpactTitle = 'Business Impact · עכשיו';
  static const String businessImpactSubtitle = 'מקשר בעיות טכניות להפסד כסף אמיתי · Gemini correlation';
  static const String activeLoss = '🚨 הפסד פעיל';
  static const String lossPerMinute = '💸 הפסד / דקה';
  static const String cumulativeLoss = 'מהתחלת התקלה';
  static const String conversionDrop = '📉 Conversion Drop';
  static const String happinessScore = '😊 Happiness Score';
  static const String dropInHour = 'ירד השעה';
  static const String churnRisk = '🚪 Churn Risk';
  static const String vipsAtRisk = 'VIP בסכנה';
  static const String npsLive = '🎯 NPS חי';
  static const String yesterdayNps = 'ירד מ';
  static const String geminiCorrelationEngine = 'Gemini Correlation Engine:';
  static const String resolveNow = '💸 פתור עכשיו';
  
  // ═══════════════════════════════════════════════════════════
  // 🤖 AI AGENTS SWARM
  // ═══════════════════════════════════════════════════════════
  
  static const String autonomousAgents = 'Autonomous AI Agents · Multi-Agent Swarm';
  static const String supervisionSettings = 'Supervision Settings';
  
  // Detective
  static const String detectiveAgent = 'Detective';
  static const String detectiveTask = 'מנתח כרגע';
  static const String detectiveConfidence = 'confidence';
  
  // Healer
  static const String healerAgent = 'Healer';
  static const String healerTask = 'מחכה לאישור';
  static const String healerEta = 'ETA';
  
  // Oracle
  static const String oracleAgent = 'Oracle';
  static const String oracleTask = 'תחזית';
  static const String oraclePeak = 'peak ב';
  static const String oracleRecommendation = 'scale up מומלץ';
  
  // Guardian
  static const String guardianAgent = 'Guardian';
  static const String guardianTask = 'חוקר';
  static const String guardianThreats = 'איומים נחסמו';
  
  // Chronicler
  static const String chroniclerAgent = 'Chronicler';
  static const String chroniclerTask = 'כותב post-mortem לתקרית';
  static const String chroniclerReports = 'דוחות החודש';
  
  static const String actionsToday = 'פעולות היום';
  static const String fixesToday = 'תיקונים היום';
  static const String activePredictions = 'תחזיות פעילות';
  
  // ═══════════════════════════════════════════════════════════
  // 🚨 INCIDENT WAR ROOM
  // ═══════════════════════════════════════════════════════════
  
  static const String warRoomTitle = 'Incident War Room';
  static const String p1Active = 'P1 ACTIVE';
  static const String affectedUsers = 'users affected';
  static const String currentLoss = 'הפסד';
  static const String team = 'צוות';
  static const String joinWarRoom = '📞 Join War Room';
  static const String liveStream = '📺 Live Stream';
  static const String aiInvestigation = 'AI Investigation · 5 agents coordinating';
  static const String done = 'done';
  static const String resolutionOptions = 'Resolution Options';
  static const String addIndex = '🔧 Add Index (מומלץ)';
  static const String rollback = '⏪ Rollback';
  static const String rateLimit = '🚦 Rate Limit';
  static const String teamChat = 'Team Chat';
  static const String online = 'online';
  
  // ═══════════════════════════════════════════════════════════
  // 🎯 4 GOLDEN SIGNALS
  // ═══════════════════════════════════════════════════════════
  
  static const String goldenSignals = '4 Golden Signals (Google SRE)';
  static const String latency = 'Latency';
  static const String latencyDesc = 'זמן תגובה';
  static const String traffic = 'Traffic';
  static const String trafficDesc = 'תעבורה';
  static const String errors = 'Errors';
  static const String errorsDesc = 'שגיאות';
  static const String saturation = 'Saturation';
  static const String saturationDesc = 'רוויה';
  static const String p50 = 'p50';
  static const String p95 = 'p95';
  static const String p99 = 'p99';
  
  // ═══════════════════════════════════════════════════════════
  // 🌍 GLOBAL MAP + HIGH AVAILABILITY
  // ═══════════════════════════════════════════════════════════
  
  static const String highAvailability = 'High Availability · 99.99%';
  static const String primary = 'Primary';
  static const String secondary = 'Secondary';
  static const String replica = 'Replica';
  static const String active = 'ACTIVE';
  static const String standby = 'STANDBY';
  static const String replicaLag = 'Replica lag';
  static const String failoverReady = 'Failover ready';
  static const String notDeployed = 'Not deployed';
  static const String deploy = 'פרוס';
  static const String recommendedForRegion = 'Recommended for users';
  
  // ═══════════════════════════════════════════════════════════
  // 🚦 CIRCUIT BREAKERS + RATE LIMITS
  // ═══════════════════════════════════════════════════════════
  
  static const String circuitBreakers = 'Circuit Breakers + Rate Limits';
  static const String closed = 'CLOSED';
  static const String throttled = 'THROTTLED';
  static const String open = 'OPEN!';
  static const String quotaUsed = 'quota used';
  static const String load = 'load';
  static const String retryWithBackoff = 'retry with exponential backoff';
  static const String circuitOpen = 'Circuit open - חסום';
  static const String tooManyFailures = 'Too many failures';
  
  // ═══════════════════════════════════════════════════════════
  // 🔥 AUTO-SCALING LIVE
  // ═══════════════════════════════════════════════════════════
  
  static const String autoScaling = 'Auto-Scaling Live · Cloud Run Instances';
  static const String instancesLabel = 'instances';
  static const String currentInstances = 'כרגע';
  static const String maxToday = 'Max היום';
  static const String costOptimized = 'Cost optimized';
  static const String scalingSettings = 'הגדרות';
  static const String minMax = 'Min: 2 · Max: 100';
  static const String predictiveScaling = 'Predictive scaling פעיל';
  static const String activity24h = 'פעילות 24h · instances vs traffic';
  static const String peak = 'peak';
  
  // ═══════════════════════════════════════════════════════════
  // 🚨 LOAD SHEDDING
  // ═══════════════════════════════════════════════════════════
  
  static const String loadShedding = 'Load Shedding · הגנה בעומסי שיא';
  static const String loadSheddingDesc = 'כשהמערכת עומס יתר - ה-AI בוחר מי מקבל שירות לפי priority';
  static const String tier1Critical = 'Tier 1 · Critical';
  static const String tier1Services = 'Payment · Active Booking · Login';
  static const String tier1Status = 'תמיד פעיל';
  static const String tier2Important = 'Tier 2 · Important';
  static const String tier2Services = 'Search · Chat · Profile';
  static const String tier3NiceToHave = 'Tier 3 · Nice-to-have';
  static const String tier3Services = 'AI suggestions · Analytics · Recommendations';
  static const String tier4Background = 'Tier 4 · Background';
  static const String tier4Services = 'Reports · Cleanup · Non-urgent emails';
  static const String underHighLoad = 'בעומס שיא (>90% CPU)';
  static const String tier1NeverFalls = 'Tier 1 אף פעם לא נופל!';
  
  // ═══════════════════════════════════════════════════════════
  // 💾 DATA ARCHITECTURE
  // ═══════════════════════════════════════════════════════════
  
  static const String dataArchitecture = 'Data Architecture · Multi-tier Storage';
  static const String hotRedis = 'Hot · Redis';
  static const String hotRedisDesc = '< 1ms · hot data';
  static const String warmFirestore = 'Warm · Firestore';
  static const String warmFirestoreDesc = '~100ms · recent data';
  static const String coolBigquery = 'Cool · BigQuery';
  static const String coolBigqueryDesc = '~1s · analytics';
  static const String coldStorage = 'Cold · Cloud Storage';
  static const String coldStorageDesc = '~10s · archive';
  static const String userSessions = 'User sessions';
  static const String topSearchResults = 'Top search results';
  static const String recentChats = 'Recent chats';
  static const String userProfiles = 'User profiles';
  static const String activeBookings = 'Active bookings';
  static const String providerData = 'Provider data';
  static const String historicalMetrics = 'Historical metrics';
  static const String reportsOverNinetyDays = 'Reports > 90 days';
  static const String dashboards = 'Dashboards';
  static const String oldPhotos = 'Old photos';
  static const String completedBookings = 'Completed bookings';
  static const String complianceLogs = 'Compliance logs';
  static const String ttl1Hour = 'TTL: 1 hour';
  static const String shardedTenX = 'Sharded × 10';
  static const String aggregated = 'Aggregated';
  static const String nearlineColdline = 'Nearline/Coldline';
  static const String fourTierStrategy = 'אסטרטגיית 4 רבדים';
  static const String ninetyFivePercentHitsRedis = '95% מהקריאות מגיעות ל-Redis (hot) → חוסך 95% מעלויות Firestore!';
  
  // ═══════════════════════════════════════════════════════════
  // 🆘 DISASTER RECOVERY
  // ═══════════════════════════════════════════════════════════
  
  static const String disasterRecovery = 'Disaster Recovery';
  static const String rto = 'RTO (Recovery Time)';
  static const String rtoDesc = 'זמן מקסימלי ל-failover אוטומטי';
  static const String rpo = 'RPO (Data Loss)';
  static const String rpoDesc = 'נתונים שעלולים להיאבד בכשל';
  static const String lastBackup = 'Last Backup';
  static const String continuousReplication = 'Continuous · real-time replication';
  static const String lastDrDrill = 'Last DR Drill';
  static const String drPass = 'PASS';
  static const String runDrDrill = '🔴 הרץ DR Drill עכשיו';
  
  // ═══════════════════════════════════════════════════════════
  // 📡 OBSERVABILITY PIPELINE
  // ═══════════════════════════════════════════════════════════
  
  static const String observabilityPipeline = 'Observability Pipeline';
  static const String dashboardReadsFromBigquery = 'הדשבורד לא קורא ישירות מ-Firestore (יקר!) · קורא מ-BigQuery דרך Pub/Sub';
  static const String step1Collection = '1. Metrics Collection';
  static const String step1Desc = 'Cloud Run emits → Pub/Sub (100K events/sec)';
  static const String step2Processing = '2. Stream Processing';
  static const String step2Desc = 'Dataflow → aggregate to 1min/1hour/1day';
  static const String step3Storage = '3. Storage';
  static const String step3Desc = 'BigQuery partitioned tables · 6 months hot, 2y cold';
  static const String step4Query = '4. Dashboard Query';
  static const String step4Desc = 'BigQuery SQL · 99% cache hit rate · < 50ms';
  static const String resultBigquery = 'התוצאה: דשבורד ב-10M users יעלה \$200/חודש במקום \$50,000';
  
  // ═══════════════════════════════════════════════════════════
  // 🎯 CONVERSION FUNNEL
  // ═══════════════════════════════════════════════════════════
  
  static const String conversionFunnel = 'Conversion Funnel · איפה הלקוחות נופלים';
  static const String funnelToday = 'היום';
  static const String funnelYesterday = 'אתמול';
  static const String funnelCompare = 'השוואה';
  static const String stepHome = '🏠 Home';
  static const String stepSearch = '🔍 Search';
  static const String stepBook = '📅 Book';
  static const String stepChat = '💬 Chat';
  static const String stepPay = '💰 Pay';
  static const String stepDone = '✅ Done';
  static const String bottleneckDetected = 'הבעיה היא השלב';
  static const String fixingWouldGain = 'אם תפתור, הצפי';
  static const String compareToSaas = 'השוואה ל-SaaS';
  
  // ═══════════════════════════════════════════════════════════
  // 🧬 COHORT ANALYSIS
  // ═══════════════════════════════════════════════════════════
  
  static const String cohortAnalysis = 'Cohort Analysis';
  static const String cohortDesc = 'אחוז חזרה לפי שבוע הרשמה';
  static const String cohortWeek = 'שבוע';
  static const String bestCohort = 'Cohort הכי חזק';
  
  // ═══════════════════════════════════════════════════════════
  // 🎯 FEATURE ADOPTION
  // ═══════════════════════════════════════════════════════════
  
  static const String featureAdoption = 'Feature Adoption';
  static const String handymanCsm = '🛠️ Handyman (חדש!)';
  static const String cleaningCsm = '🧼 Cleaning';
  static const String massageCsm = '💆 Massage';
  static const String deliveryCsm = '🛵 Delivery';
  static const String pestCsm = '🐛 Pest';
  static const String adoptionLow = 'נמוך - מומלץ לקדם ב-UX או לבדוק אם יש בעיה';
  
  // ═══════════════════════════════════════════════════════════
  // 🎲 IMPACT SIMULATOR
  // ═══════════════════════════════════════════════════════════
  
  static const String impactSimulator = 'Impact Simulator · "מה יקרה אם..."';
  static const String mlPredictions = 'Gemini ML predictions';
  static const String scenarioAddIndex = '🤔 אם אוסיף composite index עכשיו';
  static const String scenarioScaleUp = '🚀 אם אוסיף CF instances (3→8)';
  static const String scenarioCdnAu = '🌏 אם אפעיל CDN edge באוסטרליה';
  static const String executeNow = '⚡ בצע עכשיו';
  static const String planAhead = '📋 תוכן';
  static const String moreOptions = '💡 עוד אפשרויות';
  static const String askNovaPlaceholder = 'שאל Nova: מה יקרה אם אעלה את המחיר ב-10%?';
  static const String calculate = 'חשב';
  
  // ═══════════════════════════════════════════════════════════
  // 🧪 CHAOS ENGINEERING
  // ═══════════════════════════════════════════════════════════
  
  static const String chaosEngineering = 'Chaos Engineering Lab';
  static const String chaosSubtitle = 'הרץ תרגילים לבדוק חוסן';
  static const String chaosDesc = 'כמו Netflix - אתה מפיל בכוונה שירות כדי לבדוק שהמערכת שורדת';
  static const String chaosBlastRadius = 'Blast Radius';
  static const String dbSlowdown = 'DB Slowdown';
  static const String dbSlowdownDesc = 'הוסף latency של 500ms ל-Firestore';
  static const String cfTimeout = 'CF Timeout';
  static const String cfTimeoutDesc = 'כשל מדומה של Cloud Function';
  static const String networkDrop = 'Network Drop';
  static const String networkDropDesc = 'חוסר רשת בקצה משתמש';
  static const String trafficStorm = 'Traffic Storm';
  static const String trafficStormDesc = '×10 traffic simulation';
  static const String passedYesterday = 'עברנו (אתמול)';
  static const String failedLastWeek = 'כשל שבוע שעבר';
  static const String autoRetryWorks = 'Auto-retry עובד';
  static const String notTested = 'לא נבדק';
  static const String runChaos = '▶ הרץ';
  static const String chaosMonkey = 'Chaos Monkey';
  static const String chaosMonkeyDesc = 'שגרה לא-מתוזמנת של הפלות - מופעל שבת 02:00 בלבד';
  static const String chaosSettings = 'הגדרות';
  
  // ═══════════════════════════════════════════════════════════
  // 🎚️ FEATURE FLAGS
  // ═══════════════════════════════════════════════════════════
  
  static const String featureFlags = 'Feature Flags';
  static const String featureFlagsDesc = 'הדלק/כבה פיצ\'רים ל-% מהמשתמשים (Dark Launch)';
  static const String flagOn = 'ON';
  static const String flagDark = 'DARK';
  static const String flagOff = 'OFF';
  static const String adminOnly = 'admin only';
  static const String testing = 'testing';
  
  // ═══════════════════════════════════════════════════════════
  // 📝 BLAMELESS POST-MORTEM
  // ═══════════════════════════════════════════════════════════
  
  static const String blamelessPostmortem = 'Blameless Post-Mortem · AI Generated';
  static const String archive = '📚 ארכיון';
  static const String reports = 'דוחות';
  static const String chroniclerAutogen = 'Chronicler Agent · מכין דוח אוטומטית';
  static const String complete = 'complete';
  static const String reportStructure = '📋 מבנה הדוח';
  static const String summarySentence = 'סיכום · 1 משפט';
  static const String timelineWithEvents = 'ציר זמן עם events';
  static const String rootCauseAnalysis = 'Root cause analysis';
  static const String businessImpact = 'Business impact';
  static const String lessonsLearned = 'Lessons learned';
  static const String actionItems = 'Action items';
  static const String inProgress = '(מכין)';
  static const String pending = '(ממתין)';
  static const String tldr = 'TL;DR';
  static const String blamelessNote = 'ללא אשמים';
  static const String viewDraft = '📄 צפה בטיוטה מלאה';
  static const String editDraft = '✏️ ערוך';
  static const String sendReport = '📧 שלח';
  
  // ═══════════════════════════════════════════════════════════
  // 🤖 NOVA AI COPILOT
  // ═══════════════════════════════════════════════════════════
  
  static const String novaTitle = 'Nova · AI Copilot';
  static const String novaSubtitle = 'Business-aware · יודעת על revenue + churn · 🎤 voice + 📎 files';
  static const String novaVersion = 'v4 ENHANCED';
  static const String novaWelcome = 'שלום! אני Nova, עוזר AI לניטור המערכת. שאל אותי על כל דבר - מונחים טכניים, בעיות במערכת, המלצות לשיפור. איך אני יכול לעזור?';
  static const String novaThinking = 'Nova חושבת...';
  static const String novaError = 'סליחה, לא הצלחתי לענות. נסה שוב?';
  static const String askNovaAnything = 'שאל את Nova על כל דבר...';
  static const String send = 'שלח →';
  static const String novaSuggestion1 = '🎤 "Nova, כמה הפסדתי היום?"';
  static const String novaSuggestion2 = '📈 השווה ל-Uber';
  static const String novaSuggestion3 = '🔮 תחזית שבוע הבא';
  static const String novaAnalysisHeader = '📊 ניתחתי הכל - הנה ההמלצה שלי:';
  static const String fixCriticalFirst = '⚡ תקן #1 עכשיו';
  static const String sendVipPush = '📱 שלח push לVIPs';
  static const String fullReport = '📊 דוח מלא';
  static const String tryThese = '💡 נסה:';
  
  // ═══════════════════════════════════════════════════════════
  // ⚡ QUICK ACTIONS
  // ═══════════════════════════════════════════════════════════
  
  static const String quickActions = 'Quick Actions';
  static const String sentryTest = 'Sentry Test';
  static const String corsSetup = 'CORS Setup';
  static const String phoneAuth = 'Phone→Auth';
  static const String clearCache = 'Clear Cache';
  static const String quickRollback = 'Rollback';
  static const String weeklyReport = 'Weekly Report';
  static const String autoScale = 'Auto-Scale';
  static const String vipPush = 'VIP Push';
  static const String chaosTest = 'Chaos Test';
  static const String askNovaQuick = 'Ask Nova';
  
  // ═══════════════════════════════════════════════════════════
  // 🔗 INTEGRATIONS FOOTER
  // ═══════════════════════════════════════════════════════════
  
  static const String integrations = '🔗 Integrations:';
  static const String stack = '🏗️ Stack:';
  static const String poweredBy = 'Datadog + Splunk + Grafana + Uber M3 patterns · Built for AnySkill';
  
  // ═══════════════════════════════════════════════════════════
  // ⏰ TIME & UNITS
  // ═══════════════════════════════════════════════════════════
  
  static const String now = 'עכשיו';
  static const String minutes = 'דק\'';
  static const String seconds = 'שניות';
  static const String hour = 'שעה';
  static const String day = 'יום';
  static const String week = 'שבוע';
  static const String month = 'חודש';
  static const String justNow = 'לפני רגע';
  static const String agoPrefix = 'לפני';
  static const String minutesAgo = 'דקות';
  static const String secondsAgo = 'שניות';
  
  // ═══════════════════════════════════════════════════════════
  // 📊 STATUS MESSAGES
  // ═══════════════════════════════════════════════════════════
  
  static const String healthy = 'בריא';
  static const String warning = 'אזהרה';
  static const String criticalStatus = 'קריטי';
  static const String loading = 'טוען...';
  static const String errorLoading = 'שגיאה בטעינה';
  static const String noData = 'אין מידע להצגה';
  static const String tryAgain = 'נסה שוב';
  static const String refresh = 'רענן';
  static const String confirm = 'אשר';
  static const String cancel = 'בטל';
  static const String yes = 'כן';
  static const String no = 'לא';
  static const String ok = 'אישור';
  static const String close = 'סגור';
  static const String processing = 'מעבד...';
  static const String success = 'הצלחה';
  static const String failed = 'נכשל';
}
```

---

## 💬 Tooltip Explanations (for Hover Help)

Create `lib/l10n/performance_tooltips_he.dart`:

```dart
/// Tooltips explaining technical terms in Hebrew
/// Show these when user hovers over a term like APDEX, MTTR, etc.
class PerformanceTooltips {
  PerformanceTooltips._();
  
  /// APDEX = Application Performance Index
  static const String apdex = '''
APDEX (Application Performance Index)

ציון בין 0 ל-1 שמודד כמה המשתמשים מרוצים מזמני התגובה.

• 0.0-0.5: גרוע
• 0.5-0.7: סביר  
• 0.7-0.85: טוב
• 0.85-0.94: מצוין
• 0.94-1.0: מצטיין

חישוב: (משתמשים מרוצים + מעל 50% מהסובלנים) / סה"כ.
סף סבילות: עד 500ms מרוצה, 500ms-2s סובלני, >2s לא מרוצה.
''';

  /// MTTR = Mean Time To Recovery
  static const String mttr = '''
MTTR (Mean Time To Recovery)

זמן ממוצע לתיקון תקלה מרגע הזיהוי עד הפתרון.

• פחות מ-10 דק': Elite (לפי Google DORA)
• 10-60 דק': גבוה
• 1-24 שעות: בינוני
• מעל 24 שעות: נמוך

המטרה: להוריד את ה-MTTR במקסימום על ידי אוטומציה וניטור טוב יותר.
''';

  /// SLO = Service Level Objective
  static const String slo = '''
SLO (Service Level Objective)

יעד שירות שהגדרנו לעצמנו.

דוגמה: "99.9% מהבקשות ייענו תוך פחות מ-500ms".

• SLI (Indicator): מה אנחנו מודדים (latency, error rate)
• SLO (Objective): היעד שהגדרנו (99.9%)
• SLA (Agreement): החוזה המשפטי עם הלקוח

Error Budget = 100% - SLO. למשל, SLO של 99.9% = 0.1% error budget (43 דק' בחודש).
''';

  /// P95 latency
  static const String p95 = '''
p95 Latency

האחוזון ה-95 של זמני התגובה.

אם p95 = 500ms, זה אומר ש-95% מהבקשות ענו תוך פחות מ-500ms, וה-5% הגרועים ביותר לקחו יותר.

• p50 = חציון (median) - זמן תגובה של המשתמש הממוצע
• p95 = אחוזון 95 - אומר לך על ה"רגעים הרעים"
• p99 = אחוזון 99 - אומר על המצבים הקיצוניים ביותר

עדיף להתמקד ב-p95 ולא ב-average - הוא משקף את חווית המשתמש האמיתית.
''';

  /// Core Web Vitals
  static const String coreWebVitals = '''
Core Web Vitals (Google)

3 מטריקות שמודדות את חוויית המשתמש באתר:

• LCP (Largest Contentful Paint) - זמן טעינת התוכן הגדול ביותר
  • טוב: < 2.5s
  • צריך שיפור: 2.5-4.0s  
  • גרוע: > 4.0s

• FID (First Input Delay) - זמן תגובה לאינטראקציה ראשונה
  • טוב: < 100ms
  • צריך שיפור: 100-300ms
  • גרוע: > 300ms

• CLS (Cumulative Layout Shift) - יציבות הפריסה
  • טוב: < 0.1
  • צריך שיפור: 0.1-0.25
  • גרוע: > 0.25

Google משתמש במדדים האלה לדירוג SEO!
''';

  /// DORA Metrics
  static const String dora = '''
DORA Metrics (Google DevOps)

4 מטריקות שמודדות ביצועי צוות DevOps:

1. Deploy Frequency - כמה פעמים ביום/שבוע מפרסמים קוד
2. Lead Time for Changes - זמן מ-commit עד production
3. MTTR - זמן ממוצע לתיקון תקלה
4. Change Failure Rate - אחוז deployments שגרמו לתקלה

רמות:
• Elite: Deploy מספר פעמים ביום, MTTR < 1 שעה, CFR < 15%
• High: Deploy פעם בשבוע, MTTR < יום, CFR 16-30%
• Medium: Deploy פעם בחודש
• Low: פעם ברבעון
''';

  /// Rate Limiting
  static const String rateLimiting = '''
Rate Limiting (הגבלת קצב)

מונע מ-API להתרסק תחת עומס יתר על ידי הגבלת מספר בקשות.

לדוגמה: "100 בקשות לשנייה לכל משתמש"

אם עוברים את המגבלה:
• 429 Too Many Requests
• ללקוח מומלץ לנסות שוב אחרי זמן (exponential backoff)

שימושים:
• הגנה מפני DDoS
• מניעת bot scraping
• הבטחת שוויון בין משתמשים
''';

  /// Circuit Breaker
  static const String circuitBreaker = '''
Circuit Breaker (מפסק)

דפוס אבטחה שמונע cascade failure (כשל שרשרת).

3 מצבים:
• CLOSED - הכל בסדר, מאפשר בקשות
• OPEN - יותר מדי כשלים! חוסם בקשות זמנית
• HALF_OPEN - בודק אם השירות חזר לפעול

כמו מפסק חשמל בבית: אם יש short, המפסק קופץ ומונע שריפה.

ב-AnySkill: אם Cloud Function נכשל 5 פעמים רצופות, Circuit נפתח למשך 30 שניות.
''';

  /// Chaos Engineering
  static const String chaosEngineering = '''
Chaos Engineering (הנדסת כאוס)

פילוסופיה: "תפיל את המערכת בכוונה כדי למצוא חולשות לפני שהמציאות תפיל אותה בשבילך".

Netflix המציאו את Chaos Monkey ב-2011 - תוכנה שמפילה שרתים באופן אקראי בייצור!

תרגילים נפוצים:
• DB Slowdown - הוסף latency מלאכותי
• Network Partition - נתק שירות מהרשת
• Traffic Storm - שלח ×10 תעבורה
• Kill Pods - הרוג instances אקראיים

Blast Radius = היקף הנזק שהתרגיל יגרום (small/medium/large).
''';

  /// Observability vs Monitoring
  static const String observability = '''
Observability (ניצפות)

ההבדל ממוניטורינג:
• Monitoring: "האם X נופל?" (idex known unknowns)
• Observability: "למה X נופל?" (חקירה)

3 עמודים (Pillars):
1. Metrics - מספרים (CPU, latency, error rate)
2. Logs - אירועים טקסטואליים
3. Traces - מעקב בקשה דרך כל השירותים

בשנים האחרונות נוסף גם:
4. Profiles - ניתוח ביצועי קוד
5. Events - שינויים במערכת (deploys)

AnySkill משתמשת בכל ה-5!
''';

  /// Error Budget
  static const String errorBudget = '''
Error Budget (תקציב שגיאות)

כמה דאונטיים מותר לך לפי ה-SLO.

SLO 99.9% = 0.1% downtime allowed
• בחודש: ~43 דקות
• בשבוע: ~10 דקות
• ביום: ~86 שניות

אם חרגת מהתקציב:
• עצור פיצ'רים חדשים
• התמקד ביציבות
• שפר את ה-MTTR

Google SRE: "Error budget is a feature, not a bug" - אם יש תקציב, אפשר להעז!
''';

  /// APM = Application Performance Monitoring
  static const String apm = '''
APM (Application Performance Monitoring)

כלי ניטור ביצועי אפליקציה מהצד של השרת.

מה מודדים:
• Latency של endpoints
• Error rates
• Database query performance
• External API calls

דוגמאות מוכרות:
• Datadog APM
• New Relic
• Dynatrace
• Sentry Performance

AnySkill: Firebase Performance Monitoring + Sentry
''';

  /// RUM = Real User Monitoring
  static const String rum = '''
RUM (Real User Monitoring)

ניטור ביצועים מהצד של המשתמש האמיתי.

ההבדל מ-APM:
• APM: מודד בשרת (מהיר, מדויק, לא משקף משתמש אמיתי)
• RUM: מודד בדפדפן/אפליקציה (אמיתי, אבל עם noise)

מה מודדים:
• Page Load Time
• Time to Interactive
• Device type (mobile/desktop)
• Browser
• Region

AnySkill: Firebase Performance Monitoring + Sentry Session Replay
''';

  /// BigQuery
  static const String bigquery = '''
BigQuery

Data warehouse של Google Cloud לאנליטיקה בסקייל ענק.

ייתרונות:
• SQL רגיל (לא צריך ללמוד שפה חדשה)
• סקאלה לפטה-בייטים
• Serverless (לא מנהלים שרתים)
• תשלום לפי query (זול ברוב המקרים)

שימושים ב-AnySkill:
• Dashboard reads (במקום Firestore!)
• Analytics queries
• ML training data
• Cohort analysis
• Funnel analysis

זה הגורם הגדול ביותר לסקייל של הדשבורד!
''';

  /// Redis
  static const String redis = '''
Redis (Remote Dictionary Server)

מסד נתונים in-memory (כל הנתונים ב-RAM) - מהיר מאוד.

שימושים טיפוסיים:
• Cache (95% מהקריאות)
• Session storage
• Rate limiting counters
• Real-time leaderboards
• Pub/Sub messaging

למה מהיר:
• RAM access (< 1ms)
• Single-threaded (אין locks)
• Optimized data structures

AnySkill: Google Cloud Memorystore (Redis managed service).
''';

  /// Pub/Sub
  static const String pubsub = '''
Pub/Sub (Publish/Subscribe)

דפוס של Message Queue - שירות אחד שולח, שירותים אחרים מקבלים.

יתרונות:
• Decoupling (שירותים לא מחוברים ישירות)
• Scaling (אפשר להוסיף subscribers)
• Reliability (retry automatic)
• Async (לא חוסם את השולח)

דוגמה ב-AnySkill:
1. Cloud Run שולח metric ל-Pub/Sub topic "metrics-stream"
2. Cloud Function listens ומעביר ל-BigQuery
3. אם BigQuery נפל - Pub/Sub שומר את ההודעה ומנסה שוב

זה הגורם שמאפשר scale ל-100K events/sec.
''';

  /// Sharding
  static const String sharding = '''
Sharding (חלוקת מסד נתונים)

חלוקה של collection אחד גדול לכמה קטנים.

למה?
• Firestore: 10,000 writes/sec per collection max
• ב-10M users עוברים את זה בקלות
• פתרון: חלק ל-10 shards, כל אחד מקבל 10% מהעומס

דוגמה:
במקום: /experts (10M docs)
נעשה: /experts_shard_0 ... /experts_shard_9 (1M docs each)

איך מחלקים?
hash(expertId) % 10 → shard number

חיסרון: queries מורכבות יותר (צריך לפנות ל-10 shards במקביל).
''';
}
```

---

## 🎯 Usage in Widgets

Example usage in a Flutter widget:

```dart
import '../../l10n/performance_observatory_he.dart';
import '../../l10n/performance_tooltips_he.dart';

// In a widget:
Text(PerformanceObservatoryL10n.scaleReadiness)

// With tooltip:
Tooltip(
  message: PerformanceTooltips.apdex,
  waitDuration: const Duration(milliseconds: 500),
  child: Text('APDEX'),
)
```

---

## ✅ Localization Checklist

- [ ] All UI strings in Hebrew
- [ ] Technical acronyms kept in English (APDEX, MTTR, SLO)
- [ ] Tooltips explain every technical term in Hebrew
- [ ] Currency: NIS (₪) for revenue, USD ($) for Firebase costs
- [ ] Numbers use Israeli format (comma as thousand separator)
- [ ] Dates use DD/MM/YYYY format
- [ ] All RTL (Right-to-Left) correctly applied
- [ ] Emoji-first for visual scanning
- [ ] Consistent terminology throughout

---

## 🚀 Final Notes for Claude Code

**Before you start coding:**

1. ✅ Read `01_MAIN_PROMPT_PERFORMANCE_V5.md` (project overview)
2. ✅ Read `02_CLOUD_FUNCTIONS.md` (16 Cloud Functions)
3. ✅ Read `03_FRONTEND_WIDGETS.md` (17 Flutter widgets)
4. ✅ Read `04_INFRASTRUCTURE.md` (BigQuery, Redis, Pub/Sub, Sharding)
5. ✅ This file (Hebrew localization)

**Implementation order:**

1. 🏗️ Infrastructure (BigQuery, Pub/Sub, Redis) - 4 hours
2. 🔌 Cloud Functions (16 functions) - 8 hours
3. 🎨 Frontend widgets (17 widgets) - 12 hours
4. 🧪 Testing & polish - 4 hours

**Total estimated time: 28 hours** spread over 3-4 days.

**Critical success factors:**

- 🎯 Dashboard MUST read from BigQuery (not Firestore) for metrics
- 🎯 All collections > 1M docs MUST be sharded
- 🎯 Redis cache MUST have hit rate > 80%
- 🎯 All UI in Hebrew RTL
- 🎯 `flutter analyze`: 0 issues before merge

---

**🚀 Good luck! You're building something that will genuinely scale to 10M users.**
