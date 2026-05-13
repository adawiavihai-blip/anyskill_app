# 🎨 Design System - AnySkill Community

מערכת עיצוב מלאה למודול הקהילה. כל הצבעים, הטיפוגרפיה, הריווחים והקומפוננטות מסודרים כאן.

---

## 🎨 פלטת צבעים

### צבעי בסיס
```dart
Color primaryBlack = Color(0xFF18181B);     // כפתורים ראשיים, טקסט ראשי
Color primaryWhite = Color(0xFFFFFFFF);     // רקע ראשי
Color background = Color(0xFFF5F5F4);       // רקע משני (מחוץ למסך)
Color surface = Color(0xFFFAFAF9);          // רקע שדות, כרטיסים משניים
```

### צבעי טקסט
```dart
Color textPrimary = Color(0xFF18181B);      // טקסט ראשי - כותרות וטקסט עיקרי
Color textSecondary = Color(0xFF52525B);    // טקסט משני - תיאורים ופירוטים
Color textTertiary = Color(0xFF71717A);     // מטא-מידע, תאריכים
Color textMuted = Color(0xFFA1A1AA);        // טקסט מעומעם, placeholders
```

### צבעי גבולות (Borders)
```dart
Color borderPrimary = Color(0x14000000);    // 0.5px borders ראשיים (rgba(0,0,0,0.08))
Color borderSubtle = Color(0x0F000000);     // dividers דקים יותר (rgba(0,0,0,0.06))
Color borderSofter = Color(0x0A000000);     // dividers הכי עדינים (rgba(0,0,0,0.04))
```

### צבעי הלב הזהב (Gold Heart) - קריטי!
```dart
Color goldHeart = Color(0xFFA87F2A);        // הזהב הראשי - איקון הלב
Color goldHeartLight = Color(0x14A87F2A);   // רקעים זהב חיוורים (8% opacity)
Color goldHeartBorder = Color(0x40A87F2A);  // borders זהב (25% opacity)
Color goldHeartBg = Color(0xFFFFFBEB);      // רקע פתקי תודה זהובים
Color goldHeartBgBorder = Color(0xFFFEF3C7); // border רקעי זהב
Color goldHeartText = Color(0xFF92400E);    // טקסט על רקע זהב
```

### צבעי סטטוס
```dart
// הצלחה - ירוק
Color success = Color(0xFF16A34A);          // אינדיקטורים ירוקים
Color successBg = Color(0xFFDCFCE7);        // רקע ירוק עדין
Color successText = Color(0xFF166534);      // טקסט על רקע ירוק

// אזהרה - צהוב/כתום
Color warning = Color(0xFFF59E0B);          // אינדיקטור ממתין
Color warningBg = Color(0xFFFEF3C7);        // רקע צהוב
Color warningText = Color(0xFFB45309);      // טקסט על רקע צהוב

// סכנה/דחיפות - אדום
Color danger = Color(0xFFB91C1C);           // דחיפות
Color dangerBg = Color(0xFFFEF2F2);         // רקע אדום עדין

// מידע - כחול
Color info = Color(0xFF0EA5E9);             // אינדיקטורים כחולים
Color infoBg = Color(0xFFF0F9FF);           // רקע כחול עדין
Color infoText = Color(0xFF075985);         // טקסט על רקע כחול
Color infoTextDeep = Color(0xFF0C4A6E);     // טקסט כחול כהה
```

### צבעי דירוג
```dart
Color starGold = Color(0xFFFBBF24);         // כוכבי דירוג
```

---

## ✍️ טיפוגרפיה (Typography)

### פונט
```dart
fontFamily: '-apple-system, "SF Pro Display", "Inter", "Heebo", sans-serif'
```

**iOS:** SF Pro Display
**Android:** Inter (לטקסטים לועזיים) + Heebo (לעברית)

### משקלי פונט
```dart
FontWeight.w400  // Regular - טקסט רגיל
FontWeight.w500  // Medium - טקסט עם דגש קל
FontWeight.w600  // SemiBold - כותרות וכפתורים

// אסור: 700+ (כבד מדי), 300- (דק מדי)
```

