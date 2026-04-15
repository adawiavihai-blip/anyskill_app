# AnySkill — Provider Registration Flow Implementation

## 🎯 Overview

Implement a complete **Service Provider Registration** flow in the AnySkill app. This includes modifying the existing customer profile screen, building a multi-step registration wizard, and syncing submitted data with the admin dashboard.

---

## 📋 Task Breakdown

### PHASE 1: Modify Customer Profile Screen

**Location:** The existing customer profile page (where users see their profile info, favorites, received services, etc.)

**Changes Required:**

1. **REMOVE** the existing "רוצה להרוויח כסף? לחץ כאן" button (the purple gradient banner with the $ icon). Delete it completely from the UI and any related code/navigation logic.

2. **ADD** a new professional button in its place:
   - **Text:** `להצטרפות ל-AnySkill כנותן שירות`
   - **Style:** Clean, professional design that matches the app's design system. NOT a flashy/gimmicky banner — a proper CTA button with the app's primary color (purple/accent).
   - **Behavior:** `onPress` → Navigate to the new Provider Registration screen.

---

### PHASE 2: Build the Provider Registration Screen

Build a **4-step wizard** registration screen. The full HTML/CSS reference for the exact design is attached separately (file: `anyskill_provider_registration_v3.html`). Implement this as a native screen matching the design exactly.

#### Step 1 — Personal Details (פרטים אישיים)

Fields (all required):
- **שם מלא** (Full Name) — text input, placeholder: "השם שיוצג ללקוחות"
- **מספר טלפון** (Phone) — tel input, placeholder: "05X-XXXXXXX", LTR direction
- **כתובת אימייל** (Email) — email input, placeholder: "your@email.com", LTR direction

#### Step 2 — Field of Work (תחום עיסוק)

Fields (all required):
- **קטגוריה ראשית** — Dropdown select (NOT icon grid). Must be **synced with the existing categories in the app database**. Pull the category list dynamically from the same source that feeds the customer-facing category browsing.

- **תת-קטגוריה (התמחות)** — After selecting a category, show the subcategories as tappable **chips/tags**. These must also be **synced with the existing subcategories in the app**. The user selects one.

- **תיאור העיסוק** — Textarea, appears only AFTER the user selects a subcategory. Placeholder: "ספרו על הניסיון שלכם, סוגי השירות, זמינות, ומה מייחד אתכם... (מינימום 20 תווים)". Minimum 20 characters validation.

**IMPORTANT — Category Sync:**
The categories and subcategories in this registration form MUST pull from the same data source as the rest of the app. If the app has a categories collection/table in the database, use that. Do NOT hardcode a separate list. If new categories are added to the app, they should automatically appear in this registration form too.

#### Step 3 — Location & Identity Verification (מיקום ואימות זהות)

Fields (all required):
- **מדינה** (Country) — Dropdown select. Default: ישראל. Options: ישראל, ארצות הברית, בריטניה, גרמניה, צרפת, קנדה, אוסטרליה, אחר.
- **עיר** (City) — Dropdown select. Israeli cities list (תל אביב - יפו, ירושלים, חיפה, ראשון לציון, פתח תקווה, אשדוד, נתניה, באר שבע, חולון, בני ברק, רמת גן, אשקלון, הרצליה, כפר סבא, רעננה, מודיעין, אילת, נצרת, עכו, בת ים, אחר).
- **רחוב ומספר** (Street) — Text input, placeholder: "לדוגמא: הרצל 15"
- **אימות זהות** (ID Verification) — Required section:
  - Upload area for ID photo (תעודת זהות / דרכון)
  - Accepted formats: JPG, PNG, PDF
  - After upload: show green success indicator with filename
  - Display privacy tags: מוצפן, פרטי, ממתין לאישור
  - Note: "המסמך מאוחסן בהצפנה ומשמש לאימות בלבד — לא יוצג ללקוחות"
  - Tag the uploaded document with status: `pending_verification`

#### Step 4 — Business & Bank Details (פרטי עסק וחשבון בנק)

Fields (all required):

**Business Type:**
- **סוג העסק** — Dropdown select (NOT icon cards). Options:
  - עוסק פטור
  - עוסק מורשה
  - חברה בע"מ
  - חשבונית למשכיר

- **העלאת אישור עוסק** — Upload area, appears after selecting business type. Required (NOT optional/recommended). Accepted: PDF, JPG, PNG. Show success indicator after upload.

**Bank Account Details:**
- **שם הבנק** — Dropdown select with all Israeli banks:
  - בנק הפועלים (12)
  - בנק דיסקונט (11)
  - בנק לאומי (10)
  - בנק מזרחי טפחות (20)
  - בנק הבינלאומי (31)
  - בנק אוצר החייל (14)
  - בנק איגוד (13)
  - בנק מרכנתיל דיסקונט (17)
  - בנק הדואר (09)
  - בנק מסד (46)
  - בנק ירושלים (54)
  - יובנק (26)
  - בנק יהב (04)
  - בנק ערבי ישראלי (34)
