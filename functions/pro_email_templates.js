// ═══════════════════════════════════════════════════════════════════════════
// AnySkill Pro — Hebrew RTL email templates (Phase 2)
//
// Two templates wired to the Firebase Trigger Email extension. The CF
// writes a `mail/{auto-id}` doc with `{ to, message: { subject, html } }`
// and the extension delivers via the configured SMTP transport.
//
// All copy is exactly the user-provided HTML, with `{{placeholder}}`
// tokens replaced by per-call values. Placeholder set:
//   GRANT  : providerName, appLink
//   REVOKE : providerName, revocationReason, currentRating, completedDeals,
//            avgResponseTime, cancellations, recoveryTip, appLink
// ═══════════════════════════════════════════════════════════════════════════

const APP_LINK_DEFAULT = "https://anyskill-6fdf3.web.app";

// ── Revocation reason + recovery tip in Hebrew ─────────────────────────────
//
// Mirrors the JS spec the user wrote. Order of priority matches
// pro_service.js :: _identifyRevokeReason — first failing criterion wins.
//
// Returns { reason, tip }. Both Hebrew, both ready for the email body.
function getRevocationCopy({
  rating,
  completedDeals,
  avgResponseTime,
  cancellations,
  thresholds,
}) {
  const minRating          = thresholds.minRating;
  const minOrders          = thresholds.minOrders;
  const maxResponseMinutes = thresholds.maxResponseMinutes;

  if (cancellations > 0) {
    return {
      reason: `רשמנו ${cancellations} ביטול/ים מצדך ב-30 הימים האחרונים.`,
      tip:    "הימנע מקבלת עסקאות שאתה לא בטוח שתוכל לעמוד בהן. כשעוברים 30 יום ללא ביטולים — התג חוזר אוטומטית.",
    };
  }
  if (rating < minRating) {
    return {
      reason: `הדירוג הממוצע שלך ירד ל-${rating.toFixed(1)}, מתחת לסף של ${minRating}.`,
      tip:    "התמקד בתקשורת מעולה עם הלקוחות ובאיכות השירות. כל דירוג חיובי חדש יעלה את הממוצע שלך.",
    };
  }
  if (completedDeals < minOrders) {
    return {
      reason: `השלמת ${completedDeals} עסקאות מתוך ${minOrders} הנדרשות.`,
      tip:    "המשך לקבל ולסיים עסקאות בהצלחה. ברגע שתגיע ל-${minOrders} עסקאות מושלמות — תוכל לזכות בתג.",
    };
  }
  if (avgResponseTime > maxResponseMinutes) {
    return {
      reason: `זמן התגובה הממוצע שלך עלה ל-${Math.round(avgResponseTime)} דקות, מעל הסף של ${maxResponseMinutes} דקות.`,
      tip:    "הפעל התראות מיידיות באפליקציה וענה לפניות חדשות בהקדם האפשרי. גם תגובה קצרה של 'אחזור אליך בקרוב' נספרת.",
    };
  }
  return {
    reason: "לא עמדת באחד מהקריטריונים של AnySkill Pro.",
    tip:    "בדוק את הדשבורד שלך לפרטים המדויקים.",
  };
}

// ── Template 1: Grant 🏆 ───────────────────────────────────────────────────

