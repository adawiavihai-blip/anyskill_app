

// ==========================================================================
// VAULT DASHBOARD - Cloud Functions (v14.x)
// ==========================================================================

// -- Vault period helpers --------------------------------------------------
function _vaultPeriodStart(period, now) {
  switch (period) {
    case "day":
      return new Date(now.getFullYear(), now.getMonth(), now.getDate());
    case "week": {
      const day = now.getDay();
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - day);
    }
    case "month":
      return new Date(now.getFullYear(), now.getMonth(), 1);
    case "year":
      return new Date(now.getFullYear(), 0, 1);
    default:
      return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }
}

function _vaultPrevPeriodStart(period, now) {
  switch (period) {
    case "day":
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    case "week": {
      const day = now.getDay();
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - day - 7);
    }
    case "month":
      return new Date(now.getFullYear(), now.getMonth() - 1, 1);
    case "year":
      return new Date(now.getFullYear() - 1, 0, 1);
    default:
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  }
}

// -- updateVaultAnalytics - hourly aggregation -----------------------------
exports.updateVaultAnalytics = onSchedule(
  { schedule: "every 1 hours", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    const periods = ["day", "week", "month", "year"];
    const now = new Date();

    for (const period of periods) {
      try {
        const start = _vaultPeriodStart(period, now);
        const prevStart = _vaultPrevPeriodStart(period, now);

        const earningsSnap = await db
          .collection("platform_earnings")
          .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(start))
          .limit(500)
          .get();

        const prevEarningsSnap = await db
          .collection("platform_earnings")
          .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(prevStart))
          .where("timestamp", "<", admin.firestore.Timestamp.fromDate(start))
          .limit(500)
          .get();

        const revenue = earningsSnap.docs.reduce(
          (s, d) => s + (Number(d.data().amount) || 0), 0
        );
        const prevRevenue = prevEarningsSnap.docs.reduce(
          (s, d) => s + (Number(d.data().amount) || 0), 0
        );
        const txCount = earningsSnap.docs.length;
        const prevTxCount = prevEarningsSnap.docs.length;
        const avgCommission = txCount > 0 ? revenue / txCount : 0;

        const completedSnap = await db
          .collection("jobs")
          .where("status", "==", "completed")
          .where("completedAt", ">=", admin.firestore.Timestamp.fromDate(start))
          .limit(500)
          .get();

        const providerIds = new Set();
        earningsSnap.docs.forEach((d) => {
          if (d.data().sourceExpertId) providerIds.add(d.data().sourceExpertId);
        });

        const revByCategory = {};
        earningsSnap.docs.forEach((d) => {
          const cat = d.data().category || d.data().serviceType || "other";
          revByCategory[cat] = (revByCategory[cat] || 0) + (Number(d.data().amount) || 0);
        });

        const dailyRevenue = {};
        earningsSnap.docs.forEach((d) => {
          const ts = d.data().timestamp;
          if (!ts) return;
          const dt = ts.toDate();
          const key = dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0");
          if (!dailyRevenue[key]) dailyRevenue[key] = { date: key, revenue: 0, transactions: 0 };
          dailyRevenue[key].revenue += Number(d.data().amount) || 0;
          dailyRevenue[key].transactions += 1;
        });

        const hourlyActivity = new Array(24).fill(0);
        earningsSnap.docs.forEach((d) => {
          const ts = d.data().timestamp;
          if (ts) hourlyActivity[ts.toDate().getHours()]++;
        });

        const cancelledSnap = await db
          .collection("jobs")
          .where("status", "in", ["cancelled", "cancelled_with_penalty"])
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(start))
          .limit(200)
          .get();

        const totalJobs = completedSnap.docs.length + cancelledSnap.docs.length;
        const completionRate = totalJobs > 0 ? completedSnap.docs.length / totalJobs * 100 : 100;
        const revenueGrowth = prevRevenue > 0 ? ((revenue - prevRevenue) / prevRevenue * 100) : (revenue > 0 ? 100 : 0);

        const growthScore = Math.min(100, Math.max(0, (revenueGrowth + 100) / 3));
        const retentionScore = Math.min(100, Math.max(0, completionRate));
        const diversityScore = Math.min(100, providerIds.size / 50 * 100);
        const healthTotal = growthScore * 0.3 + retentionScore * 0.3 + 80 * 0.2 + diversityScore * 0.2;

        const dailyArr = Object.values(dailyRevenue).sort((a, b) => a.date.localeCompare(b.date));
        let forecastLow = 0, forecastHigh = 0, confidence = 0;
        if (dailyArr.length >= 3) {
          const vals = dailyArr.map((d) => d.revenue);
          const avgDaily = vals.reduce((s, v) => s + v, 0) / vals.length;
          const daysRemaining = period === "month" ? 30 - dailyArr.length : 7;
          forecastLow = Math.round((revenue + avgDaily * daysRemaining) * 0.85);
          forecastHigh = Math.round((revenue + avgDaily * daysRemaining) * 1.15);
          confidence = Math.min(90, Math.round(dailyArr.length / 14 * 100));
        }

        await db.collection("vault_analytics").doc(period).set({
          period,
          revenue: roundNIS(revenue),
          transaction_count: txCount,
          avg_commission: roundNIS(avgCommission),
          active_providers: providerIds.size,
          completed_jobs: completedSnap.docs.length,
          cancelled_jobs: cancelledSnap.docs.length,
          revenue_change_percent: roundNIS(revenueGrowth),
          previous_period: {
            revenue: roundNIS(prevRevenue),
            transaction_count: prevTxCount,
          },
          revenue_by_category: revByCategory,
          daily_revenue: Object.values(dailyRevenue),
          hourly_activity: hourlyActivity,
          health_score: {
            total: Math.round(healthTotal),
            growth: Math.round(growthScore),
            retention: Math.round(retentionScore),
            settlement: 80,
            diversity: Math.round(diversityScore),
          },
          forecast: {
            monthly_low: forecastLow,
            monthly_high: forecastHigh,
            confidence_percent: confidence,
          },
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log("Vault analytics updated: " + period);
      } catch (err) {
        console.error("Vault analytics error (" + period + "):", err);
      }
    }
  }
);