- **מספר בנק** — Auto-filled readonly field based on bank selection (the number in parentheses)
- **מספר סניף** — Numeric input, max 4 digits, placeholder: "185"
- **מספר חשבון** — Numeric input, max 9 digits, placeholder: "123456"
- Privacy note: "פרטי הבנק מוצפנים ומשמשים להעברת תשלומים בלבד"

**Info Card — "AnySkill בקיצור" (provider-focused text):**
- 🔒 **הכסף שלך בטוח:** ברגע שלקוח מבצע הזמנה, התשלום נכנס לנאמנות. בסיום השירות ואישור הלקוח — הכסף מועבר אליך.
- 🤝 **תיווך בלבד:** AnySkill מחברת בינך לבין הלקוח. האחריות המקצועית על ביצוע העבודה היא שלך.
- 📋 **מדיניות ביטולים:** הגדירו מדיניות ביטולים ברורה בפרופיל שלכם — הלקוחות רואים אותה לפני ההזמנה.
- 💰 **העברות מהירות:** לאחר אישור סיום השירות, התשלום מועבר ישירות לחשבון הבנק שלכם.

**Terms of Service & Privacy Policy — MANDATORY FULL READ:**

This is a critical UX requirement. The existing Terms of Service and Privacy Policy content that currently lives behind the old "רוצה להרוויח כסף" flow MUST be preserved and integrated into this new registration flow. Here is exactly how it should work:

1. **Scrollable Document Container:** Below the info card, display a scrollable container (bordered box, max-height ~300px with overflow-y: scroll) containing the FULL text of:
   - **תנאי השימוש** (Terms of Service) — the same content that currently exists in the app
   - **מדיניות הפרטיות** (Privacy Policy) — the same content that currently exists in the app
   - Display them one after the other inside the same scrollable container, with clear section headers separating them.

2. **Scroll-to-Bottom Enforcement:** The checkbox below the container MUST be **disabled and grayed out** until the user has scrolled ALL the way to the bottom of the document. Track scroll position — only when `scrollTop + clientHeight >= scrollHeight - 20` (i.e., user reached the bottom with small tolerance), enable the checkbox.

3. **Visual Indicator:** While the user hasn't scrolled to the bottom yet, show a subtle hint below the container: "גללו למטה כדי לקרוא את כל התנאים ←" with a small downward arrow animation. Once the user reaches the bottom, this hint disappears.

4. **Checkbox:** Once enabled (after full scroll), the checkbox text reads: "אני מאשר/ת שקראתי והסכמתי לתנאי השימוש ולמדיניות הפרטיות של AnySkill (גרסה 2.0)"

5. **Submit Button:** `שלח בקשת הצטרפות ל-AnySkill` — remains DISABLED until the checkbox is checked. The checkbox can only be checked after scrolling to the bottom. So the flow is: scroll to bottom → checkbox becomes clickable → check checkbox → submit button becomes active.

**IMPORTANT:** The COMPLETE and REAL Terms of Service and Privacy Policy text is already included in the HTML reference file (`anyskill_provider_registration_v3.html`) inside the scrollable terms container. This is the EXACT same content currently used in the app (14 sections of Terms of Service + Privacy Policy section). Use this text as-is. It includes all sections: 1. מהי AnySkill, 2. סטטוס ספקים — קבלן עצמאי, 3. מודל תשלום — נאמנות (Escrow), 4. עמלות ודמי שירות, 5. מדיניות ביטולים, 6. ציות מס ואחריות פיסקלית, 7. אחריות משתמשים והתנהגות אסורה, 8. אבטחת חשבון ואחריות אישית, 9. הגבלת אחריות, 10. יישוב מחלוקות ובוררות, 11. קניין רוחני, 12. מדיניות פרטיות, 13. שינויים בתנאים, 14. דין חל ושיפוט. However — if the app already stores this content in the database or a separate file, pull from THAT source to stay in sync. The HTML file is the fallback reference.

---

### PHASE 3: Submission Flow & Data Handling

#### On Submit:

1. **Validate** all required fields across all 4 steps. If any field is missing, navigate back to that step and highlight the missing field.

2. **Save** the provider application to the database with the following structure:

```
provider_applications {
  id: auto-generated
  user_id: (linked to existing customer account)
  status: "pending_review"
  created_at: timestamp
  
  // Step 1
  full_name: string
  phone: string
  email: string
  
  // Step 2
  category_id: reference (from app's categories)
  subcategory_id: reference (from app's subcategories)
  bio_description: string
  
  // Step 3
  country: string
  city: string
  street_address: string
  id_document_url: file URL (uploaded to storage)
  id_verification_status: "pending_verification"
  
  // Step 4
  business_type: enum ["עוסק פטור", "עוסק מורשה", "חברה בע״מ", "חשבונית למשכיר"]
  business_document_url: file URL (uploaded to storage)
  bank_name: string
  bank_number: string
  branch_number: string
  account_number: string
  
  terms_accepted: true
  terms_version: "2.0"
  terms_accepted_at: timestamp
  terms_fully_scrolled: true  // confirms user scrolled to bottom before accepting
}
```