### היררכיית גדלים
```dart
// כותרות
fontSize: 32, fontWeight: w600, letterSpacing: -0.8  // Hero stat (147 התנדבויות)
fontSize: 24, fontWeight: w600, letterSpacing: -0.6  // כותרת רקע שחור
fontSize: 22, fontWeight: w600, letterSpacing: -0.5  // כותרת מסך
fontSize: 16, fontWeight: w600, letterSpacing: -0.3  // שם משתמש

// טקסט תוכן
fontSize: 15, fontWeight: w600, letterSpacing: -0.2  // כותרת בכרטיס (h3)
fontSize: 14, fontWeight: w600, letterSpacing: -0.1  // כפתור / חשוב
fontSize: 14, fontWeight: w400, letterSpacing: -0.1  // טקסט גוף עיקרי
fontSize: 13, fontWeight: w400, letterSpacing: -0.1  // טקסט גוף משני
fontSize: 13, fontWeight: w500, letterSpacing: -0.1  // טקסט מודגש קל
fontSize: 12, fontWeight: w500, letterSpacing: -0.1  // לייבל / מטא
fontSize: 11, fontWeight: w500, letterSpacing: 0.2   // קפסטיון עם uppercase
fontSize: 10, fontWeight: w400, letterSpacing: 0     // timestamp / footer

// משקל מינימלי לקריאות (a11y)
fontSize: 11px - מינימום מוחלט!
```

### Letter-Spacing (קריטי לתחושה פרימיום!)
- כותרות גדולות (24px+): **-0.4 to -0.8px**
- כותרות בינוניות (15-22px): **-0.2 to -0.3px**
- טקסט רגיל (12-14px): **-0.1px**
- טקסט קטן עם uppercase: **+0.2 to +0.3px**

---

## 📏 ריווחים (Spacing)

### עקרון
מערכת ריווח מבוססת **4px**:
```
4, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32
```

### ריווחים סטנדרטיים
```dart
// מסכים
EdgeInsets.symmetric(horizontal: 20)         // padding מסך מלא
EdgeInsets.fromLTRB(20, 28, 20, 16)          // header של מסך

// כרטיסים
EdgeInsets.all(14)                           // padding בכרטיס קטן
EdgeInsets.all(16)                           // padding בכרטיס בינוני
EdgeInsets.symmetric(h: 16, v: 14)           // כרטיס אופקי

// כפתורים
EdgeInsets.symmetric(v: 14, h: 0)            // כפתור ראשי (full width)
EdgeInsets.symmetric(v: 12, h: 18)           // כפתור משני
EdgeInsets.symmetric(v: 6, h: 12)            // pill/chip

// בין סקציות
SizedBox(height: 24-32)                      // בין סקציות גדולות
SizedBox(height: 16)                         // בין כרטיסים
SizedBox(height: 8-10)                       // בתוך סקציה
```

---

## 🔵 Border Radius

```dart
BorderRadius.circular(8)    // badges קטנים (קפסולה דחופה)
BorderRadius.circular(10)   // alerts קטנים, סטטוסים
BorderRadius.circular(12)   // שדות טופס, alerts בינוניים
BorderRadius.circular(14)   // כרטיסים בינוניים
BorderRadius.circular(18)   // כרטיסים גדולים, התראות
BorderRadius.circular(22)   // panels
BorderRadius.circular(24)   // מסכים מלאים, top sheets
BorderRadius.circular(100)  // כפתורים, pills (pill-shaped) - תמיד!
BorderRadius.circular(999)  // אווטארים, אייקונים עגולים
```

---

## 🔘 קומפוננטות

### Primary Button (כפתור ראשי)
```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Color(0xFF18181B),
    foregroundColor: Colors.white,
    minimumSize: Size(double.infinity, 0),
    padding: EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(100),
    ),
    elevation: 0,
    textStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
  ),
  onPressed: onPressed,
  child: Text('המשך'),
)
```

### Secondary Button (כפתור משני)
```dart
OutlinedButton(
  style: OutlinedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Color(0xFF18181B),
    side: BorderSide(color: Color(0x1F000000), width: 0.5),
    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(100),
    ),
  ),
  onPressed: onPressed,
  child: Text('ביטול'),
)
```

