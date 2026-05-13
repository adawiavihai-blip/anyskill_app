# 🎯 פרומט לקלוד קוד — מערכת ניהול באנרים + VIP מלאה ל-AnySkill

## 🎨 הקשר ומטרה

יש לי אפליקציית AnySkill (Flutter + Firestore + Cloud Functions) — שוק שירותים בעברית RTL.
המערכת הקיימת לניהול באנרים מבולגנת: 3 לשוניות (v1, v2, VIP) שמראות אותו דבר, אין מערכת תשלומים, ספקים לא יכולים לקנות חשיפה.

**אני רוצה לבנות מערכת חדשה ומקצועית שמחליפה לגמרי את הקיים.** העיצוב כבר תוכנן — קובץ HTML מצורף בשם `banners-mockup-v2.html` משמש כ-source of truth ויזואלי. כל הצבעים, פונטים, ריווחים, רכיבים ואנימציות צריכים להיות זהים אליו.

---

## 📁 ארכיטקטורת תיקיות חדשה (החלף את הקיים)

```
lib/
├── screens/
│   └── admin_banners/                    ← תיקייה חדשה (מחק admin_banners_v2)
│       ├── admin_banners_dashboard_screen.dart      ← מסך A
│       ├── banner_edit_screen.dart                  ← מסך B
│       ├── vip_management_screen.dart               ← מסך C
│       ├── vip_payments_screen.dart                 ← מסך D
│       └── subcategory_banners_screen.dart          ← מסך E (חדש)
│
├── widgets/
│   └── banners_admin/                    ← מחק את הקיים, התחל מחדש
│       ├── design_tokens.dart            ← צבעים, פונטים, ריווחים, רדיוסים
│       ├── kpi_card.dart
│       ├── placement_card.dart
│       ├── banner_table_row.dart
│       ├── vip_slot_card.dart
│       ├── waitlist_row.dart
│       ├── payment_row.dart
│       ├── section_card.dart             ← כרטיס accordion למסך עריכה
│       ├── live_preview_phone.dart       ← תצוגה מקדימה במסך עריכה
│       ├── add_vip_modal.dart
│       ├── category_accordion.dart       ← חדש - לתת-קטגוריות
│       ├── subcategory_row.dart          ← חדש
│       ├── default_banner_card.dart      ← חדש - לברירת מחדל גלובלית
│       └── command_palette.dart          ← אופציונלי
│
├── models/
│   ├── banner_model.dart                 ← קיים — להרחיב
│   ├── vip_subscription_model.dart       ← חדש
│   ├── vip_payment_model.dart            ← חדש
│   └── subcategory_banner_model.dart     ← חדש
│
├── services/
│   ├── banners_service.dart              ← קיים — להרחיב
│   ├── vip_subscription_service.dart     ← חדש (CRUD על subscriptions)
│   ├── vip_payment_service.dart          ← חדש (אינטגרציה לתשלומים)
│   ├── vip_rotation_service.dart         ← חדש (לוגיקת רוטציה יומית)
│   └── subcategory_banner_service.dart   ← חדש (תת-קטגוריות)
│
├── screens/
│   ├── provider_profile/
│   │   └── widgets/
│   │       └── vip_upgrade_button.dart   ← חדש — הכפתור בפרופיל הספק
│   │
│   └── subcategory_view/                 ← מסך תת-קטגוריה הקיים בלקוח
│       └── widgets/
│           └── subcategory_banner_widget.dart  ← חדש - להציג את הבאנר
```

---

## 🗄️ סכמת Firestore

### קולקציה קיימת `banners/` — להוסיף שדות
```javascript
{
  // קיים
  id: string,
  title: string,
  subtitle: string,
  imageUrl: string,
  isActive: boolean,
  order: number,
  createdAt: timestamp,

  // חדש — חובה להוסיף
  placement: 'vip_carousel' | 'home_promo' | 'wallet' | 'subcategory',  // היה type — לעבור לפלייסמנט מפורש
  subcategoryId: string?,               // חובה אם placement='subcategory' — מזהה תת-הקטגוריה
  isDefaultGlobalSubcat: boolean,       // אם true, מוצג בכל תת-קטגוריה ללא באנר ייעודי
  designStyle: 'gradient' | 'image' | 'provider_carousel',
  gradientColors: [string, string],     // hex codes
  iconEmoji: string,
  rotationSpeedSec: number,             // למסכי VIP — מהירות החלפה
  rotationOrder: 'ai' | 'random' | 'rating' | 'manual',
  scheduleStart: timestamp?,
  scheduleEnd: timestamp?,
  scheduleHours: { sun:[8,12,16], mon:[...], ... },  // heatmap
  abTestEnabled: boolean,
  abVariantOf: string?,                 // ID של ה-parent לגרסה ב'
  metrics: {
    impressions7d: number,
    clicks7d: number,
    ctr: number,
    revenue: number
  },
  status: 'active' | 'paused' | 'scheduled' | 'draft'
}
```

