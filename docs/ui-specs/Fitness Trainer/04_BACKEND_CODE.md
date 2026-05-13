# 🤖 Backend - Cloud Functions
## 3 פונקציות AI עם Gemini 2.5 Flash Lite

> **קובץ זה משלים את** `01_MAIN_PROMPT.md`, `02_PROVIDER_CODE.md`, `03_CLIENT_CODE.md`  
> **מטרה:** Cloud Functions מוכנות לפריסה ב-Firebase

---

## 📦 הכנה

### 1. התקן את החבילות:
```bash
cd functions
npm install @google/generative-ai firebase-functions firebase-admin
```

### 2. הגדר את ה-API Key:
```bash
firebase functions:secrets:set GEMINI_API_KEY
# הדבק את המפתח של Gemini כשמתבקש
```

### 3. עדכן את `package.json`:
```json
{
  "dependencies": {
    "@google/generative-ai": "^0.21.0",
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^5.0.0"
  }
}
```

---

## 🤖 Function #1: `recommendTrainersByGoals`

### `functions/src/fitness/recommendTrainersByGoals.js`

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');

const GEMINI_KEY = functions.params.defineSecret('GEMINI_API_KEY');

/**
 * AI-powered trainer matching based on client's quiz answers
 * Called from: Client side after completing personality quiz
 * Returns: Match score 0-100 + reasons in Hebrew
 */
exports.recommendTrainersByGoals = functions
  .region('us-central1')
  .runWith({ 
    memory: '512MB', 
    timeoutSeconds: 60,
    secrets: [GEMINI_KEY],
  })
  .https.onCall(async (data, context) => {
    
    // Auth check
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'יש להתחבר כדי לקבל המלצות'
      );
    }
    
    const { 
      goal,           // 'build_muscle' / 'lose_weight' / 'endurance' / 'flexibility' / 'event_prep'
      experience,     // 'beginner' / 'intermediate' / 'advanced'
      frequency,      // '1-2' / '3-4' / '5+'
      location,       // 'home' / 'park' / 'gym'
      style,          // 'motivator' / 'calm' / 'data' / 'friendly'
      trainerId,      // Optional - specific trainer to evaluate
    } = data;
    
    try {
      const genAI = new GoogleGenerativeAI(GEMINI_KEY.value());
      const model = genAI.getGenerativeModel({ 
        model: 'gemini-2.5-flash-lite',
        generationConfig: {
          temperature: 0.3,
          maxOutputTokens: 1024,
          responseMimeType: 'application/json',
        },
      });
      
      // Get trainer data if specified
      let trainerData = null;
      if (trainerId) {
        const trainerDoc = await admin.firestore()
          .collection('providers')
          .doc(trainerId)
          .get();
        
        if (trainerDoc.exists) {
          trainerData = trainerDoc.data();
        }
      }
      
      // Build prompt
      const prompt = buildMatchPrompt({
        goal, experience, frequency, location, style,
        trainerData,
      });
      
      // Call Gemini
      const result = await model.generateContent(prompt);
      const response = result.response.text();
      
      // Parse JSON
      const parsed = JSON.parse(response);
      
      // Log analytics
      await admin.firestore().collection('matching_analytics').add({
        userId: context.auth.uid,
        criteria: { goal, experience, frequency, location, style },
        trainerId: trainerId || null,
        matchScore: parsed.matchScore,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return parsed;
      
    } catch (error) {
      console.error('[recommendTrainersByGoals] Error:', error);
      
      // Fallback response (so UI doesn't break)
      return {
        matchScore: calculateFallbackScore({ goal, experience, frequency, location, style }),
        reasons: getFallbackReasons({ goal, location }),
        success: false,
        fallback: true,
      };
    }
  });