function buildGrantEmail({ providerName, appLink = APP_LINK_DEFAULT }) {
  const subject = "🏆 מזל טוב! קיבלת את תג AnySkill Pro";
  const html = `<!DOCTYPE html>
<html dir="rtl" lang="he">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ברוך הבא ל-AnySkill Pro</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Rubik', 'Assistant', Arial, sans-serif; background-color: #f5f5f7; direction: rtl;">
  <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="background-color: #f5f5f7; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="600" style="max-width: 600px; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.08);">

          <tr>
            <td style="background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); padding: 48px 40px; text-align: center;">
              <div style="font-size: 64px; margin-bottom: 16px;">🏆</div>
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: 700; line-height: 1.3;">
                מזל טוב, ${_escape(providerName)}!
              </h1>
              <p style="color: #e0e7ff; margin: 12px 0 0 0; font-size: 18px; font-weight: 500;">
                קיבלת את תג AnySkill Pro
              </p>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #1f2937; font-size: 16px; line-height: 1.6; margin: 0 0 24px 0;">
                אנחנו גאים להודיע לך שהצטרפת למועדון היוקרתי של <strong>AnySkill Pro</strong> — הספקים המובילים באפליקציה.
              </p>
              <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 32px 0;">
                התג הזה מהווה הוכחה לאיכות, למקצועיות ולשירות יוצא הדופן שאתה מעניק ללקוחות שלך. עמדת בכל ארבעת הסטנדרטים הגבוהים ביותר שלנו:
              </p>

              <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="margin-bottom: 32px;">
                ${_criterionRow("⭐", "#fef3c7", "דירוג גבוה", "ציון 4.8 ומעלה ממלקוחות אמיתיים")}
                <tr><td style="height: 12px;"></td></tr>
                ${_criterionRow("🏆", "#fef3c7", "ניסיון מוכח", "20 עסקאות שהושלמו בהצלחה")}
                <tr><td style="height: 12px;"></td></tr>
                ${_criterionRow("⚡", "#dbeafe", "תגובה מהירה", "זמן תגובה ממוצע של פחות מ-15 דקות")}
                <tr><td style="height: 12px;"></td></tr>
                ${_criterionRow("🛡️", "#dcfce7", "אמינות מושלמת", "אפס ביטולים מצדך ב-30 הימים האחרונים")}
              </table>

              <div style="background: linear-gradient(135deg, #eef2ff 0%, #f3e8ff 100%); border-radius: 12px; padding: 24px; margin-bottom: 32px;">
                <h3 style="color: #4338ca; margin: 0 0 12px 0; font-size: 17px; font-weight: 700;">
                  ✨ מה זה אומר עבורך?
                </h3>
                <ul style="color: #4b5563; font-size: 14px; line-height: 1.8; margin: 0; padding-right: 20px;">
                  <li>חשיפה מוגברת בתוצאות החיפוש</li>
                  <li>תג בולט שמשדר אמון ללקוחות חדשים</li>
                  <li>עדיפות בהמלצות האפליקציה</li>
                  <li>כניסה לקהילה של הספקים המובילים</li>
                </ul>
              </div>

              <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                <tr>
                  <td align="center">
                    <a href="${_escape(appLink)}" style="display: inline-block; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); color: #ffffff; text-decoration: none; padding: 16px 48px; border-radius: 12px; font-size: 16px; font-weight: 600; box-shadow: 0 4px 12px rgba(99, 102, 241, 0.3);">
                      צפה בפרופיל שלי
                    </a>
                  </td>
                </tr>
              </table>

              <p style="color: #6b7280; font-size: 13px; line-height: 1.6; margin: 32px 0 0 0; text-align: center;">
                חשוב לדעת: התג ניתן אוטומטית על בסיס הביצועים שלך. כדי לשמור עליו, המשך לספק שירות ברמה הגבוהה ביותר.
              </p>
            </td>
          </tr>

          <tr>
            <td style="background-color: #f9fafb; padding: 24px 40px; text-align: center; border-top: 1px solid #e5e7eb;">
              <p style="color: #9ca3af; font-size: 12px; margin: 0; line-height: 1.6;">
                קיבלת את האימייל הזה כי אתה נותן שירות רשום ב-AnySkill.<br>
                יש לך שאלות? צור קשר עם התמיכה שלנו.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
  return { subject, html };
}

// ── Template 2: Revoke 💙 ──────────────────────────────────────────────────

function buildRevokeEmail({
  providerName,
  revocationReason,
  currentRating,
  completedDeals,
  avgResponseTime,
  cancellations,
  recoveryTip,
  appLink = APP_LINK_DEFAULT,
}) {
  const subject = "עדכון לגבי תג AnySkill Pro שלך";
  const html = `<!DOCTYPE html>
<html dir="rtl" lang="he">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>עדכון תג AnySkill Pro</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Rubik', 'Assistant', Arial, sans-serif; background-color: #f5f5f7; direction: rtl;">
  <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="background-color: #f5f5f7; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="600" style="max-width: 600px; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.08);">

          <tr>
            <td style="background: linear-gradient(135deg, #64748b 0%, #475569 100%); padding: 40px; text-align: center;">
              <div style="font-size: 48px; margin-bottom: 12px;">💙</div>
              <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: 700; line-height: 1.3;">
                שלום ${_escape(providerName)},
              </h1>
              <p style="color: #cbd5e1; margin: 12px 0 0 0; font-size: 16px;">
                עדכון חשוב לגבי התג שלך
              </p>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #1f2937; font-size: 16px; line-height: 1.7; margin: 0 0 20px 0;">
                רצינו לעדכן אותך שתג <strong>AnySkill Pro</strong> הוסר זמנית מהפרופיל שלך.
              </p>
              <p style="color: #4b5563; font-size: 15px; line-height: 1.7; margin: 0 0 28px 0;">
                זה לא סוף הדרך — זו רק הזדמנות לחזור חזק יותר. הנה הסיבה המדויקת ואיך לחזור למעמד:
              </p>

              <div style="background-color: #fef3f2; border-right: 4px solid #f87171; border-radius: 8px; padding: 20px; margin-bottom: 28px;">
                <div style="color: #991b1b; font-size: 14px; font-weight: 700; margin-bottom: 8px;">
                  הקריטריון שלא התקיים:
                </div>
                <div style="color: #7f1d1d; font-size: 15px; line-height: 1.6;">
                  ${_escape(revocationReason)}
                </div>
              </div>

              <h3 style="color: #111827; font-size: 17px; font-weight: 700; margin: 0 0 16px 0;">
                📊 הסטטוס הנוכחי שלך:
              </h3>

              <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="margin-bottom: 32px;">
                ${_metricRow("⭐ דירוג", `${currentRating.toFixed(1)} / 4.8`)}
                <tr><td style="height: 8px;"></td></tr>
                ${_metricRow("🏆 עסקאות שהושלמו", `${completedDeals} / 20`)}
                <tr><td style="height: 8px;"></td></tr>
                ${_metricRow("⚡ זמן תגובה ממוצע", `${avgResponseTime > 0 ? Math.round(avgResponseTime) : "—"} דק'`)}
                <tr><td style="height: 8px;"></td></tr>
                ${_metricRow("🛡️ ביטולים (30 ימים)", `${cancellations}`)}
              </table>

              <div style="background: linear-gradient(135deg, #ecfdf5 0%, #d1fae5 100%); border-radius: 12px; padding: 24px; margin-bottom: 32px;">
                <h3 style="color: #065f46; margin: 0 0 12px 0; font-size: 17px; font-weight: 700;">
                  💪 איך לחזור לתג?
                </h3>
                <p style="color: #047857; font-size: 14px; line-height: 1.7; margin: 0;">
                  ${_escape(recoveryTip)}
                </p>
                <p style="color: #047857; font-size: 14px; line-height: 1.7; margin: 12px 0 0 0;">
                  ברגע שתעמוד שוב בכל הקריטריונים — התג יחזור אליך אוטומטית. אנחנו מאמינים בך! 🚀
                </p>
              </div>

              <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                <tr>
                  <td align="center">
                    <a href="${_escape(appLink)}" style="display: inline-block; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); color: #ffffff; text-decoration: none; padding: 16px 48px; border-radius: 12px; font-size: 16px; font-weight: 600; box-shadow: 0 4px 12px rgba(99, 102, 241, 0.3);">
                      לצפייה בדשבורד שלי
                    </a>
                  </td>
                </tr>
              </table>

              <p style="color: #6b7280; font-size: 13px; line-height: 1.6; margin: 32px 0 0 0; text-align: center;">
                אנחנו כאן לעזור. אם יש לך שאלות או שאתה חושב שחלה טעות — פנה אלינו ונבדוק ביחד.
              </p>
            </td>
          </tr>

          <tr>
            <td style="background-color: #f9fafb; padding: 24px 40px; text-align: center; border-top: 1px solid #e5e7eb;">
              <p style="color: #9ca3af; font-size: 12px; margin: 0; line-height: 1.6;">
                קיבלת את האימייל הזה כי אתה נותן שירות רשום ב-AnySkill.<br>
                יש לך שאלות? צור קשר עם התמיכה שלנו.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
  return { subject, html };
}

