# פרומפט ל-Claude Code: מימוש טאב ניהול באנרים

## הקשר

אני צריך ממך לממש מחדש את טאב "באנרים" במערכת הניהול שלי. זהו שינוי משמעותי - ממשק ניהול ברמה של Linear/Stripe/Vercel, עם פיצ'ר חדש של קרוסלת נותני שירות.

קבצים שצירפתי:
- `mockups/01_banners_list.html` - המסך הראשי (תצוגת רשימת הבאנרים)
- `mockups/02_provider_carousel_builder.html` - מסך בניית קרוסלת נותני שירות
- `docs/01_product_spec.md` - מפרט מלא של המוצר

**חשוב**: המוקאפים הם static HTML עם CSS/JS inline להמחשת המראה וההתנהגות. עליך לממש אותם בצורה שמתאימה לסטאק הטכני הקיים שלי (React/Vue/etc - תתאים).

## עקרונות עבודה

### 1. קרא קודם את המפרט המלא
פתח את `docs/01_product_spec.md` וקרא אותו מתחילה ועד הסוף **לפני שאתה כותב שורת קוד**. המסמך מכיל פלטת צבעים מדויקת, טיפוגרפיה, רווחים, עקרונות עיצוב, ומפרט טכני של כל חלק בממשק.

### 2. שמור על הקיים, אל תמחק
**חשוב מאוד**: כל הבאנרים הקיימים במערכת חייבים להישאר פעילים ולא להימחק. המעבר בין הממשק הישן לחדש צריך להיות חלק - אותם נתונים, תצוגה חדשה.

הבאנרים הקיימים שראיתי בתמונות:
- הכנות לפורים (גרדיאנט סגול, פעיל)
- שירות תיקון מכשירים (תמונה עם מכשירים, פעיל)
- באנר עם אישה מחייכת (פעיל)
- ועוד באנרים שמופיעים בטאב "קרוסל" ו"ארנק"

### 3. מימוש בשלבים - לא הכל בבת אחת
בצע את העבודה בשלבים הבאים, ואחרי כל שלב תן לי הודעה ברורה מה סיימת ומה הלאה. אל תעבור לשלב הבא לפני שסיימת את הנוכחי.

---

## שלבי המימוש

### שלב 1: הכנה וחקירה (לפני כתיבת קוד)
1. סרוק את הפרויקט שלי וזהה:
   - איזה framework אני משתמש בו (React, Vue, Next, Svelte...)
   - איזה state management (Redux, Zustand, Pinia...)
   - איזה CSS approach (Tailwind, CSS modules, styled-components...)
   - איפה נמצא הקוד הקיים של טאב הבאנרים
   - איפה מוגדר schema הדאטה של הבאנרים ב-DB
2. **הצג לי מה מצאת** ואשר את ההבנה שלך לפני שממשיכים.

### שלב 2: עדכון סכימת הנתונים
הוסף לסכימה הקיימת:

```typescript
type BannerType = 'carousel' | 'wallet' | 'popup' | 'top_bar' | 'provider_carousel'; // הוספה!
type BannerStatus = 'active' | 'scheduled' | 'draft' | 'expired';

interface Banner {
  id: string;
  name: string;
  type: BannerType;
  status: BannerStatus;
  createdBy: string;
  createdAt: Date;
  startDate?: Date;
  endDate?: Date;
  location: string; // 'home_page' | 'all_pages' | etc
  // תצוגה
  displayMode: 'gradient' | 'image' | 'video' | 'ai_generated';
  gradientColors?: [string, string];
  imageUrl?: string;
  icon?: string;
  title?: string;
  subtitle?: string;
  cta?: { text: string; action: string };
  // A/B
  hasAbTest: boolean;
  abVariants?: Array<{ id: string; title: string; trafficPercent: number }>;
  // מטריקות
  impressions: number;
  clicks: number;
  ctr: number;
  attributedRevenue?: number;
}

// סוג חדש: קרוסלת נותני שירות
interface ProviderCarouselBanner extends Banner {
  type: 'provider_carousel';
  providerIds: string[]; // IDs של 2-20 נותני שירות
  rotationDuration: number; // 2000-8000 ms, default 4000
  sortMode: 'ai' | 'random' | 'rating' | 'manual';
  transitionAnimation: 'slide' | 'fade' | 'zoom' | 'flip';
  displayOptions: {
    showProfilePic: boolean;
    showRating: boolean;
    showGallery: boolean;
    galleryCount: number; // default 3
    showCategory: boolean;
    showPrice: boolean;
    showAvailability: boolean;
  };
}
```