// -- generateVaultAlerts - hourly smart alerts -----------------------------
exports.generateVaultAlerts = onSchedule(
  { schedule: "every 1 hours", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    try {
      const alerts = [];

      const cutoff48h = new Date(Date.now() - 48 * 60 * 60 * 1000);
      const stuckSnap = await db
        .collection("jobs")
        .where("status", "==", "paid_escrow")
        .where("createdAt", "<", admin.firestore.Timestamp.fromDate(cutoff48h))
        .limit(10)
        .get();

      for (const doc of stuckSnap.docs) {
        const existing = await db
          .collection("vault_alerts")
          .where("related_id", "==", doc.id)
          .where("type", "==", "warning")
          .limit(1)
          .get();
        if (existing.empty) {
          alerts.push({
            type: "warning",
            severity: "warning",
            title: "עסקה תקועה",
            message: "הזמנה " + doc.id.substring(0, 8) + " באסקרו יותר מ-48 שעות",
            related_id: doc.id,
          });
        }
      }

      const monthDoc = await db.collection("vault_analytics").doc("month").get();
      if (monthDoc.exists) {
        const rev = monthDoc.data().revenue || 0;
        for (const m of [100, 500, 1000, 5000, 10000]) {
          if (rev >= m) {
            const mTitle = "אבן דרך: ₪" + m;
            const existing = await db
              .collection("vault_alerts")
              .where("type", "==", "achievement")
              .where("title", "==", mTitle)
              .limit(1)
              .get();
            if (existing.empty) {
              alerts.push({
                type: "achievement",
                severity: "info",
                title: mTitle,
                message: "הכנסות החודש עברו את ₪" + m + "!",
              });
            }
          }
        }

        const monthData = monthDoc.data();
        const completed = monthData.completed_jobs || 0;
        const cancelled = monthData.cancelled_jobs || 0;
        if (completed + cancelled > 5 && cancelled / (completed + cancelled) > 0.2) {
          alerts.push({
            type: "risk",
            severity: "critical",
            title: "שיעור ביטולים גבוה",
            message: Math.round(cancelled / (completed + cancelled) * 100) + "% ביטולים החודש",
          });
        }
      }

      if (alerts.length > 0) {
        const batch = db.batch();
        for (const alert of alerts) {
          const ref = db.collection("vault_alerts").doc();
          batch.set(ref, {
            ...alert,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
          });
        }
        await batch.commit();
        console.log("Generated " + alerts.length + " vault alerts");
      }
    } catch (err) {
      console.error("Vault alerts error:", err);
    }
  }
);

// -- updateVaultBalance - trigger on transaction writes --------------------
exports.updateVaultBalance = onDocumentWritten(
  "transactions/{transactionId}",
  async () => {
    const db = admin.firestore();
    try {
      const settingsDoc = await db
        .collection("admin").doc("admin")
        .collection("settings").doc("settings")
        .get();

      const totalPlatformBalance = settingsDoc.exists
        ? (Number(settingsDoc.data().totalPlatformBalance) || 0)
        : 0;

      const pendingSnap = await db
        .collection("jobs")
        .where("status", "==", "paid_escrow")
        .limit(200)
        .get();
      const pendingAmount = pendingSnap.docs.reduce(
        (s, d) => s + (Number(d.data().commission) || 0), 0
      );

      const withdrawnSnap = await db
        .collection("withdrawals")
        .where("status", "==", "completed")
        .limit(500)
        .get();
      const totalWithdrawn = withdrawnSnap.docs.reduce(
        (s, d) => s + (Number(d.data().amount) || 0), 0
      );

      await db.collection("vault_balance").doc("main").set({
        available_balance: roundNIS(totalPlatformBalance - totalWithdrawn),
        pending_balance: roundNIS(pendingAmount),
        total_withdrawn: roundNIS(totalWithdrawn),
        total_platform_balance: roundNIS(totalPlatformBalance),
        last_updated: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      console.error("Vault balance update error:", err);
    }
  }
);