### Pill / Chip
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: isSelected ? Color(0xFF18181B) : Colors.transparent,
    border: isSelected
        ? null
        : Border.all(color: Color(0x1F000000), width: 0.5),
    borderRadius: BorderRadius.circular(100),
  ),
  child: Text(
    label,
    style: TextStyle(
      fontSize: 12,
      color: isSelected ? Colors.white : Color(0xFF52525B),
      fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
      letterSpacing: -0.1,
    ),
  ),
)
```

### Avatar עם לב זהב (קריטי!)
```dart
class AvatarWithGoldHeart extends StatelessWidget {
  final String userId;
  final double size;
  final Timestamp? goldHeartExpiresAt;

  bool get hasActiveGoldHeart {
    if (goldHeartExpiresAt == null) return false;
    return goldHeartExpiresAt!.toDate().isAfter(DateTime.now());
  }

  Widget build(BuildContext context) {
    return Stack(
      children: [
        // האווטאר עצמו
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF4F46E5),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: size * 0.32,
              ),
            ),
          ),
        ),

        // הלב הזהב (רק אם פעיל!)
        if (hasActiveGoldHeart)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40A87F2A),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.favorite,
                size: size * 0.22,
                color: Color(0xFFA87F2A),
              ),
            ),
          ),
      ],
    );
  }
}
```

### Card (כרטיס סטנדרטי)
```dart
Container(
  padding: EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: Color(0x14000000), width: 0.5),
  ),
  child: child,
)
```

### Card Soft (רקע אפור עדין)
```dart
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Color(0xFFFAFAF9),
    borderRadius: BorderRadius.circular(14),
  ),
  child: child,
)
```

### Badge (סטטוס/תווית)
```dart
// דחוף
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: Color(0xFFFEF2F2),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.access_time, size: 9, color: Color(0xFFB91C1C)),
      SizedBox(width: 5),
      Text(
        'תוך 47 דקות',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFFB91C1C),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
)
```

---

## 🎨 עקרונות יסוד

### ❌ אסור!
1. **גרדיאנטים צבעוניים** (אדום-ורוד-סגול) - הוסר ב-100%
2. **אימוג'י כקישוט** (👴🎖️👨‍👩‍👧🤝) - השתמש ב-SVG icons בלבד
3. **Shadows כבדים** - מקסימום `0 4px 12px rgba(0,0,0,0.08)`
4. **Borders עבים** - תמיד `0.5px`, מעולם לא `1px+`
5. **אנימציות פועמות** (pulse, scale infinite) - יוצר חרדה
6. **טקסטים מתחת ל-11px** - בעיית a11y
7. **צבעי טקסט מתחת ל-#A1A1AA** - לא קריא

### ✅ חובה!
1. **רווח לבן** - הרבה
2. **כפתור פעולה אחד דומיננטי** במסך
3. **גבולות 0.5px** ותמיד
4. **Letter-spacing שלילי** בכותרות
5. **משקל פונט 600 מקסימום** - בלי 700+
6. **אייקונים SVG stroke 1.5-1.8** - לא fill, לא stroke עבה

---

## 🌗 רקע שחור (Dark Cards)

לרגעים מיוחדים בלבד (חגיגות, סיכומים):
```dart
// רקע
color: Color(0xFF18181B)
gradient: LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF18181B), Color(0xFF1F1F23)],
)

// טקסטים
white: Color(0xFFFFFFFF)
white70: Color(0xB3FFFFFF)
white60: Color(0x99FFFFFF)
white50: Color(0x80FFFFFF)
white40: Color(0x66FFFFFF)
white35: Color(0x59FFFFFF)

// dividers על שחור
Color(0x14FFFFFF)  // 0.5px border על רקע שחור
```

---

## 📐 Z-Index / Stacking

```
1: רקע
2-3: תוכן רגיל
5: כפתורי map / floating elements
6: כרטיסים תחתונים על מפה
10: header
20: dropdowns / popovers
30: modals
40: toasts
50: critical alerts
```