### שלב 3: יצירת רכיבי UI בסיסיים (Design System)
לפני מסכים, בנה את רכיבי הבסיס:

1. **עיצוב tokens** - קובץ CSS/TS עם כל משתני העיצוב מהמפרט (pallette, typography, spacing)
2. **Button** - עם variants: `primary`, `secondary`, `ghost`
3. **Chip/Badge** - עם variants: `success`, `warn`, `neutral`, `accent`
4. **Toggle** - switch חלק עם אנימציה 180ms
5. **Checkbox** - מעוצב (לא native)
6. **Sparkline** - רכיב SVG שמקבל array של מספרים
7. **MetricCard** - כרטיס KPI בודד
8. **Kbd** - רכיב לקיצור מקלדת

### שלב 4: המסך הראשי (רשימת באנרים)
על בסיס `mockups/01_banners_list.html`:

1. Header עם breadcrumb
2. סרגל KPIs (4 מטריקות)
3. סרגל טאבים (All/Carousel/Provider/Wallet/Popup/TopBar)
4. סרגל מסננים
5. טבלת הבאנרים
   - **חשוב**: הטוגל המהיר חייב לעבוד ולשנות סטטוס מיידית
   - hover states
6. כרטיס תובנת Gemini בתחתית (static כרגע)
7. Footer עם קיצורי מקלדת

### שלב 5: מסך בניית באנר (Wizard)
**אל תבנה עדיין את הוויזארד המלא**. בנה קודם את **סוג הבאנר החדש** (provider_carousel) כי זה הפיצ'ר הכי חשוב שלי.

על בסיס `mockups/02_provider_carousel_builder.html`:

1. Split view: editor משמאל, live preview מימין
2. **חלק 1**: בחירת נותני שירות
   - משוך מ-DB את רשימת הנותנים (טבלת `providers` או דומה)
   - חיפוש עם debounce 300ms
   - סינון לפי קטגוריה ודירוג
   - checkboxes עם סופר ("6 נבחרו")
3. **חלק 2**: הגדרות רוטציה
   - סליידר 2-8 שניות עם presets
   - Radio group ל-sort mode
   - Checkboxes ל-display options
   - Buttons ל-transition animation
4. **חלק 3**: Live preview
   - מסגרת מובייל
   - הבאנר מתחלף באמת עם setTimeout/setInterval
   - בר התקדמות
   - נקודות ניווט
5. כפתורי שמירה/פרסום

### שלב 6: רכיב התצוגה בפועל (ProviderCarouselBanner)
זה הרכיב שהמשתמשים הסופיים יראו באפליקציה. הוא צריך:

1. לקבל `banner.providerIds` ולמשוך את הנתונים של כל נותן
2. לנהל state של `currentIndex`
3. להשתמש ב-`setTimeout` להחלפה אוטומטית
4. **אנימציית fade** של 350ms בין כרטיסים (או לפי בחירת המשתמש)
5. בר התקדמות שמתמלא לאורך זמן ההצגה
6. נקודות ניווט (הפעילה = 14px pill, השאר = 3px dots)
7. אפשרות למשתמש לגעת/ללחוץ כדי:
   - להשהות את הרוטציה
   - לעבור קדימה/אחורה
   - ללחוץ = לעבור לדף הפרופיל (`navigate('/providers/${providerId}')`)
8. **טירגוט חכם** - אם יש משתמש מחובר, שלח את ה-providerIds ל-Gemini API עם ה-userId ו-context, וקבל חזרה את הסדר המומלץ.

### שלב 7: אינטגרציה עם Gemini
המערכת כבר משתמשת ב-Gemini באפליקציה. תבנה שימוש חדש:

**Endpoint חדש**: `POST /api/ai/banner-insights`
- Input: list of banners with metrics
- Output: 1-3 actionable insights + suggested actions
- יקרא כל X זמן (כל כניסה לטאב באנרים, או כל 5 דקות)

**Endpoint נוסף**: `POST /api/ai/smart-provider-order`
- Input: userId, providerIds, context (time of day, location)
- Output: reordered providerIds

### שלב 8: Command Palette (⌘K)
1. Global keyboard listener ל-`⌘K` / `Ctrl+K`
2. Modal centered עם input מעל
3. fuzzy search על באנרים + פעולות
4. keyboard navigation (↑↓↵)
5. קבוצות: "באנרים", "פעולות מהירות", "AI", "ניווט"

### שלב 9: A/B Testing (יכול להיות בשלב נפרד)
- הוספת variants לסכימה
- חלוקת תעבורה במערכת הגשת הבאנרים
- חישוב מובהקות סטטיסטית (Chi-square test)
- UI להשוואה + "פרסם מנצח"

### שלב 10: בדיקות ו-QA
1. **בדוק שכל הבאנרים הקיימים עדיין מוצגים נכון**
2. בדוק פעולות: toggle, edit, delete, duplicate
3. בדוק את הקרוסלה בפועל - רצה, מתחלפת, לחיצה עובדת
4. בדוק RTL בכל הממשק
5. בדוק responsive (desktop/tablet/mobile)
6. בדוק ניגודיות וגישות
7. בדוק ביצועים (אין memory leaks מה-setInterval של הקרוסלה!)

---

## הנחיות חשובות נוספות

### RTL
כל הממשק בעברית RTL. השתמש ב-`dir="rtl"` ברמת הroot של הטאב. שים לב לאייקונים כיווניים (חצים).

### State Management
- משתני עיצוב: CSS variables
- מצב UI (pagination, filters, search): URL params (כדי לאפשר shareable links)
- מצב דאטה: מה שיש בפרויקט (Redux/Zustand/Pinia)

### Type Safety
השתמש ב-TypeScript strict mode. אל תשתמש ב-`any`. הגדר interfaces לכל הדאטה.

### Animations
- rotation של קרוסלה: `setInterval` עם cleanup ב-unmount (חובה!)
- transitions: CSS `transition` (לא JS animations)
- fade בין כרטיסים: 350ms ease
- כל hover/focus: 120-180ms

### אל תעשה:
- ❌ אל תשתמש בצבעים שלא מוגדרים בפלטה
- ❌ אל תשתמש ב-emoji פנימה ב-UI (רק SVG icons)
- ❌ אל תעשה shadows חוץ מ-focus rings
- ❌ אל תשתמש ב-ALL CAPS או Title Case (רק sentence case)
- ❌ אל תוסיף font weight 600/700 (רק 400 ו-500)
- ❌ אל תשכח cleanup ל-setInterval של הקרוסלה

### מה לעשות בסוף כל שלב:
1. תקצר לי מה עשית
2. תגיד מה הקבצים שנוצרו/שונו
3. תגיד מה השלב הבא
4. **תחכה לאישור שלי לפני שאתה ממשיך**

---

## שאלות שאני עשוי לשאול

אם אני שואל "איך זה נראה?", הרץ את האפליקציה והראה screenshots.
אם אני שואל "האם זה עובד?", הרץ את הפיצ'ר בפועל ותדגים.
אם יש לך ספק, תשאל אותי - אל תהמר.

## עדיפות פיצ'רים

אם יש לך מגבלת זמן, סדר עדיפות:
1. **Must have**: טבלת הבאנרים + קרוסלת נותני שירות (מסך בנייה + תצוגה בפועל)
2. **Should have**: KPIs, סינונים, תובנות Gemini
3. **Nice to have**: Command Palette, A/B Testing, לוח שנה

---

## מוכן להתחיל?

אם אתה מבין הכל - תגיד לי "מוכן, מתחיל בשלב 1" ותתחיל לסרוק את הפרויקט.
אם יש לך שאלות - תשאל לפני שאתה מתחיל.
