# ⭐ Gold Heart Logic - לב הזהב

## 🎯 התקציר

הלב הזהב הוא **תג זמני של 30 יום** המוענק לנותני שירות לאחר השלמת התנדבות. הלב מוצג על תמונת הפרופיל שלהם ומתחדש בכל התנדבות חדשה.

---

## 📋 הגדרות

### תרחיש 1 - התנדבות ראשונה
```
משתמש דניאל → משלים התנדבות ראשונה ב-15/05/2026 14:32
↓
goldHeartExpiresAt = 14/06/2026 14:32  (30 יום קדימה)
↓
לב זהב מופיע על תמונת הפרופיל שלו
```

### תרחיש 2 - התנדבות חדשה לפני שפג תוקף
```
דניאל מבצע התנדבות נוספת ב-25/05/2026 16:00 (10 ימים אחרי הראשונה)
↓
goldHeartExpiresAt = 24/06/2026 16:00  (30 יום קדימה מהתאריך החדש!)
↓
הלב מתחדש - עוד 30 יום
```

### תרחיש 3 - אין התנדבות חדשה תוך 30 יום
```
דניאל סיים את ההתנדבות הראשונה ב-15/05/2026 14:32
↓ עוברים 30 יום ללא פעילות
14/06/2026 14:33 - הלב נעלם אוטומטית
↓
הפרופיל לא מציג יותר את הלב הזהב
```

### תרחיש 4 - חזרה אחרי הפסקה ארוכה
```
דניאל לא התנדב כבר 60 יום (הלב נעלם לפני 30 יום)
↓
דניאל מבצע התנדבות חדשה ב-15/07/2026 12:00
↓
goldHeartExpiresAt = 14/08/2026 12:00  (30 יום מהיום)
↓
הלב הזהב חוזר! (מתחיל מחדש)
```

---

## 🔧 יישום טכני

### Firestore Schema

#### users collection
```javascript
{
  uid: "user_abc123",
  displayName: "דניאל בן-עמי",

  // ⭐ השדה החדש הקריטי:
  goldHeartExpiresAt: Timestamp,  // null אם מעולם לא התנדב או הלב פג

  // שדות תומכים שכבר קיימים (לא משנים):
  volunteerTaskCount: 5,           // מספר התנדבויות סה"כ
  communityXP: 10350,              // נקודות XP
  communityBadges: [               // תגי הישג קבועים (לא משתנים!)
    "starter",                     // אחרי התנדבות ראשונה
    "pillar"                       // אחרי 5 התנדבויות
  ],

  // שדות שלא בשימוש יותר (deprecated):
  // volunteerHeart: false,        // ← מוחלף ע"י goldHeartExpiresAt
  // hasActiveVolunteerBadge: false, // ← מוחלף ע"י goldHeartExpiresAt
  // lastVolunteerTaskAt: ...      // ← מוחלף ע"י goldHeartExpiresAt
}
```

### קוד Dart (Flutter)

#### lib/utils/gold_heart_helper.dart
```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class GoldHeartHelper {
  /// בדיקה אם המשתמש בעל לב זהב פעיל
  static bool hasActiveGoldHeart(Timestamp? expiresAt) {
    if (expiresAt == null) return false;
    return expiresAt.toDate().isAfter(DateTime.now());
  }

  /// כמה ימים נותרו עד פקיעת הלב הזהב
  static int? daysUntilExpiry(Timestamp? expiresAt) {
    if (!hasActiveGoldHeart(expiresAt)) return null;
    final diff = expiresAt!.toDate().difference(DateTime.now());
    return diff.inDays;
  }

  /// תאריך הפקיעה (לתצוגה)
  static String? expiryDateFormatted(Timestamp? expiresAt) {
    if (!hasActiveGoldHeart(expiresAt)) return null;
    final date = expiresAt!.toDate();
    return '${date.day} ב${_monthName(date.month)} ${date.year}';
  }

  /// הענקה / חידוש לב זהב (לקרוא לאחר completed)
  static Timestamp grantGoldHeart() {
    return Timestamp.fromDate(
      DateTime.now().add(Duration(days: 30)),
    );
  }

  static String _monthName(int month) {
    const months = [
      'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return months[month - 1];
  }
}
```