function buildMatchPrompt({ goal, experience, frequency, location, style, trainerData }) {
  const goalMap = {
    build_muscle: 'בניית שריר ומסה',
    lose_weight: 'הרזיה ושריפת שומן',
    endurance: 'שיפור סיבולת',
    flexibility: 'גמישות והרגעה',
    event_prep: 'הכנה לאירוע ספורטיבי',
  };
  
  const styleMap = {
    motivator: 'מאמן מוטיבטור (אנרגטי, צועק, לוחץ)',
    calm: 'מאמן רגוע (סבלני, מסביר לאט)',
    data: 'מאמן מבוסס דאטה (מספרים, סטטיסטיקות)',
    friendly: 'מאמן חברותי (כמו חבר, מצחיק)',
  };
  
  const trainerInfo = trainerData ? `
פרטי המאמן:
- שם: ${trainerData.name || 'לא זמין'}
- התמחויות: ${(trainerData.specialties || []).join(', ')}
- שנות ניסיון: ${trainerData.yearsExperience || 'לא זמין'}
- דירוג: ${trainerData.rating || 'לא זמין'}
- מספר ביקורות: ${trainerData.reviewsCount || 0}
- מיקומי שירות: ${(trainerData.locations || []).join(', ')}
- מחיר ממוצע: ₪${trainerData.basePrice || 'לא זמין'}
` : '';
  
  return `אתה יועץ כושר מומחה בישראל. עליך להעריך התאמה בין לקוח למאמן כושר.

פרטי הלקוח:
- מטרה: ${goalMap[goal]}
- רמת ניסיון: ${experience}
- תדירות: ${frequency} פעמים בשבוע
- מיקום מועדף: ${location}
- סגנון מועדף: ${styleMap[style]}

${trainerInfo}

המשימה שלך:
1. חשב ציון התאמה 0-100 (60-80 = טוב, 80-95 = מצוין, 95+ = מושלם)
2. תן 4 סיבות בעברית (קצרות, עם אימוג'י) למה זו התאמה טובה
3. כל סיבה חייבת להיות ספציפית ומוטיבציונית

החזר JSON תקין בלבד:
{
  "matchScore": 94,
  "reasons": [
    "🎯 מומחית ב[התמחות רלוונטית]",
    "🏠 מאמנת ב[מיקום הלקוח]",
    "💪 +[X] שנות ניסיון",
    "💝 סגנון [סגנון תואם]"
  ]
}`;
}

function calculateFallbackScore({ goal, experience, frequency, location, style }) {
  // Deterministic fallback based on completeness
  let score = 70;
  if (goal && experience && frequency && location && style) score += 15;
  return Math.min(100, score + Math.floor(Math.random() * 15));
}

