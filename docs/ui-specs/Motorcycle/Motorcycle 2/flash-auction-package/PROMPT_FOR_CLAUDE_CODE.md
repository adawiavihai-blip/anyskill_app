# משימה: בניית פיצ'ר Flash Auction לכפתור "מצא גרר דחוף"

## הקשר

באפליקציה כבר קיים פיצ'ר "גרר אופנועים" (CSM #8 שבנינו) — נותני שירות יכולים לסמן את עצמם בתת-קטגוריה הזו, ולקוחות רואים אותם בעמוד התת-קטגוריה.

עכשיו אנחנו מוסיפים שכבה נוספת: **Flash Auction** — מצב חירום בלחיצה אחת.

**הכפתור "מצא גרר דחוף" כבר קיים בעמוד התת-קטגוריה** (ליד כפתור "מפה"), אבל הוא לא עושה כלום. המשימה שלך: לחבר אותו לפיצ'ר חדש ומלא.

## איך זה עובד (Flow Overview)

### צד הלקוח:
1. **לוחץ "מצא גרר דחוף"** מעמוד התת-קטגוריה
2. **מסך 1: אבחון תקלה** — בוחר אחת מ-6 אפשרויות (תקלת מנוע, תאונה, פנצ'ר, מצבר מת, גלגלים נעולים, אחר)
3. **מסך 2: מיקום ותיעוד** — מסמן על מפה (Wolt-style) או מקליד כתובת. למעלה גם יעד. תמונות = מומלץ, לא חובה
4. **לוחץ "שדר את הקריאה"** — נוצר מסמך `flash_auctions/{auctionId}` ב-Firestore + נשלחת התראת FCM לכל הגרריסטים שסימנו "גרר אופנועים" ב-15 ק"מ
5. **מסך 3: המתנה (radar)** — סטטיסטיקות חיות (כמה קיבלו, כמה בודקים, רדיוס נוכחי)
6. **מסך 4: הצעות** — ככל שגרריסטים מאשרים, ההצעות מופיעות בזמן אמת. הלקוח רואה כרטיס פרופיל קיים + ETA + מחיר. בוחר אחת
7. **אחרי בחירה** — נכנסים לזרימת התשלום הקיימת (Pay & Secure) → המסך מעקב הקיים

### צד נותן השירות (גרריסט):
1. **התראת FCM** מגיעה ("קריאת גרר חדשה — 8.4 ק"מ ממך")
2. **לוחץ → נכנס ללשונית "הזדמנויות" הקיימת** עם כרטיס הקריאה החדש
3. **רואה:** מיקום הלקוח (כתובת + מפה), יעד, סוג תקלה, תמונות אם יש
4. **לא רואה:** טלפון, שם מלא, אפשרות הודעה. רק מידע אנונימי
5. **המערכת חישבה אוטומטית** את המחיר לפי הפרופיל שלו (base + km × rate + תוספת לילה אם רלוונטי + תוספת חירום 50%)
6. **מילוי שדה אחד**: "תוך כמה זמן תגיע?" (בדקות)
7. **לוחץ "אשר ושלח הצעה"** — ההצעה נשלחת ללקוח. גרריסט אחר עדיין יכול לשלוח גם
8. **אם הלקוח בחר אותו** — מקבל התראה + מועבר למסך מעקב הקיים

## ייחודיות הפיצ'ר

❗ **הגרריסט לא קובע מחיר** — המערכת קובעת לפי המחירים שכבר הוגדרו בפרופיל שלו. הוא רק מאשר.
❗ **הגרריסט קובע רק ETA** — תוך כמה דקות יגיע. זה ההבדל המרכזי בין הצעות.
❗ **לקוח לא רואה פרטי קשר** עד הבחירה — מונע ספאם וגניבת לקוחות מחוץ למערכת.
❗ **כרטיסי פרופיל קיימים** — אל תיצור עיצוב חדש להצעות. השתמש ב-`ProviderProfileCard` הקיים, רק הוסף רצועת ETA + מחיר + כפתור "בחר" בתחתית.

## מה צריך לבנות

### חדש (Flutter screens):

1. **`flash_auction_issue_screen.dart`** — מסך 1 (אבחון תקלה)
2. **`flash_auction_location_screen.dart`** — מסך 2 (מפה אינטראקטיבית + כתובות + תמונות אופציונליות)
3. **`flash_auction_searching_screen.dart`** — מסך 3 (רדאר + סטטיסטיקות חיות)
4. **`flash_auction_offers_screen.dart`** — מסך 4 (רשימת הצעות חיה עם כרטיסי פרופיל קיימים)
5. **`flash_auction_provider_card.dart`** — הקומפוננטה שמופיעה בלשונית "הזדמנויות" אצל הגרריסט (כרטיס הקריאה + שדה ETA + כפתור אישור)
6. **`flash_auction_safety_dialog.dart`** — דיאלוג בטיחות שנפתח מכפתור "אתה במקום בטוח?"

### חדש (Models + Services):

7. **`lib/models/flash_auction.dart`** — `FlashAuction`, `FlashAuctionOffer`, `IssueType`, `AuctionStatus`
8. **`lib/services/flash_auction_service.dart`** — יצירת auction, שליפת auctions פעילים לגרריסט, שליחת הצעה, בחירת הצעה, ביטול
9. **`lib/services/flash_auction_pricing_service.dart`** — חישוב מחיר אוטומטי לפי פרופיל הגרריסט (משתמש בלוגיקה הקיימת מ-`MotorcycleTowBookingService.calculate()`)
10. **`lib/services/flash_auction_dispatch_service.dart`** — שליחת FCM לגרריסטים ברדיוס, גלגול שכבות (5km → 10km → 15km)

### חדש (Cloud Functions):

11. **`functions/flash_auction_dispatch.ts`** — Cloud Function: כשנוצר auction חדש, שולח FCM לגרריסטים. אחרי 30s אם אין הצעות → מרחיב רדיוס. אחרי 2 דקות → סוגר auction אם אין הצעות
12. **`functions/flash_auction_offer_received.ts`** — Trigger: כשגרריסט שולח הצעה, מעדכן את ה-auction ושולח FCM ללקוח

### עדכונים לקבצים קיימים:

13. **`subcategory_screen.dart`** (או איך שקוראים לעמוד התת-קטגוריה אצלך) — חיווט הכפתור "מצא גרר דחוף" שכבר קיים → שיפתח את `FlashAuctionIssueScreen`
14. **`opportunities_screen.dart`** (לשונית הזדמנויות הקיימת) — הוספת stream שמשלב את ה-auctions הפעילים מהפיצ'ר הזה לרשימה הקיימת. כל auction יוצג כ-`FlashAuctionProviderCard`
15. **`firestore.rules`** — הוספת rules ל-`flash_auctions/{auctionId}` (ראה למטה)

## מבנה Firestore

```
flash_auctions/{auctionId}
  ├── customerId: string
  ├── createdAt: timestamp
  ├── status: 'searching' | 'has_offers' | 'matched' | 'cancelled' | 'expired'
  ├── issueType: 'engine_fault' | 'accident' | 'flat_tire' | 'dead_battery' | 'wheels_locked' | 'other'
  ├── pickupLocation: { address, lat, lng }
  ├── dropoffLocation: { address, lat, lng }
  ├── distanceKm: number
  ├── photos: string[] (Storage URLs, אופציונלי)
  ├── currentRadiusKm: number (5 → 10 → 15)
  ├── notifiedProviderIds: string[]
  ├── selectedOfferId: string | null
  ├── matchedJobId: string | null (אחרי שעובר ל-Pay & Secure)
  └── expiresAt: timestamp (createdAt + 2 דקות)

flash_auctions/{auctionId}/offers/{offerId}
  ├── providerId: string
  ├── providerName: string (snapshot — חיתוך מהפרופיל)
  ├── providerRating: number
  ├── providerJobsCount: number
  ├── etaMinutes: number ← הגרריסט קובע
  ├── totalPrice: number ← מחושב אוטומטית
  ├── priceBreakdown: { base, km, kmTotal, nightSurcharge, emergencySurcharge }
  ├── createdAt: timestamp
  └── status: 'pending' | 'selected' | 'rejected'
```

## אלגוריתם חישוב מחיר

נמצא בכל פרופיל גרריסט תחת `motorcycleTowProfile`:
```dart
final breakdown = MotorcycleTowBookingService.calculate(
  basePrice: provider.pricing.basePrice,           // ברירת מחדל ₪180
  pricePerKm: provider.pricing.pricePerKm,         // ברירת מחדל ₪4.5
  distanceKm: auction.distanceKm,
  isNightTime: _isWithinNightHours(provider.pricing),
  nightSurchargePercent: provider.pricing.nightSurchargePercent,  // 25%
  isEmergency: true, // תמיד true ב-Flash Auction
  emergencySurchargePercent: provider.pricing.emergencySurchargePercent, // 50%
);
// breakdown.total → המחיר שיוצג לגרריסט (ולאחר אישור — ללקוח)
```

## אלגוריתם דירוג ההצעה "המומלצת ביותר"

ככל שיש יותר הצעות, ה-UI מסמן אחת כ-"המומלצת ביותר". הניקוד:

```dart
double score = 0;
score += (60 - offer.etaMinutes) * 2;             // ETA נמוך = יותר נקודות
score += (1000 - offer.totalPrice) * 0.05;        // מחיר נמוך = יותר נקודות
score += offer.providerRating * 20;               // דירוג × 20
score += min(offer.providerJobsCount, 200) * 0.1; // ניסיון, מקסימום 200 גרירות
// המקסימום score → המומלץ ביותר (badge ירוק)
```

## אלגוריתם שליחת התראות (Layered Dispatch)

ב-Cloud Function `flash_auction_dispatch.ts`:

```
T+0:    שלח FCM ל-5 הקרובים ביותר ברדיוס 5 ק"מ
T+30s:  אם 0 הצעות → הרחב ל-10 ק"מ + שלח לעוד 10 גרריסטים
T+60s:  אם 0 הצעות → הרחב ל-15 ק"מ + שלח לכל מי שעוד לא קיבל
T+120s: אם 0 הצעות → סגור auction עם status='expired' + הצע ללקוח לעבור למצב "בקשת הצעות" רגיל
```

**Geo-query**: השתמש ב-`geoflutterfire2` או חישוב Haversine אם כבר משתמשים בו ב-`dog_walks` (אותה תבנית).

## Firestore Rules

```
match /flash_auctions/{auctionId} {
  allow read: if request.auth != null && (
    resource.data.customerId == request.auth.uid ||
    request.auth.uid in resource.data.notifiedProviderIds
  );
  allow create: if request.auth != null
    && request.resource.data.customerId == request.auth.uid;
  allow update: if request.auth != null && (
    resource.data.customerId == request.auth.uid ||
    request.auth.uid in resource.data.notifiedProviderIds
  );

  match /offers/{offerId} {
    allow read: if request.auth != null && (
      get(/databases/$(database)/documents/flash_auctions/$(auctionId)).data.customerId == request.auth.uid ||
      resource.data.providerId == request.auth.uid
    );
    allow create: if request.auth != null
      && request.resource.data.providerId == request.auth.uid;
  }
}
```

## מה לא לבנות

❌ אל תיצור chat — הצ'אט הקיים יופעל אוטומטית אחרי שלקוח בוחר הצעה
❌ אל תיצור מסך מעקב חי — הקיים (`MotorcycleTowTrackingScreen`) יקבל את המידע מה-auction
❌ אל תיצור Pay & Secure חדש — הקיים יקבל את המחיר מההצעה שנבחרה
❌ אל תיצור כרטיסי פרופיל חדשים — השתמש ב-`ProviderProfileCard` הקיים
❌ אל תיצור לשונית הזדמנויות חדשה — הקיימת מקבלת רק רכיב חדש (`FlashAuctionProviderCard`)
❌ אל תיצור AI כרגע — חישוב מחיר הוא מתמטי טהור

## חיבורים לזרימה הקיימת

```
[כפתור "מצא גרר דחוף"]
        ↓ קיים, רק לחבר
[FlashAuctionIssueScreen] (חדש)
        ↓
[FlashAuctionLocationScreen] (חדש)
        ↓ יוצר flash_auction doc
[FlashAuctionSearchingScreen] (חדש)
        ↓ stream של offers
[FlashAuctionOffersScreen] (חדש)
        ↓ לקוח בוחר הצעה
[Pay & Secure] (קיים) ← מקבל priceBreakdown מההצעה
        ↓ אחרי תשלום
[MotorcycleTowTrackingScreen] (קיים) ← מקבל matchedJobId
```

## דברים לשים לב אליהם

1. **התראות FCM**: לגרריסטים — title="קריאת גרר חדשה", body="X ק"מ ממך · ₪Y הכנסה משוערת", action=פתח לשונית הזדמנויות.
2. **Real-time**: מסך ההמתנה (radar) צריך להיות `StreamBuilder` שעוקב אחרי ה-`offers` subcollection.
3. **Race condition**: כש-2 לקוחות בוחרים את אותו גרריסט בו-זמנית — תשתמש ב-Firestore transaction.
4. **טיימר 60 שניות**: במסך המתנה אצל הלקוח, וגם אצל הגרריסט (Cloud Function ידאג ל-expiration).
5. **גרריסט שלא פנוי**: אם הגרריסט באמצע גרירה אחרת, הוא לא מקבל התראה (בדוק `provider.activeJob` field).
6. **שמור ETA כהצהרה**: אם הגרריסט אמר 12 דקות אבל מתעכב, הלקוח יראה את הזמן האמיתי דרך GPS tracking הקיים אחרי המאצ'.

## Mockups

ראה את הקובץ `mockups/customer-flow.html` — שם 4 מסכי הלקוח עם כל הסטיילים, האינטראקציות והאנימציות. השתמש בו כמקור אמת לעיצוב, אבל תיישם ב-Flutter עם הקונבנציות של הפרויקט (לפי הפטרן של 7 ה-CSMs הקיימים).

## Output סיום

אחרי שתסיים, ספק לי:
1. רשימה של כל הקבצים החדשים שיצרת
2. רשימה של הקבצים הקיימים ששינית (מה שונה ולמה)
3. צילום מסך של flutter analyze (חייב 0 issues)
4. הוראות deploy (firebase deploy + flutter build)
5. תזכורת אם יש צעדים שדורשים פעולה ידנית שלי (rules deploy, FCM setup, וכו')

בהצלחה!