3. **Upload files** (ID document + business document) to secure storage (Firebase Storage / S3 / whatever the app uses). Store the download URLs in the application record.

4. **Show confirmation screen** after successful submission:
   - Display a success message:
     ```
     ✅ קיבלנו את בקשת ההצטרפות שלכם!
     
     צוות AnySkill עובר על הפרטים ויאשר את הפרופיל שלכם בקרוב.
     
     תודה שבחרתם להצטרף ל-AnySkill! 🎉
     ```
   - Include a button to go back to the home screen.
   - Do NOT navigate back to the registration form.

5. **Notify the admin** — Create a notification/entry in the admin dashboard that a new provider application was submitted and is awaiting review.

---

### PHASE 4: Admin Side

In the admin dashboard/panel:

1. **New section:** "בקשות הצטרפות נותני שירות" (Provider Join Requests)
2. **List view** of all pending applications with:
   - Applicant name
   - Category + subcategory
   - City
   - Submission date
   - Status (pending_review / approved / rejected)
3. **Detail view** for each application showing all submitted data including:
   - Ability to view uploaded documents (ID + business doc)
   - Approve / Reject buttons
4. **On Approve:**
   - Change application status to "approved"
   - Create a provider profile for this user
   - The user's role changes from "customer" to "provider" (or gains dual role)
   - Send notification to the user that they've been approved
5. **On Reject:**
   - Change application status to "rejected"
   - Optionally include a rejection reason
   - Send notification to the user

---

## 🎨 Design Guidelines

- **RTL Layout** — Everything is right-to-left (Hebrew)
- **Font:** Heebo for body, Rubik for headings
- **Primary Color:** #6C5CE7 (purple)
- **All form fields** use clean dropdown selects — NO icon grids or card-based selection
- **Progress bar** at top showing steps 1-4
- **Sticky CTA button** at bottom of screen
- **Header** at very top with just "AnySkill" text (no icon/logo next to it)
- **All fields are required** — show red dot indicator next to labels
- **Mobile-first** responsive design
- Refer to the HTML file (`anyskill_provider_registration_v3.html`) for exact styling, spacing, colors, and component structure

---

## ⚠️ Important Notes

1. **Category Sync is Critical** — Categories and subcategories MUST come from the app's existing database, not hardcoded. This ensures consistency between what customers see and what providers can register for.

2. **Remove ALL old "רוצה להרוויח כסף" buttons** — Search the entire codebase for this text and any related navigation/components. Remove them all.

3. **Security** — Uploaded documents (ID, business doc) should be stored in a secure location with restricted access. Only admins should be able to view them.

4. **Bank details** — Must be encrypted at rest in the database.

5. **File validation** — Validate file types (JPG, PNG, PDF only) and file size (max 10MB) before upload.

6. **The confirmation screen** after submission should be a separate screen/state, not an alert dialog. It should look professional with the success message and a "חזרה לדף הבית" button.

7. **Terms of Service Preservation** — The existing Terms of Service and Privacy Policy text from the current "רוצה להרוויח כסף" flow MUST be preserved. Find where this content is stored (database, static file, or hardcoded screen) and reuse the EXACT same content in the new registration flow's scrollable terms container. Do NOT delete or lose this content when removing the old flow. The terms must be scrollable, and the user must scroll to the bottom before they can check the acceptance checkbox.

---

## 📁 Files Reference

- `anyskill_provider_registration_v3.html` — Complete HTML/CSS/JS reference for the registration wizard design. Use this as the source of truth for all styling, layout, spacing, and component behavior.

---

## ✅ Definition of Done

- [ ] Old "רוצה להרוויח כסף" button removed from profile
- [ ] New "להצטרפות ל-AnySkill כנותן שירות" button added to profile
- [ ] 4-step registration wizard fully functional
- [ ] Categories & subcategories synced from app database
- [ ] All fields validated (required + format)
- [ ] Files upload to secure storage
- [ ] Data saved to database on submission
- [ ] Professional confirmation screen shown after submit
- [ ] Admin dashboard shows pending applications
- [ ] Admin can approve/reject applications
- [ ] Approved users get provider role + notification
- [ ] Design matches the HTML reference file exactly
- [ ] Existing Terms of Service & Privacy Policy content preserved from old flow
- [ ] Terms displayed in scrollable container in Step 4
- [ ] Checkbox disabled until user scrolls to bottom of terms
- [ ] Submit button disabled until checkbox is checked
- [ ] All old related code cleaned up