### קולקציה חדשה `vip_subscriptions/`
```javascript
{
  id: string,
  providerId: string,                   // ref to providers/
  status: 'active' | 'expired' | 'pending' | 'waitlist' | 'admin_comp',
  type: 'paid' | 'admin_comp' | 'trial',
  startDate: timestamp,
  endDate: timestamp,                   // null אם admin_comp קבוע
  autoRenew: boolean,                   // ברירת מחדל true
  pricePerMonth: number,                // 99
  carouselPosition: number?,            // 1-30, או null אם בהמתנה
  waitlistPosition: number?,            // אם בהמתנה
  
  // אם admin_comp:
  compReason: string?,
  compDuration: 'trial_30d' | '1_month' | '3_months' | 'permanent',
  grantedBy: string?,                   // adminId
  grantedAt: timestamp?,
  
  // מטריקות
  totalImpressions: number,
  totalClicks: number,
  
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### קולקציה חדשה `vip_payments/`
```javascript
{
  id: string,
  providerId: string,
  subscriptionId: string,               // ref to vip_subscriptions/
  amount: number,                       // 99
  currency: 'ILS',
  status: 'paid' | 'pending' | 'failed' | 'refunded',
  paymentMethod: 'visa' | 'mastercard' | 'amex' | 'comp',
  cardLast4: string?,
  paymentDate: timestamp,
  failureReason: string?,
  invoiceUrl: string?,
  isRenewal: boolean,
  renewalType: 'auto' | 'manual'
}
```

### קולקציה חדשה `vip_carousel_state/` (סינגלטון)
```javascript
{
  id: 'current',
  maxSlots: 30,
  activeProviderIds: [string],          // עד 30
  waitlistProviderIds: [string],
  rotationMode: 'fixed' | 'fair_daily',  // fair_daily = רוטציה יומית כשיש >30
  lastRotationAt: timestamp,
  totalMonthlyRevenue: number,
  updatedAt: timestamp
}
```

---

## 📱 מסך A: Dashboard (admin_banners_dashboard_screen.dart)

הריפליקציה ב-Flutter של מסך A מהמוקאפ. כולל:

### Topbar
- Breadcrumb: "ניהול / באנרים · Studio"
- Search bar עם placeholder "חפש או הפעל פקודה..." + ⌘K chip
- User chip בצד שמאל

### Page Header
- כותרת "באנרים · Studio" — Fraunces 38px
- Subtitle: "🟢 10 באנרים · 7 פעילים · עדכון אחרון לפני 4 דקות"
- כפתורים: ייצוא דוח · תבניות · באנר חדש (primary)

### KPI Strip (4 כרטיסים)
1. חשיפות 7 ימים — ערך + delta + sparkline
2. הקלקות
3. CTR ממוצע
4. הכנסה מ-VIP — בצבע זהב!

### Placement Cards (3 כרטיסים גדולים)
1. **VIP · Premium** — רקע כהה דרגתי (#1F1B14 → #2A2317) עם זוהר זהב, רקע preview של 4 כרטיסי VIP מיניאטורים שמתחלפים, סטטיסטיקה: ספקים 23/30, CTR 7.2%, הכנסה ₪22.7k
2. **באנרי קידום (Standard)** — רקע לבן, preview של באנר ירוק
3. **באנר ארנק (Wallet)** — רקע לבן, preview של באנר סגול

לחיצה על VIP → goTo `vip_management_screen`. לחיצה על אחרים → סינון בטבלה למטה.

### Tabs לסינון: הכל / פעילים / מתוזמנים / טיוטות
+ Bulk actions bar שמופיע כשיש בחירה
+ פילטרים: מיקום, מיון

### טבלת באנרים (10 הקיימים — סנכרן)
עמודות: Checkbox · באנר (thumb + title + meta) · מיקום (chip צבעוני) · סטטוס (toggle + label) · חשיפות · הקלקות · CTR (עם bar) · הכנסה · actions

חיבור לקיים:
- `banners_service.dart` קיים → להוסיף method `getAllBannersWithMetrics()` שמחזיר את כל הבאנרים עם המטריקות.
- אם בעבר השדה היה `type` במקום `placement` — צריך migration script שמעביר ערכים: `provider_carousel` → `vip_carousel`, אחרים → `home_promo` או `wallet` לפי לוגיקה קיימת.

### AI Insight Card (תחתית)
כרטיס דרגתי עם אייקון זהב, קריאת תובנה מ-Cloud Function (Gemini) שמנתחת ביצועים ומציעה פעולה. לדוגמה: "VIP מציג CTR גבוה ב-56% מהממוצע. נותרו 7 מקומות פנויים. קידום אקטיבי יכול להוסיף ₪693/חודש."

---

## 📱 מסך B: עריכת באנר (banner_edit_screen.dart)

עמוד מלא (לא drawer). Layout: form מימין (1fr) + תצוגה מקדימה sticky משמאל (380px).

### 6 כרטיסי Accordion (section_card.dart)
כל כרטיס: מספר במעגל + כותרת + תיאור + סטטוס + חץ. לחיצה פותחת/סוגרת.

1. **פרטים בסיסיים** — כותרת, תת-כותרת, **בחירת מיקום (3 segments: VIP / בית / ארנק)**, סדר הצגה, קטגוריה
2. **עיצוב ומראה** — סגנון רקע (segments), 8 גרדיאנטים מוכנים לבחירה, image uploader, icon picker (10 emoji)
3. **ספקים בקרוסלה** (רק אם placement=vip_carousel) — חיפוש + רשימת providers עם avatar, rating, category. אפשרות להוסיף/להסיר. נחוץ: integration עם providers/ collection. הצג כמה נבחרו (X/30). לינק לפתוח VIP management
4. **סיבוב והצגה** (רק VIP) — slider של מהירות 2-8 שניות + presets, סדר (AI/אקראי/דירוג/ידני), אנימציה (Fade/Slide/Zoom/3D)
5. **תזמון ופרסום** — date range, switch תזמון חכם, **heatmap שבועי** של 7 ימים × 4 שעות (8/12/16/20) — לחיצה מפעילה/מכבה
6. **Targeting & A/B** — switches: הצג לכל המשתמשים, הפעל A/B Test

### Live Preview Sticky (פאנל ימני, sticky)
- Tabs: 📱 מובייל / 💻 דסקטופ
- Phone frame של iPhone (notch + status bar) — גובה ~280×590
- בתוך המסך: search bar, stories, **כרטיס VIP במלוא תפארתו** (זהב על שחור עם dots מתחתיו), tiles, promo banner
- מתחת: preview info card עם 4 שורות: מיקום, ספקים, סיבוב, חשיפות צפויות

### Sticky Save Bar (תחתית)
"🟢 נשמר אוטומטית · לפני 4 שניות · 3 שינויים מאז הפרסום" + כפתורים: היסטוריה, שמור כטיוטה, פרסם 3 שינויים

---

## 📱 מסך C: ניהול VIP (vip_management_screen.dart)

### VIP Hero (גדול, דרגתי כהה)
- רקע: `linear-gradient(135deg, #1F1B14 0%, #2A2317 50%, #1A1A1A 100%)` + זוהר זהב
- צד שמאל: tag "⭐ VIP · קרוסלת ספקים", כותרת "הקרוסלה היוקרתית של AnySkill", תיאור על 99₪/חודש ו-30 מקומות, 3 סטטיסטיקות (הכנסה, משלמים, רשימת המתנה)
- צד ימין: **טבעת קיבולת** SVG אנימטיבית (160px) — circle בקוטר 68 עם stroke גרדיאנט זהב, מציג 23/30, נותרו 7

### Capacity Bar
פס אופקי שמראה: 16 משלמים (זהב) + 7 חינם-מנהל (שחור) + 7 פנויים (אפור)

### Header + Add VIP button
כפתור זהב "הוסף ספק חינם" → פותח modal `add_vip_modal.dart`

### Tabs: הכל (23) / משלמים (16) / חינם · מנהל (7) / פג בקרוא (3)

### VIP Slot Grid (auto-fill, minmax(280px,1fr))
כל כרטיס:
- אם featured (משלם רגיל): רקע `linear-gradient(135deg, #FAF6EB 0%, white 100%)`, border זהב
- אם admin-comp: ::after עם תג שחור "🎁 חינם · המנהל" בפינה שמאל למעלה
- אם expired: opacity 0.6 + border-style dashed
- Rank badge בפינה ימין למעלה (1, 2, 3...)
- Avatar 48px (עיגול-ריבוע), שם + ✓ verified + קטגוריה + rating
- **שורת זמן** עם אייקון: "נותרו X ימים · עד DD/MM" + tag חידוש (ירוק "↻ אוטו" / כתום "⚠ ידני" / אפור "קבוע")
- 3 stats: חשיפות, קליקים, CTR
- 3 כפתורים: 📊 פרטים · ✏️ ערוך · 🗑 הסר

### Empty Slot (אחד)
ריבוע מקווקו עם "+ הוסף ספק חינם" → פותח modal

### Waitlist Card (תחתית)
כרטיס נפרד עם header אייקון זהב + counter גדול (42).
שורות: position, avatar, שם + meta, סטטוס "✓ שילם", "צפי כניסה", סכום, כפתור "↑ קדם".
"הצג עוד 39 ברשימת ההמתנה →"

---

## 📱 מסך D: תשלומי VIP (vip_payments_screen.dart)

### 4 Stat Cards
1. הכנסה החודש — ₪22,770 (gold)
2. תשלומים פעילים — 23
3. חידוש בחודש הבא — 14
4. פוטנציאל המתנה — ₪41.5k

### Tabs: הכל / שולמו / בהמתנה / נכשלו
+ פילטר חודש

### טבלת תשלומים
עמודות: ספק (avatar+שם+meta) · סכום · סטטוס (paid/pending/failed/comp) · תאריך · אמצעי תשלום (visa/mc dot + last4) · חידוש (אוטו/ידני/קבוע) · ⋯

---

## 📱 מסך E: באנרי תת-קטגוריות (subcategory_banners_screen.dart)

מסך חדש לניהול באנרים שמופיעים בראש מסך תת-קטגוריה. למשל: לוחצים בבית על "כושר וספורט" → "מאמני כושר" → נכנסים לרשימת ספקים → באנר בראש המסך.

### לוגיקה עסקית
- לכל תת-קטגוריה אפשר להגדיר **0+ באנרים ייעודיים**
- אם אין באנר ייעודי → מוצג **באנר ברירת המחדל הגלובלי** (banner אחד מיוחד עם `isDefaultGlobalSubcat=true`)
- אפשר להגדיר 1+ באנרים לאותה תת-קטגוריה (יוצגו בקרוסלה אם יש יותר מאחד)

### מבנה המסך

**Hero (כחול-לבן בהיר):**
- Tag: "📁 חדש · באנרי תת-קטגוריות"
- כותרת: "באנר אישי לכל תת-קטגוריה"
- תיאור על איך זה עובד + ברירת מחדל
- 4 סטטיסטיקות: סה"כ תת-קטגוריות, עם באנר ייעודי, משתמשות בברירת מחדל, CTR ממוצע
- כפתורים: "באנר תת-קטגוריה חדש" + "הגדרות גלובליות"

**Default Banner Card (כרטיס מקווקו מיוחד למעלה):**
- Preview קטן של הבאנר (140×80px)
- Tag "⚡ ברירת מחדל גלובלית"
- כותרת + תיאור עם מספר תת-הקטגוריות שמשתמשות בו
- כפתורים: "ערוך ברירת מחדל" + "סטטיסטיקה"

**Search bar + Filter pills:** הכל / עם באנר ייעודי / בברירת מחדל / CTR גבוה

**Categories Accordion:**
לכל קטגוריה ראשית (כושר וספורט, יופי וטיפוח, בית וגינה, חינוך, עסקים, אירועים) — accordion שנפתח. שורת הראש: emoji + שם הקטגוריה + pill ירוק "X / Y תת-קטגוריות עם באנר" + מספר חשיפות. 

**בתוך הקטגוריה - שורת תת-קטגוריה (subcategory_row.dart):**
Layout: emoji-icon · [שם + meta] · mini-thumbs · status-chip · action-button

- **Mini-thumbs:** עד 3 thumbnails חופפים של הבאנרים שמוגדרים (עיגולים קטנים בצבע הגרדיאנט שלהם)
- **Status chip:** "✓ X באנרים" (ירוק) או "⚡ ברירת מחדל" (אפור)  
- **Action:** "✏️ ערוך" אם יש, או "+ הוסף באנר" אם אין

### Service: subcategory_banner_service.dart

```dart
class SubcategoryBannerService {
  // עבור הלקוח - איזה באנר להציג בראש מסך תת-קטגוריה
  Future<List<BannerModel>> getBannersForSubcategory(String subcategoryId) async {
    // 1. נסה למצוא באנרים ייעודיים לתת-קטגוריה
    final specific = await db.collection('banners')
      .where('placement', isEqualTo: 'subcategory')
      .where('subcategoryId', isEqualTo: subcategoryId)
      .where('status', isEqualTo: 'active')
      .orderBy('order')
      .get();
    
    if (specific.docs.isNotEmpty) {
      return specific.docs.map((d) => BannerModel.fromFirestore(d)).toList();
    }
    
    // 2. אם אין - החזר את ברירת המחדל הגלובלית
    final defaultBanner = await db.collection('banners')
      .where('placement', isEqualTo: 'subcategory')
      .where('isDefaultGlobalSubcat', isEqualTo: true)
      .where('status', isEqualTo: 'active')
      .limit(1)
      .get();
    
    return defaultBanner.docs.map((d) => BannerModel.fromFirestore(d)).toList();
  }
  
  // עבור המנהל - סטטיסטיקות לכל קטגוריה
  Future<Map<String, SubcategoryStats>> getCategoryStats() async {
    // מחזיר לכל קטגוריה: כמה תת-קטגוריות, כמה עם באנר, סך חשיפות
  }
}
```

### Widget בלקוח: subcategory_banner_widget.dart

ב-`screens/subcategory_view/` (המסך הקיים שמראה ספקים בתת-קטגוריה):

```dart
class SubcategoryBannerWidget extends StatelessWidget {
  final String subcategoryId;
  
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BannerModel>>(
      future: SubcategoryBannerService().getBannersForSubcategory(subcategoryId),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return SizedBox.shrink();
        
        if (snap.data!.length == 1) {
          // באנר אחד - הצג קבוע
          return _SingleBannerCard(banner: snap.data!.first);
        } else {
          // מספר באנרים - קרוסלה
          return _BannerCarousel(banners: snap.data!);
        }
      },
    );
  }
}
```

הוסף את הוויג'ט בראש מסך תת-הקטגוריה (לפני רשימת הספקים), עם padding תקני.

### עדכון מסך B (Banner Edit)

ב-Section 1 (פרטים בסיסיים) - הוסף `subcategory` לoptions של placement segment:

```dart
SegmentedControl(
  options: ['VIP', 'באנר בית', 'תת-קטגוריה', 'ארנק'],
  onChange: (value) => setState(() => placement = value),
)
```

אם placement='subcategory' → הצג שדה נוסף "בחר תת-קטגוריה" עם dropdown מקושר ל-categories collection. אם המשתמש מסמן "ברירת מחדל גלובלית" → השדה נעלם והבאנר יוגדר כ-default.

---



### 1. כפתור VIP בפרופיל הספק (vip_upgrade_button.dart)

ב-screens/provider_profile/ — להוסיף widget בולט:

```dart
// אם הספק לא ב-VIP:
ElevatedButton.icon(
  icon: Icon(Icons.star),
  label: Text('הצטרף ל-VIP · ₪99/חודש'),
  style: gold gradient (#B89855 → #8C6F36),
  onPressed: () => Navigator.push(VipUpgradePaymentScreen()),
)

// אם הספק כבר ב-VIP פעיל:
Container(
  decoration: gold border,
  child: Column([
    Text('⭐ חבר VIP פעיל'),
    Text('נותרו X ימים'),
    Switch('חידוש אוטומטי', value: subscription.autoRenew),
    TextButton('בטל מנוי'),
  ]),
)

// אם בהמתנה:
Container(
  child: Column([
    Text('🕒 ברשימת המתנה'),
    Text('מקום מספר X · צפי כניסה: DD/MM'),
  ]),
)
```

### 2. תהליך תשלום (vip_payment_service.dart)

**המלצה: השתמש ב-Stripe או PayPlus (ספק תשלומים ישראלי).** אינטגרציה דרך Cloud Function `processVipPayment`.

```dart
Future<void> processVipPayment(String providerId) async {
  // 1. קרא ל-Cloud Function שיוצרת payment intent
  // 2. הצג ל-user את payment sheet (Stripe SDK)
  // 3. בהצלחה: 
  //    - צור document ב-vip_payments/ עם status='paid'
  //    - בדוק כמות במקומות בvip_carousel_state
  //    - אם < 30: צור subscription סטטוס 'active', הוסף ל-activeProviderIds
  //    - אם >= 30: צור subscription סטטוס 'waitlist', הוסף לסוף waitlistProviderIds
  //    - הצג למשתמש: "התקבלת ל-VIP! מופיע מיד" / "ברשימת המתנה, מקום #X"
}
```

### 3. Cloud Function: בדיקת חיוב חודשית

`scheduledMonthlyVipBilling` — Pub/Sub schedule כל יום ב-03:00:

```javascript
async function scheduledMonthlyVipBilling() {
  const expiringSubs = await db.collection('vip_subscriptions')
    .where('status', '==', 'active')
    .where('endDate', '<=', new Date())
    .get();
  
  for (const sub of expiringSubs.docs) {
    if (sub.data().autoRenew) {
      // נסה לחייב את הכרטיס
      const result = await chargeStripe(sub.data().providerId, 99);
      if (result.success) {
        await sub.ref.update({
          endDate: addMonth(sub.data().endDate),
          updatedAt: now()
        });
        await createPaymentRecord(sub.id, 'paid', 'auto');
        await sendNotification(sub.data().providerId, 'vip_renewed');
      } else {
        // חיוב נכשל
        await sub.ref.update({ status: 'expired' });
        await createPaymentRecord(sub.id, 'failed', 'auto');
        await removeFromCarousel(sub.data().providerId);
        await promoteFromWaitlist();  // קדם את הראשון בהמתנה
        await sendNotification(sub.data().providerId, 'vip_payment_failed');
      }
    } else {
      // חידוש ידני בלבד — שלח תזכורת לפני, ואם פג — הסר
      const daysLeft = daysBetween(now(), sub.data().endDate);
      if (daysLeft === 3) await sendReminder(sub.data().providerId, '3_days_left');
      if (daysLeft === 1) await sendReminder(sub.data().providerId, '1_day_left');
      if (daysLeft <= 0) {
        await sub.ref.update({ status: 'expired' });
        await removeFromCarousel(sub.data().providerId);
        await promoteFromWaitlist();
      }
    }
  }
}
```

### 4. לוגיקת רוטציה הוגנת (vip_rotation_service.dart)

**הבעיה:** מה אם יש 1000 ספקים שרוצים VIP?  
**הפתרון:** רק 30 בקרוסלה בכל רגע, אבל **רוטציה יומית בין כל המשלמים**.

```dart
// Cloud Function: dailyVipRotation — Pub/Sub כל יום ב-04:00
async function dailyVipRotation() {
  const allPaidSubs = await db.collection('vip_subscriptions')
    .where('status', 'in', ['active', 'waitlist'])
    .where('type', '==', 'paid')
    .orderBy('startDate', 'asc')  // FIFO
    .get();
  
  if (allPaidSubs.size <= 30) {
    // לא צריך רוטציה — כולם מקבלים מקום
    return;
  }
  
  // יש יותר מ-30 משלמים — סבב יומי
  const adminCompIds = await getAdminCompProviderIds();  // אלה תמיד נשארים
  const slotsForPaid = 30 - adminCompIds.length;
  
  // יום בחודש (1-30) → קח את ה-slotsForPaid הבאים מהרשימה הסיבובית
  const dayOfMonth = new Date().getDate();
  const startIdx = ((dayOfMonth - 1) * slotsForPaid) % allPaidSubs.size;
  const todaysProviders = [];
  for (let i = 0; i < slotsForPaid; i++) {
    todaysProviders.push(allPaidSubs.docs[(startIdx + i) % allPaidSubs.size].data().providerId);
  }
  
  // עדכן את vip_carousel_state
  await db.collection('vip_carousel_state').doc('current').update({
    activeProviderIds: [...adminCompIds, ...todaysProviders],
    lastRotationAt: now(),
    rotationMode: 'fair_daily'
  });
  
  // עדכן את כל ה-subscriptions עם carouselPosition
  // ...
}
```

**הסבר ללקוח (במסך VIP):** "כל ספק שמשלם מובטח להופיע בקרוסלה לפחות פעם אחת בכל יום בממוצע. עם 60 משלמים: 30 מופיעים בכל פעם, מתחלפים יומית — כל אחד מקבל ~50% זמן הצגה."

### 5. הוספה ידנית של מנהל (Admin Comp)

ב-add_vip_modal.dart:
```dart
Future<void> addAdminCompVip(String providerId, String duration, String reason) async {
  final endDate = duration == 'permanent' ? null : addDuration(now(), duration);
  
  await db.collection('vip_subscriptions').add({
    providerId,
    status: 'active',
    type: 'admin_comp',
    startDate: now(),
    endDate,
    autoRenew: false,
    pricePerMonth: 0,
    compReason: reason,
    compDuration: duration,
    grantedBy: currentAdminId,
    grantedAt: now(),
  });
  
  // הוסף לקרוסלה (admin-comp תמיד יכול גם אם הקרוסלה מלאה — מגדיל את maxSlots זמנית)
  await addToCarousel(providerId, isComp: true);
  
  // שלח התראה לספק
  if (sendNotificationEnabled) {
    await sendNotification(providerId, 'vip_granted_by_admin', { reason });
  }
}
```

---

## 🎨 Design Tokens (design_tokens.dart)

צריך כקובץ Dart נפרד שכל הקוד ישתמש בו:

```dart
class AppColors {
  static const bg = Color(0xFFFAFAF7);
  static const bgElevated = Color(0xFFFFFFFF);
  static const bgSubtle = Color(0xFFF4F3EF);
  static const ink = Color(0xFF1A1A1A);
  static const ink2 = Color(0xFF3A3A38);
  static const ink3 = Color(0xFF6B6B68);
  static const ink4 = Color(0xFF9A9A95);
  static const success = Color(0xFF1A7F4E);
  static const successBg = Color(0xFFE8F5EE);
  static const warn = Color(0xFFB8651A);
  static const warnBg = Color(0xFFFBF1E2);
  static const danger = Color(0xFFB83A2A);
  static const dangerBg = Color(0xFFFBEBE7);
  static const gold = Color(0xFFB89855);
  static const goldSoft = Color(0xFFF5EDD9);
  static const goldDeep = Color(0xFF8C6F36);
  
  static const vipGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF1F1B14), Color(0xFF2A2317), Color(0xFF1A1A1A)],
  );
  static const goldGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFFB89855), Color(0xFF8C6F36)],
  );
}

class AppRadius {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

class AppSpacing {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s7 = 32.0;
  static const s8 = 40.0;
}

class AppTextStyles {
  static const display = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 38,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.95,
    height: 1.1,
  );
  static const h2 = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.44,
  );
  // ... להוסיף לכל הסגנונות במוקאפ
}
```

הוסף את הפונטים ל-`pubspec.yaml`:
```yaml
fonts:
  - family: Fraunces
    fonts:
      - asset: assets/fonts/Fraunces-Regular.ttf
      - asset: assets/fonts/Fraunces-Medium.ttf, weight: 500
  - family: Heebo
    fonts:
      - asset: assets/fonts/Heebo-Regular.ttf
      - asset: assets/fonts/Heebo-Medium.ttf, weight: 500
      - asset: assets/fonts/Heebo-SemiBold.ttf, weight: 600
```

---

## 🔄 Migration של 10 הבאנרים הקיימים

צור Cloud Function חד-פעמית `migrateBannersToV2`:

```javascript
async function migrateBannersToV2() {
  const oldBanners = await db.collection('banners').get();
  
  for (const doc of oldBanners.docs) {
    const data = doc.data();
    const placement = mapTypeToPlacement(data.type);  
    // provider_carousel → vip_carousel
    // home_carousel → home_promo
    // wallet_top → wallet
    // (subcategory באנרים ייווצרו ידנית במסך החדש)
    
    await doc.ref.update({
      placement,
      subcategoryId: null,
      isDefaultGlobalSubcat: false,
      designStyle: data.imageUrl ? 'image' : 'gradient',
      gradientColors: data.gradientColors || ['#6B4FA8', '#4A3580'],  // default
      iconEmoji: data.iconEmoji || '📢',
      rotationSpeedSec: 4,
      rotationOrder: 'ai',
      scheduleHours: { /* default = always on */ },
      abTestEnabled: false,
      metrics: {
        impressions7d: 0,  // ימולא ע"י analytics
        clicks7d: 0,
        ctr: 0,
        revenue: 0
      },
      status: data.isActive ? 'active' : 'paused'
    });
  }
}
```

**הרץ פעם אחת ידנית מ-Firebase Console** ואז כל הבאנרים יראו במסך החדש מיד.

**בנוסף - צור באנר ברירת מחדל לתת-קטגוריות:**
```javascript
// סקריפט נפרד - הרץ פעם אחת
async function createDefaultSubcategoryBanner() {
  await db.collection('banners').add({
    title: 'המומחים הטובים בתת-הקטגוריה',
    subtitle: 'מצא את הספק המתאים לך',
    placement: 'subcategory',
    subcategoryId: null,
    isDefaultGlobalSubcat: true,
    designStyle: 'gradient',
    gradientColors: ['#2C5BA8', '#4A7BCF'],
    iconEmoji: '⭐',
    status: 'active',
    isActive: true,
    order: 0,
    createdAt: now()
  });
}
```

---

## ✅ סדר עבודה מוצע

1. **שלב 1: יסודות** (1-2 ימים)
   - צור `design_tokens.dart`
   - הוסף פונטים ל-pubspec
   - בנה `section_card.dart`, `kpi_card.dart`, `placement_card.dart`
   - הרץ migration script

2. **שלב 2: Dashboard** (1 יום)
   - בנה `admin_banners_dashboard_screen.dart` — הצג את 10 הבאנרים הקיימים
   - חבר Tabs, Filters, Bulk actions
   - חבר ל-`banners_service.dart` הקיים

3. **שלב 3: Banner Edit** (2 ימים)
   - בנה `banner_edit_screen.dart` עם 6 sections
   - בנה `live_preview_phone.dart` — חי, מתעדכן עם כל שינוי
   - תזמון heatmap

4. **שלב 4: VIP Backend** (3 ימים)
   - מודלים ושירותים: `vip_subscription_service`, `vip_payment_service`, `vip_rotation_service`
   - Cloud Functions: `processVipPayment`, `scheduledMonthlyVipBilling`, `dailyVipRotation`
   - אינטגרציה לתשלומים (Stripe / PayPlus)
   - כפתור VIP בפרופיל הספק

5. **שלב 5: VIP Admin Screens** (2 ימים)
   - `vip_management_screen.dart` עם hero, capacity ring, slot grid, waitlist
   - `vip_payments_screen.dart` עם stats + table
   - `add_vip_modal.dart`

6. **שלב 6: ליטוש** (1 יום)
   - אנימציות, transitions, hover states
   - Empty states, loading states
   - בדיקת RTL בכל המסכים

---

## 🎯 קריטריונים להצלחה

- ✅ כל 10 הבאנרים הקיימים מוצגים במסך Dashboard החדש מיד אחרי deploy
- ✅ ספק יכול ללחוץ "הצטרף ל-VIP" בפרופיל ולשלם ₪99
- ✅ אחרי תשלום מוצלח, הספק מופיע בקרוסלה תוך פחות מ-10 שניות
- ✅ אם מלא (30 ספקים): נכנס לרשימת המתנה ויודע את מספר המקום שלו
- ✅ סוף החודש: חידוש אוטומטי כברירת מחדל; אם הספק כיבה — הוא מקבל התראות לפני שפג
- ✅ מנהל יכול להוסיף ספק לחינם דרך כפתור זהב במסך VIP, עם בחירת תוקף
- ✅ מנהל רואה רשימה ברורה של מי שילם / מי בהמתנה / מי בחינם, עם זמן שנותר
- ✅ **תת-קטגוריות:** כל מסך תת-קטגוריה בלקוח מציג באנר בראש (ייעודי או ברירת מחדל)
- ✅ **תת-קטגוריות:** מנהל יכול לראות את כל 52 התת-קטגוריות במבט hierarchy ולהוסיף/לערוך באנר לכל אחת
- ✅ **תת-קטגוריות:** עריכת ברירת המחדל הגלובלית משפיעה על כל 40 התת-קטגוריות שאין להן באנר ייעודי
- ✅ עיצוב 1:1 למוקאפ — שום פשרות על פונטים, ריווחים, צבעים, רדיוסים, אנימציות

---

## 📎 קבצים מצורפים
- `banners-mockup-v2.html` — המוקאפ המלא (source of truth ויזואלי)
- כל מסך במוקאפ ניתן לראות ע"י מעבר בין tabs בסיידבר השמאלי

---

**הערה חשובה:** כל UI text בעברית. כל לוגיקה ב-Hebrew RTL. כל ה-currency ב-₪. Date format: DD/MM/YYYY.