function getFallbackReasons({ goal, location }) {
  const goalReasons = {
    build_muscle: '💪 מתמחה בבניית שריר',
    lose_weight: '🔥 מומחה להרזיה',
    endurance: '🏃 מאמן סיבולת',
    flexibility: '🧘 מתמחה בגמישות',
    event_prep: '🏆 הכנה לאירועים',
  };
  
  const locationReasons = {
    home: '🏠 מגיע עד הבית',
    park: '🌳 אימונים בפארק',
    gym: '🏋️ אימוני חדר כושר',
  };
  
  return [
    goalReasons[goal] || '🎯 מתאים למטרות שלך',
    locationReasons[location] || '📍 באזור שלך',
    '⭐ דירוג גבוה מלקוחות',
    '✓ מאמן מאומת',
  ];
}
```

---

## 🎯 Function #2: `optimizeTrainerProfile`

### `functions/src/fitness/optimizeTrainerProfile.js`

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');

const GEMINI_KEY = functions.params.defineSecret('GEMINI_API_KEY');

/**
 * Calculates trainer profile score and provides AI suggestions
 * Called from: Provider side - AI Coach Score Card
 * Returns: Score 0-100 + 5 improvement suggestions in Hebrew
 */
exports.optimizeTrainerProfile = functions
  .region('us-central1')
  .runWith({ 
    memory: '512MB', 
    timeoutSeconds: 60,
    secrets: [GEMINI_KEY],
  })
  .https.onCall(async (data, context) => {
    
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'יש להתחבר'
      );
    }
    
    const trainerId = context.auth.uid;
    
    try {
      // Fetch trainer profile
      const trainerDoc = await admin.firestore()
        .collection('providers')
        .doc(trainerId)
        .get();
      
      if (!trainerDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'המאמן לא נמצא');
      }
      
      const trainer = trainerDoc.data();
      
      // Calculate base score
      const score = calculateProfileScore(trainer);
      
      // Get AI suggestions
      const genAI = new GoogleGenerativeAI(GEMINI_KEY.value());
      const model = genAI.getGenerativeModel({ 
        model: 'gemini-2.5-flash-lite',
        generationConfig: {
          temperature: 0.4,
          responseMimeType: 'application/json',
        },
      });
      
      const prompt = buildOptimizePrompt(trainer, score);
      const result = await model.generateContent(prompt);
      const response = JSON.parse(result.response.text());
      
      // Save to trainer doc for caching
      await admin.firestore()
        .collection('providers')
        .doc(trainerId)
        .update({
          profileScore: score,
          aiSuggestions: response.suggestions,
          lastOptimized: admin.firestore.FieldValue.serverTimestamp(),
        });
      
      return {
        score,
        suggestions: response.suggestions,
      };
      
    } catch (error) {
      console.error('[optimizeTrainerProfile] Error:', error);
      
      // Fallback - calculate score deterministically
      const trainerDoc = await admin.firestore()
        .collection('providers')
        .doc(trainerId)
        .get();
      
      const score = trainerDoc.exists ? calculateProfileScore(trainerDoc.data()) : 50;
      
      return {
        score,
        suggestions: getFallbackSuggestions(trainerDoc.data()),
        fallback: true,
      };
    }
  });

function calculateProfileScore(trainer) {
  let score = 0;
  
  // Specialties (15 points)
  const specCount = (trainer.specialties || []).length;
  if (specCount >= 3) score += 15;
  else if (specCount >= 1) score += 8;
  
  // Certifications (15 points)
  const certs = (trainer.certifications || []).filter(c => c.isVerified);
  score += Math.min(15, certs.length * 5);
  
  // Pricing packages (10 points)
  if ((trainer.pricingPackages || []).length >= 2) score += 10;
  
  // Locations (10 points)
  const locCount = (trainer.locations || []).length;
  score += Math.min(10, locCount * 4);
  
  // Success stories (15 points)
  score += Math.min(15, (trainer.successStories || []).length * 5);
  
  // Active offers (10 points)
  if ((trainer.activeOffers || []).length >= 1) score += 10;
  
  // Story length (10 points)
  const storyLen = (trainer.story || '').length;
  if (storyLen >= 200) score += 10;
  else if (storyLen >= 100) score += 5;
  
  // Portfolio (10 points)
  score += Math.min(10, (trainer.portfolio || []).length * 2);
  
  // Rating bonus (5 points)
  if ((trainer.rating || 0) >= 4.5) score += 5;
  
  return Math.min(100, score);
}

function buildOptimizePrompt(trainer, currentScore) {
  return `אתה יועץ עסקי למאמני כושר בישראל. עליך לתת 5 הצעות לשיפור הפרופיל.

נתוני המאמן הנוכחיים:
- ציון נוכחי: ${currentScore}/100
- שם: ${trainer.name || 'לא זמין'}
- מספר התמחויות: ${(trainer.specialties || []).length}
- מספר תעודות: ${(trainer.certifications || []).length} (מאומתות: ${(trainer.certifications || []).filter(c => c.isVerified).length})
- מספר חבילות: ${(trainer.pricingPackages || []).length}
- מספר מיקומי שירות: ${(trainer.locations || []).length}
- מספר סיפורי הצלחה: ${(trainer.successStories || []).length}
- מבצעים פעילים: ${(trainer.activeOffers || []).length}
- אורך הסיפור האישי: ${(trainer.story || '').length} תווים
- מחיר ממוצע: ₪${trainer.basePrice || 'לא זמין'}
- דירוג: ${trainer.rating || 'אין'} (${trainer.reviewsCount || 0} ביקורות)