#### lib/services/community_hub_service.dart - עדכון
```dart
// בפונקציה שמטפלת באישור התנדבות (כשהפונה מאשר):
Future<void> _handleConfirmation({
  required String volunteerUserId,
  required String taskId,
}) async {
  final volunteerRef = FirebaseFirestore.instance
      .collection('users')
      .doc(volunteerUserId);

  // עדכון אטומי
  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final volunteer = await transaction.get(volunteerRef);

    if (!volunteer.exists) return;

    final currentXP = volunteer.data()?['communityXP'] ?? 0;
    final taskCount = volunteer.data()?['volunteerTaskCount'] ?? 0;

    transaction.update(volunteerRef, {
      // ⭐ הענקה / חידוש לב הזהב - תמיד 30 יום קדימה מעכשיו
      'goldHeartExpiresAt': GoldHeartHelper.grantGoldHeart(),

      // עדכוני XP ומספר התנדבויות
      'communityXP': currentXP + COMMUNITY_XP_REWARD,  // 450
      'volunteerTaskCount': taskCount + 1,
      'lastCompletedTaskAt': FieldValue.serverTimestamp(),
    });
  });
}
```

### Firestore Rules
```javascript
// firestore.rules

match /users/{userId} {
  // קריאה: כולם יכולים לראות את הלב הזהב (פאבליק)
  allow read: if true;

  // עדכון: רק המשתמש בעצמו או Cloud Function (admin)
  allow update: if (
    request.auth.uid == userId &&
    // וידוא שהשדה goldHeartExpiresAt לא נשלח על ידי המשתמש ישירות
    !('goldHeartExpiresAt' in request.resource.data.diff(resource.data).affectedKeys())
  ) || (
    // Cloud Function רשאית לעדכן את הלב הזהב
    request.auth.token.admin == true
  );
}

// כללים על task documents (התנדבויות)
match /community_tasks/{taskId} {
  allow read: if true;
  allow create: if request.auth != null;
  allow update: if request.auth != null && (
    request.auth.uid == resource.data.requesterUserId ||
    request.auth.uid == resource.data.volunteerUserId
  );
}
```

### Cloud Function (חובה!)
המשתמש לא יכול לעדכן את `goldHeartExpiresAt` בעצמו - זה חייב לקרות בצד שרת:

```javascript
// functions/src/community.ts
export const onTaskCompleted = functions.firestore
  .document('community_tasks/{taskId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // רק כש-task עובר ל-completed
    if (before.status !== 'completed' && after.status === 'completed') {
      const volunteerId = after.volunteerUserId;

      // עדכון אטומי של המתנדב
      await admin.firestore()
        .collection('users')
        .doc(volunteerId)
        .update({
          // ⭐ 30 יום קדימה מהיום
          goldHeartExpiresAt: admin.firestore.Timestamp.fromDate(
            new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
          ),

          volunteerTaskCount: admin.firestore.FieldValue.increment(1),
          communityXP: admin.firestore.FieldValue.increment(450),
          lastCompletedTaskAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      // שליחת notification למתנדב
      await sendNotification(volunteerId, {
        title: 'לב זהב פעיל!',
        body: 'התנדבות הושלמה. הלב הזהב יוצג למשך 30 יום.',
      });
    }
  });
```

---

## 🎨 שימוש ב-UI

### בכל מקום שמציג אווטאר של מתנדב
```dart
// במקום:
CircleAvatar(backgroundImage: NetworkImage(user.photoUrl))

// השתמש ב:
AvatarWithGoldHeart(
  photoUrl: user.photoUrl,
  initials: user.initials,
  size: 48,
  goldHeartExpiresAt: user.goldHeartExpiresAt,  // ← קריטי
)
```