// ── HTML helpers ───────────────────────────────────────────────────────────

function _criterionRow(emoji, iconBg, title, subtitle) {
  return `
                <tr>
                  <td style="padding: 16px; background-color: #f9fafb; border-radius: 12px;">
                    <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                      <tr>
                        <td width="48" style="vertical-align: top;">
                          <div style="width: 40px; height: 40px; background-color: ${iconBg}; border-radius: 10px; text-align: center; line-height: 40px; font-size: 20px;">${emoji}</div>
                        </td>
                        <td style="padding-right: 16px;">
                          <div style="color: #111827; font-size: 15px; font-weight: 600; margin-bottom: 4px;">${title}</div>
                          <div style="color: #6b7280; font-size: 14px;">${subtitle}</div>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>`;
}

function _metricRow(label, value) {
  return `
                <tr>
                  <td style="padding: 14px 16px; background-color: #f9fafb; border-radius: 10px;">
                    <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                      <tr>
                        <td style="color: #374151; font-size: 14px; font-weight: 500;">${label}</td>
                        <td align="left" style="color: #111827; font-size: 14px; font-weight: 700;">
                          ${value}
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>`;
}

// Minimal HTML escape — defends against name fields with stray < > & " '.
// We control most inputs server-side, but providerName comes from user
// input so we must sanitise.
function _escape(str) {
  if (str === null || str === undefined) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

module.exports = {
  buildGrantEmail,
  buildRevokeEmail,
  getRevocationCopy,
};