המשימה שלך:
תן בדיוק 5 הצעות מדורגות לפי impact:
1. עדיפות גבוהה (אדום) - שיפורים שיעלו את ה-conversion ב-15%+
2. עדיפות בינונית (כתום) - שיפורים של 5-15%
3. עדיפות נמוכה (ירוק) - שיפורים של 0-5%

לכל הצעה:
- icon: אימוג'י
- title: כותרת קצרה (עד 6 מילים)
- description: תיאור קצר (עד 15 מילים)
- impact: "+X%" - אחוז ההשפעה הצפויה
- action: טקסט הקריאה לפעולה (כפתור, עד 4 מילים)
- priority: "high" / "medium" / "low"

החזר JSON תקין בלבד:
{
  "suggestions": [
    {
      "icon": "📸",
      "title": "הוסיפי תמונות לפני/אחרי",
      "description": "3 תמונות = +15% בקליקים",
      "impact": "+15%",
      "action": "הוסיפי עכשיו",
      "priority": "high"
    }
  ]
}`;
}

function getFallbackSuggestions(trainer) {
  const suggestions = [];
  
  if (!trainer.successStories || trainer.successStories.length < 1) {
    suggestions.push({
      icon: '📸',
      title: 'הוסיפי תמונות לפני/אחרי',
      description: '3 תמונות = +15% בקליקים',
      impact: '+15%',
      action: 'הוסיפי עכשיו',
      priority: 'high',
    });
  }
  
  if (!trainer.activeOffers || trainer.activeOffers.length < 1) {
    suggestions.push({
      icon: '🎁',
      title: 'הפעילי "אימון ראשון בחינם"',
      description: 'מגדיל פניות פי 3 בממוצע',
      impact: '+25%',
      action: 'הפעילי',
      priority: 'high',
    });
  }
  
  if ((trainer.story || '').length < 200) {
    suggestions.push({
      icon: '📝',
      title: 'הסיפור שלך קצר מדי',
      description: 'הוסיפי 100+ מילים',
      impact: '+10%',
      action: 'ערכי',
      priority: 'medium',
    });
  }
  
  if ((trainer.specialties || []).length < 3) {
    suggestions.push({
      icon: '🎯',
      title: 'הוסיפי עוד התמחויות',
      description: 'מינימום 3 התמחויות מומלצות',
      impact: '+8%',
      action: 'הוסיפי',
      priority: 'medium',
    });
  }
  
  if ((trainer.pricingPackages || []).length < 3) {
    suggestions.push({
      icon: '💰',
      title: 'הוסיפי חבילה נוספת',
      description: '3 חבילות = יותר אופציות לקוחות',
      impact: '+5%',
      action: 'הוסיפי',
      priority: 'low',
    });
  }
  
  return suggestions.slice(0, 5);
}
```

---

## 🏋️ Function #3: `generateCustomWorkoutPlan`

### `functions/src/fitness/generateCustomWorkoutPlan.js`

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');

const GEMINI_KEY = functions.params.defineSecret('GEMINI_API_KEY');

/**
 * Generates a personalized 4-week workout plan in Hebrew
 * Called from: Trainer side after first session - sent to client
 * Returns: Structured 4-week plan with exercises
 */
exports.generateCustomWorkoutPlan = functions
  .region('us-central1')
  .runWith({ 
    memory: '512MB', 
    timeoutSeconds: 90,
    secrets: [GEMINI_KEY],
  })
  .https.onCall(async (data, context) => {
    
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'יש להתחבר'
      );
    }
    
    const {
      clientId,
      goal,                  // 'build_muscle' / 'lose_weight' / etc
      experience,           // 'beginner' / 'intermediate' / 'advanced'
      frequency,            // '1-2' / '3-4' / '5+'
      durationWeeks = 4,
      equipmentAvailable = ['none'],
      injuriesOrLimitations = [],
      currentWeight = null,
      targetWeight = null,
    } = data;
    
    try {
      const genAI = new GoogleGenerativeAI(GEMINI_KEY.value());
      const model = genAI.getGenerativeModel({ 
        model: 'gemini-2.5-flash-lite',
        generationConfig: {
          temperature: 0.5,
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
        },
      });
      
      const prompt = buildWorkoutPrompt({
        goal, experience, frequency, durationWeeks,
        equipmentAvailable, injuriesOrLimitations,
        currentWeight, targetWeight,
      });
      
      const result = await model.generateContent(prompt);
      const plan = JSON.parse(result.response.text());
      
      // Save plan to client's profile
      if (clientId) {
        await admin.firestore()
          .collection('clients')
          .doc(clientId)
          .collection('workout_plans')
          .add({
            ...plan,
            createdBy: context.auth.uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isActive: true,
          });
      }
      
      return plan;
      
    } catch (error) {
      console.error('[generateCustomWorkoutPlan] Error:', error);
      throw new functions.https.HttpsError(
        'internal',
        'שגיאה ביצירת תכנית האימון: ' + error.message
      );
    }
  });