### במסך הפרופיל - הצגת מצב הלב הזהב
```dart
if (GoldHeartHelper.hasActiveGoldHeart(user.goldHeartExpiresAt)) {
  final daysLeft = GoldHeartHelper.daysUntilExpiry(user.goldHeartExpiresAt);
  return GoldHeartActiveBanner(
    daysLeft: daysLeft!,
    expiryDate: GoldHeartHelper.expiryDateFormatted(user.goldHeartExpiresAt!),
  );
}
```

---

## 🔍 השפעה על דירוג חיפוש

### lib/services/search_ranking_service.dart
```dart
double calculateRankingScore(VolunteerUser user) {
  double score = baseScore;

  // ⭐ בונוס דירוג למשתמש עם לב זהב פעיל
  if (GoldHeartHelper.hasActiveGoldHeart(user.goldHeartExpiresAt)) {
    score += 50;  // 50 נקודות בונוס
  }

  // (שאר הלוגיקה הקיימת)
  return score;
}
```

זה אומר שמשתמש שעכשיו השלים התנדבות יופיע **גבוה יותר** ב-30 הימים הבאים בכל החיפושים, מה שמגדיל סיכוי ללקוחות → סיכוי להכנסות → תמריץ חוזר להתנדב.

---

## 🐛 Edge Cases לטיפול

### 1. תאריך null
```dart
// תמיד בדוק null:
if (user.goldHeartExpiresAt == null) {
  // לא להציג לב זהב
}
```

### 2. שעון מערכת לא נכון
```dart
// השתמש ב-Firestore server timestamp לעדכונים, לא ב-DateTime.now() של הלקוח
goldHeartExpiresAt: FieldValue.serverTimestamp() + 30 days
```

### 3. ביקורת שלילית (1 כוכב)
```dart
// אופציונלי: ביקורת מתחת ל-3 כוכבים לא מעניקה לב זהב
if (rating >= 3) {
  await grantGoldHeart(volunteerId);
}
```

### 4. אישור אוטומטי (auto-confirm אחרי 24 שעות)
```dart
// גם במקרה זה הלב הזהב מוענק
// כדי לא לאפשר לפונה לעכב את ההענקה
```

### 5. ביטול התנדבות אחרי השלמה
```dart
// אם פונה מבטל את האישור (תרחיש נדיר):
// - הלב הזהב נשאר (לא מבטלים)
// - ה-XP מוחזר
// - ייכנס ללוח דיווחים לבדיקת הונאה
```

---

## ✅ Checklist יישום

- [ ] הוספת שדה `goldHeartExpiresAt: Timestamp` בכל user document
- [ ] יצירת `GoldHeartHelper` class
- [ ] יצירת `AvatarWithGoldHeart` widget
- [ ] עדכון Cloud Function `onTaskCompleted`
- [ ] עדכון Firestore Rules
- [ ] עדכון `search_ranking_service.dart`
- [ ] החלפת כל `CircleAvatar` ל-`AvatarWithGoldHeart` במסכים הבאים:
  - [ ] community_hub_screen.dart
  - [ ] profile_screen.dart
  - [ ] search_results_screen.dart
  - [ ] chat_screen.dart
  - [ ] my_volunteering_screen.dart
- [ ] בדיקת UI במסכים: 06, 07, 09, 15
- [ ] בדיקת flow מקצה לקצה:
  1. השלמת התנדבות → לב זהב מופיע ✓
  2. עוברים 30 יום (זמן מדומה) → לב נעלם ✓
  3. התנדבות חדשה → לב חוזר ל-30 יום ✓
- [ ] הסרת קוד ישן: `volunteerHeart`, `hasActiveVolunteerBadge`

---

## 📊 מטריקות למעקב (Analytics)

מומלץ להוסיף events ל-Firebase Analytics:

```dart
analytics.logEvent('gold_heart_granted', parameters: {
  'user_id': volunteerId,
  'task_id': taskId,
  'is_first_time': taskCount == 1,
});

analytics.logEvent('gold_heart_renewed', parameters: {
  'user_id': volunteerId,
  'days_since_previous': daysSincePrevious,
});

analytics.logEvent('gold_heart_expired', parameters: {
  'user_id': userId,
  'days_active_total': activeDaysTotal,
});
```