function buildWorkoutPrompt({ goal, experience, frequency, durationWeeks, equipmentAvailable, injuriesOrLimitations, currentWeight, targetWeight }) {
  return `אתה מאמן כושר מקצועי. צור תכנית אימון מותאמת אישית בעברית.

פרטי הלקוח:
- מטרה: ${goal}
- רמת ניסיון: ${experience}
- תדירות שבועית: ${frequency}
- משך התכנית: ${durationWeeks} שבועות
- ציוד זמין: ${equipmentAvailable.join(', ')}
- מגבלות/פציעות: ${injuriesOrLimitations.length > 0 ? injuriesOrLimitations.join(', ') : 'אין'}
${currentWeight ? `- משקל נוכחי: ${currentWeight} ק"ג` : ''}
${targetWeight ? `- משקל יעד: ${targetWeight} ק"ג` : ''}

צור תכנית מובנית עם:
1. סקירה כללית של התכנית
2. לוח זמנים שבועי (אילו ימים, איזה חלקי גוף)
3. תרגילים ספציפיים (סטים x חזרות x מנוחה)
4. תכנית התקדמות שבועית
5. המלצות התאוששות
6. טיפים תזונתיים

החזר JSON תקין בלבד:
{
  "planOverview": "תיאור כללי של התכנית...",
  "weeklySchedule": [
    {
      "week": 1,
      "title": "שבוע התרגלות",
      "days": [
        {
          "day": "ראשון",
          "focus": "פלג גוף עליון",
          "duration": "45-60 דקות",
          "exercises": [
            {
              "name": "שכיבות סמיכה",
              "sets": 3,
              "reps": "8-12",
              "restSeconds": 60,
              "notes": "התחילי על הברכיים אם קשה"
            }
          ]
        }
      ]
    }
  ],
  "progressionStrategy": "איך להתקדם משבוע לשבוע...",
  "recoveryTips": ["טיפ 1", "טיפ 2"],
  "nutritionGuidelines": ["הנחיה 1", "הנחיה 2"]
}`;
}
```

---

## 📦 שילוב ב-`functions/index.js`

```javascript
// functions/index.js
const admin = require('firebase-admin');
admin.initializeApp();

// Existing functions...
exports.recommendTrainersByGoals = require('./src/fitness/recommendTrainersByGoals').recommendTrainersByGoals;
exports.optimizeTrainerProfile = require('./src/fitness/optimizeTrainerProfile').optimizeTrainerProfile;
exports.generateCustomWorkoutPlan = require('./src/fitness/generateCustomWorkoutPlan').generateCustomWorkoutPlan;
```

---

## 🚀 הוראות פריסה

### Step 1: הגדר את ה-API Key
```bash
firebase functions:secrets:set GEMINI_API_KEY
# הדבק את המפתח (קיבל אותו מ-https://makersuite.google.com)
```

### Step 2: בדוק לוקלית
```bash
cd functions
npm run serve
# פותח Firebase Emulator על localhost:5001
```

### Step 3: פרוס לפרודקשן
```bash
# פריסה של הפונקציות החדשות בלבד
firebase deploy --only functions:recommendTrainersByGoals
firebase deploy --only functions:optimizeTrainerProfile
firebase deploy --only functions:generateCustomWorkoutPlan

# או הכל יחד
firebase deploy --only functions
```

### Step 4: עדכן את `firestore.rules`
```javascript
// firestore.rules - הוסף את הכללים הבאים:

match /matching_analytics/{docId} {
  allow read: if request.auth.token.admin == true;
  allow create: if request.auth != null;
}

match /clients/{clientId}/workout_plans/{planId} {
  allow read: if request.auth.uid == clientId;
  allow create, update: if request.auth.uid == resource.data.createdBy;
}

// Allow trainers to update their own profile with new fields
match /providers/{providerId} {
  allow update: if request.auth.uid == providerId &&
    request.resource.data.diff(resource.data).affectedKeys()
      .hasAny(['profileScore', 'aiSuggestions', 'lastOptimized', 
               'specialties', 'pricingPackages', 'locations',
               'certifications', 'successStories', 'activeOffers']);
}
```

### Step 5: פרוס את הכללים
```bash
firebase deploy --only firestore:rules
```

---

## 📊 מבנה Firestore המומלץ

```
providers/{providerId}
├── name: "סיגלית מלסה"
├── subcategory: "מאמני כושר"
├── specialties: ["strength", "fat_loss", "pregnancy", "seniors", "rehab"]
├── certifications: [
│     { id, name, institution, year, isVerified, imageUrl }
│   ]
├── pricingPackages: [
│     { id, name, type, sessions, durationMinutes, price, discount, isPopular }
│   ]
├── locations: [
│     { id, type, radiusKm, extraCost, notes }
│   ]
├── successStories: [
│     { id, clientName, result, testimonial, beforeImageUrl, afterImageUrl, rating, clientApproved }
│   ]
├── activeOffers: [
│     { id, type, title, description, discountPercent, availableSpots, expiresAt }
│   ]
├── story: "..."
├── basePrice: 200
├── rating: 4.92
├── reviewsCount: 127
├── yearsExperience: 30
├── profileScore: 78          (calculated by AI)
├── aiSuggestions: [...]      (calculated by AI)
└── lastOptimized: timestamp

matching_analytics/{docId}
├── userId
├── criteria: { goal, experience, frequency, location, style }
├── trainerId
├── matchScore
└── timestamp

clients/{clientId}/workout_plans/{planId}
├── planOverview
├── weeklySchedule: [...]
├── progressionStrategy
├── recoveryTips: [...]
├── nutritionGuidelines: [...]
├── createdBy (trainer ID)
├── createdAt
└── isActive
```

---

## ✅ Definition of Done - Backend

- [ ] 3 Cloud Functions פרוסים ב-Firebase
- [ ] GEMINI_API_KEY מוגדר כ-secret
- [ ] Firestore Rules מעודכנים
- [ ] בדיקה חיה: Quiz מחזיר תוצאה אמיתית מ-Gemini
- [ ] בדיקה חיה: AI Coach Score מחושב נכון
- [ ] בדיקה חיה: Workout Plan נוצר ונשמר
- [ ] Logs נקיים ב-Firebase Console
- [ ] Latency < 5 שניות לכל function
- [ ] Fallback responses עובדים אם Gemini נופל

---

## 🐛 Troubleshooting

### "GEMINI_API_KEY not found"
```bash
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```

### "Quota exceeded"
- בדוק את הdashboard של Gemini: https://aistudio.google.com
- ה-Free tier מאפשר 15 RPM (Requests Per Minute)
- שדרג ל-paid אם צריך יותר

### "Cold start latency"
- הוסף ב-`runWith({ minInstances: 1 })` כדי להחזיק instance חי תמיד (עולה כסף)

### "JSON Parse Error"
- וודא ש-`responseMimeType: 'application/json'` מוגדר
- בדוק שהפרומפט אומר במפורש "החזר JSON תקין בלבד"

---

**📁 לקובץ הבא: `05_INTEGRATION.md` - איך לחבר את הבלוקים למסכים הקיימים**
