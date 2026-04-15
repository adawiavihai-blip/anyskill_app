import { useState, useEffect, useRef, useCallback } from "react";

/* ═══════════════════════════════════════════
   CONSTANTS
   ═══════════════════════════════════════════ */

const CATEGORIES = [
  { id: "delivery", icon: "📦", label: "משלוחים", color: "#10B981", priceRange: [30, 120] },
  { id: "cleaning", icon: "🧹", label: "ניקיון", color: "#3B82F6", priceRange: [80, 250] },
  { id: "repairs", icon: "🔧", label: "תיקונים", color: "#F59E0B", priceRange: [100, 400] },
  { id: "moving", icon: "🚚", label: "הובלות", color: "#8B5CF6", priceRange: [200, 800] },
  { id: "pets", icon: "🐾", label: "טיפול בחיות", color: "#EC4899", priceRange: [50, 150] },
  { id: "tech", icon: "💻", label: "טכנולוגיה", color: "#06B6D4", priceRange: [100, 500] },
  { id: "lessons", icon: "📚", label: "שיעורים פרטיים", color: "#F97316", priceRange: [80, 200] },
  { id: "photography", icon: "📸", label: "צילום", color: "#6366F1", priceRange: [150, 600] },
  { id: "design", icon: "🎨", label: "עיצוב", color: "#D946EF", priceRange: [200, 1000] },
  { id: "other", icon: "✨", label: "אחר", color: "#64748B", priceRange: [50, 300] },
];

const URGENCY = [
  { id: "flexible", label: "גמיש", sub: "בלי לחץ", icon: "🕐" },
  { id: "today", label: "היום", sub: "בהקדם האפשרי", icon: "⚡" },
  { id: "urgent", label: "דחוף עכשיו", sub: "תוך שעה", icon: "🔥" },
];

const PROOF_TYPES = [
  { id: "photo", label: "תמונה", icon: "📷" },
  { id: "text", label: "טקסט", icon: "📝" },
  { id: "photo_text", label: "תמונה + טקסט", icon: "📋" },
];

const MOCK_PROVIDERS = [
  { id: 1, name: "יוסי כהן", avatar: "👨‍🔧", rating: 4.9, reviews: 127, price: 95, time: "25 דק'", badge: "⭐ מומלץ", specialty: "משלוחים מהירים", completedTasks: 340 },
  { id: 2, name: "מירב לוי", avatar: "👩‍💼", rating: 4.8, reviews: 89, price: 110, time: "40 דק'", badge: null, specialty: "שירות אמין", completedTasks: 215 },
  { id: 3, name: "דני אברהם", avatar: "👨‍💻", rating: 5.0, reviews: 56, price: 85, time: "15 דק'", badge: "🚀 מהיר", specialty: "זמין תמיד", completedTasks: 178 },
];

const QUICK_REPLIES = [
  { id: "when", text: "מתי אפשר להתחיל?", icon: "🕐" },
  { id: "exp", text: "יש לך ניסיון בתחום?", icon: "💪" },
  { id: "price", text: "אפשר לדבר על המחיר?", icon: "💰" },
  { id: "details", text: "אפשר עוד פרטים?", icon: "📋" },
];

const TASK_STATUSES = [
  { id: "published", label: "פורסמה", icon: "📢", color: "#3B82F6" },
  { id: "accepted", label: "נותן שירות קיבל", icon: "🤝", color: "#8B5CF6" },
  { id: "on_way", label: "בדרך אליך", icon: "🚗", color: "#F59E0B" },
  { id: "in_progress", label: "בביצוע", icon: "⚡", color: "#F97316" },
  { id: "done", label: "בוצע", icon: "✅", color: "#10B981" },
  { id: "rated", label: "דורג", icon: "⭐", color: "#EAB308" },
];

/* ═══════════════════════════════════════════
   MAIN APP
   ═══════════════════════════════════════════ */
export default function AnyTasksApp() {
  const [screen, setScreen] = useState("home");
  const [step, setStep] = useState(1);
  const [animating, setAnimating] = useState(false);
  const [task, setTask] = useState({
    title: "", description: "", category: null, budget: "",
    urgency: "flexible", proof: "photo",
    locationFrom: "", locationTo: "", isRemote: false,
  });

  useEffect(() => {
    const link = document.createElement("link");
    link.href = "https://fonts.googleapis.com/css2?family=Rubik:wght@300;400;500;600;700;800;900&display=swap";
    link.rel = "stylesheet";
    document.head.appendChild(link);
  }, []);

  const goToStep = (s) => {
    setAnimating(true);
    setTimeout(() => { setStep(s); setAnimating(false); }, 200);
  };
  const goBack = () => { if (step > 1) goToStep(step - 1); else setScreen("home"); };

  const appStyle = {
    fontFamily: "'Rubik', sans-serif",
    direction: "rtl",
    maxWidth: 430,
    margin: "0 auto",
    minHeight: "100vh",
    background: "#FAFBFC",
    position: "relative",
  };

  return (
    <div style={appStyle}>
      {screen === "home" && (
        <HomeScreen onNewTask={() => { setScreen("create"); setStep(1); }}
          onTracker={() => setScreen("tracker")}
          onChat={() => setScreen("chat")}
          onOffers={() => setScreen("offers")}
        />
      )}
      {screen === "create" && (
        <CreateTaskFlow step={step} totalSteps={4} task={task} setTask={setTask}
          goToStep={goToStep} goBack={goBack} animating={animating}
          onPublish={() => setScreen("offers")}
        />
      )}
      {screen === "offers" && <RealTimeOffers onBack={() => setScreen("home")} onAccept={() => setScreen("tracker")} />}
      {screen === "tracker" && <LiveTracker onBack={() => setScreen("home")} onChat={() => setScreen("chat")} onRate={() => setScreen("rating")} />}
      {screen === "chat" && <ChatScreen onBack={() => setScreen("tracker")} />}
      {screen === "rating" && <DualRating onBack={() => setScreen("home")} />}
    </div>
  );
}

/* ═══════════════════════════════════════════
   HOME SCREEN
   ═══════════════════════════════════════════ */
function HomeScreen({ onNewTask, onTracker, onChat, onOffers }) {
  const [loaded, setLoaded] = useState(false);
  useEffect(() => { setTimeout(() => setLoaded(true), 100); }, []);

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column" }}>
      {/* Header */}
      <div style={{
        background: "linear-gradient(135deg, #0F172A 0%, #1E293B 50%, #334155 100%)",
        padding: "24px 20px 32px",
        borderRadius: "0 0 28px 28px",
        position: "relative", overflow: "hidden",
      }}>
        <div style={{ position: "absolute", top: -30, left: -30, width: 100, height: 100, borderRadius: "50%", background: "rgba(16,185,129,0.08)" }} />
        <div style={{ position: "absolute", bottom: -15, right: 60, width: 60, height: 60, borderRadius: "50%", background: "rgba(16,185,129,0.06)" }} />

        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 24 }}>
          <div style={{
            width: 36, height: 36, borderRadius: 12,
            background: "rgba(255,255,255,0.08)", border: "1px solid rgba(255,255,255,0.1)",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 16, cursor: "pointer",
          }}>🔔</div>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <div style={{ textAlign: "right" }}>
              <div style={{ color: "#fff", fontSize: 18, fontWeight: 700 }}>היי אביחי 👋</div>
              <div style={{ color: "rgba(255,255,255,0.5)", fontSize: 13, fontWeight: 300 }}>מה צריך לעשות היום?</div>
            </div>
            <div style={{
              width: 46, height: 46, borderRadius: 16,
              background: "linear-gradient(135deg, #10B981, #059669)",
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 19, fontWeight: 800, color: "#fff",
              boxShadow: "0 4px 16px rgba(16,185,129,0.3)",
            }}>א</div>
          </div>
        </div>

        {/* Quick categories */}
        <div style={{ display: "flex", gap: 10, overflowX: "auto", paddingBottom: 4 }}>
          {CATEGORIES.slice(0, 5).map((cat, i) => (
            <div key={cat.id} style={{
              display: "flex", flexDirection: "column", alignItems: "center", gap: 6,
              opacity: loaded ? 1 : 0, transform: loaded ? "translateY(0)" : "translateY(12px)",
              transition: `all 0.4s ease ${i * 0.07}s`, cursor: "pointer", minWidth: 62,
            }}>
              <div style={{
                width: 52, height: 52, borderRadius: 16,
                background: "rgba(255,255,255,0.07)", backdropFilter: "blur(10px)",
                display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 23, border: "1px solid rgba(255,255,255,0.06)",
              }}>{cat.icon}</div>
              <span style={{ color: "rgba(255,255,255,0.7)", fontSize: 11, fontWeight: 400, whiteSpace: "nowrap" }}>{cat.label}</span>
            </div>
          ))}
        </div>
      </div>

      <div style={{ padding: "20px 20px 0", flex: 1 }}>
        {/* Navigation cards to demo screens */}
        <div style={{ fontSize: 16, fontWeight: 700, color: "#0F172A", marginBottom: 14, textAlign: "right" }}>🧭 ניווט בין המסכים</div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 24 }}>
          {[
            { label: "הצעות בזמן אמת", icon: "⚡", action: onOffers, color: "#8B5CF6" },
            { label: "מעקב משימה", icon: "📍", action: onTracker, color: "#F59E0B" },
            { label: "צ'אט + תגובות", icon: "💬", action: onChat, color: "#3B82F6" },
            { label: "דירוג כפול", icon: "⭐", action: () => { /* go to rating via tracker */ onTracker(); }, color: "#EC4899" },
          ].map((item, i) => (
            <button key={i} onClick={item.action} style={{
              padding: "18px 12px", borderRadius: 18, border: "none",
              background: "#fff", boxShadow: "0 2px 12px rgba(0,0,0,0.04)",
              cursor: "pointer", display: "flex", flexDirection: "column",
              alignItems: "center", gap: 8, transition: "all 0.2s",
              opacity: loaded ? 1 : 0, transform: loaded ? "scale(1)" : "scale(0.95)",
              transitionDelay: `${0.2 + i * 0.08}s`,
            }}>
              <div style={{
                width: 44, height: 44, borderRadius: 14,
                background: `${item.color}12`, display: "flex",
                alignItems: "center", justifyContent: "center", fontSize: 22,
              }}>{item.icon}</div>
              <span style={{ fontSize: 12, fontWeight: 600, color: "#334155" }}>{item.label}</span>
            </button>
          ))}
        </div>

        {/* Active task */}
        <div style={{ fontSize: 16, fontWeight: 700, color: "#0F172A", marginBottom: 12, textAlign: "right" }}>
          המשימות שלי
          <span style={{ fontSize: 13, fontWeight: 400, color: "#94A3B8", marginRight: 8 }}>(1 פעילות)</span>
        </div>
        <div style={{
          background: "#fff", borderRadius: 20, padding: 18,
          boxShadow: "0 2px 16px rgba(0,0,0,0.04)", border: "1px solid rgba(0,0,0,0.04)",
          opacity: loaded ? 1 : 0, transform: loaded ? "translateY(0)" : "translateY(16px)",
          transition: "all 0.5s ease 0.4s",
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ padding: "4px 12px", borderRadius: 20, background: "#ECFDF5", color: "#059669", fontSize: 13, fontWeight: 700 }}>₪100</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <span style={{ fontSize: 12, color: "#94A3B8" }}>לפני 2 שעות</span>
              <span style={{ padding: "5px 14px", borderRadius: 20, background: "#10B981", color: "#fff", fontSize: 12, fontWeight: 600 }}>פתוחה</span>
            </div>
          </div>
          <div style={{ marginTop: 10, fontSize: 15, fontWeight: 600, color: "#0F172A" }}>משלוח חבילה לרחוב הרצל</div>
          <div style={{ marginTop: 4, fontSize: 13, color: "#64748B" }}>3 הצעות התקבלו</div>
          <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
            <button onClick={onOffers} style={{
              flex: 1, padding: "11px 0", borderRadius: 12,
              background: "#0F172A", border: "none", color: "#fff",
              fontSize: 13, fontWeight: 600, cursor: "pointer",
            }}>צפה בהצעות ⚡</button>
            <button onClick={onTracker} style={{
              flex: 1, padding: "11px 0", borderRadius: 12,
              background: "#F1F5F9", border: "none", color: "#475569",
              fontSize: 13, fontWeight: 500, cursor: "pointer",
            }}>מעקב</button>
          </div>
        </div>
      </div>

      {/* FAB */}
      <div style={{ position: "sticky", bottom: 0, padding: "16px 20px 24px", background: "linear-gradient(transparent, #FAFBFC 30%)" }}>
        <button onClick={onNewTask} style={{
          width: "100%", padding: "17px 0",
          background: "linear-gradient(135deg, #10B981 0%, #059669 100%)",
          color: "#fff", border: "none", borderRadius: 16,
          fontSize: 16, fontWeight: 700, cursor: "pointer",
          boxShadow: "0 8px 30px rgba(16,185,129,0.35)",
          display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
        }}>
          <span style={{ fontSize: 20 }}>+</span>
          פרסם משימה חדשה
        </button>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════
   CREATE TASK FLOW (4 Steps)
   ═══════════════════════════════════════════ */
function CreateTaskFlow({ step, totalSteps, task, setTask, goToStep, goBack, animating, onPublish }) {
  const canProceed = () => {
    if (step === 1) return task.category !== null;
    if (step === 2) return task.title.trim().length >= 3;
    if (step === 3) return task.budget > 0;
    return true;
  };
  const stepLabels = ["קטגוריה", "פרטים", "תשלום", "סיכום"];

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", background: "#FAFBFC" }}>
      {/* Top bar */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        padding: "16px 20px 12px", background: "#fff", borderBottom: "1px solid #F1F5F9",
      }}>
        <div style={{ width: 36 }} />
        <div style={{ fontSize: 17, fontWeight: 700, color: "#0F172A" }}>פרסום משימה חדשה</div>
        <button onClick={goBack} style={{
          width: 36, height: 36, borderRadius: 12, background: "#F1F5F9",
          border: "none", display: "flex", alignItems: "center", justifyContent: "center",
          cursor: "pointer", fontSize: 18, color: "#475569",
        }}>→</button>
      </div>

      {/* Progress */}
      <div style={{ padding: "12px 20px 0", background: "#fff" }}>
        <div style={{ display: "flex", gap: 6 }}>
          {Array.from({ length: totalSteps }).map((_, i) => (
            <div key={i} style={{
              flex: 1, height: 4, borderRadius: 4,
              background: i < step ? "linear-gradient(90deg, #10B981, #059669)" : "#E2E8F0",
              transition: "all 0.4s",
            }} />
          ))}
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
          {stepLabels.map((l, i) => (
            <span key={i} style={{ fontSize: 11, fontWeight: i + 1 === step ? 600 : 400, color: i + 1 <= step ? "#10B981" : "#CBD5E1" }}>{l}</span>
          ))}
        </div>
      </div>

      {/* Content */}
      <div style={{
        flex: 1, padding: 20,
        opacity: animating ? 0 : 1, transform: animating ? "translateX(-20px)" : "translateX(0)",
        transition: "all 0.2s",
      }}>
        {step === 1 && <StepCategory task={task} setTask={setTask} />}
        {step === 2 && <StepDetails task={task} setTask={setTask} />}
        {step === 3 && <StepPayment task={task} setTask={setTask} />}
        {step === 4 && <StepSummary task={task} />}
      </div>

      {/* Action */}
      <div style={{ padding: "16px 20px 28px", background: "#fff", borderTop: "1px solid #F1F5F9" }}>
        <button onClick={() => { if (step < totalSteps) goToStep(step + 1); else onPublish(); }}
          disabled={!canProceed()}
          style={{
            width: "100%", padding: "16px 0",
            background: canProceed() ? "linear-gradient(135deg, #10B981, #059669)" : "#E2E8F0",
            color: canProceed() ? "#fff" : "#94A3B8",
            border: "none", borderRadius: 16, fontSize: 16, fontWeight: 700,
            cursor: canProceed() ? "pointer" : "default",
            boxShadow: canProceed() ? "0 8px 30px rgba(16,185,129,0.3)" : "none",
            transition: "all 0.3s",
          }}
        >{step === totalSteps ? "🚀  פרסם משימה" : "המשך"}</button>
      </div>
    </div>
  );
}

function StepCategory({ task, setTask }) {
  const [loaded, setLoaded] = useState(false);
  useEffect(() => { setTimeout(() => setLoaded(true), 50); }, []);
  return (
    <div>
      <div style={{ marginBottom: 6, textAlign: "right" }}>
        <div style={{ fontSize: 22, fontWeight: 800, color: "#0F172A", marginBottom: 4 }}>מה צריך לעשות?</div>
        <div style={{ fontSize: 14, color: "#94A3B8" }}>בחר קטגוריה שמתאימה למשימה שלך</div>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12, marginTop: 24 }}>
        {CATEGORIES.map((cat, i) => {
          const sel = task.category === cat.id;
          return (
            <button key={cat.id} onClick={() => setTask({ ...task, category: cat.id })} style={{
              padding: "20px 8px 16px", borderRadius: 20,
              border: sel ? `2px solid ${cat.color}` : "2px solid transparent",
              background: sel ? `${cat.color}08` : "#fff",
              boxShadow: sel ? `0 4px 20px ${cat.color}25` : "0 2px 8px rgba(0,0,0,0.03)",
              cursor: "pointer", display: "flex", flexDirection: "column", alignItems: "center", gap: 8,
              transition: "all 0.25s", opacity: loaded ? 1 : 0,
              transform: loaded ? "translateY(0) scale(1)" : "translateY(16px) scale(0.95)",
              transitionDelay: `${i * 0.04}s`,
            }}>
              <div style={{
                width: 48, height: 48, borderRadius: 16,
                background: sel ? `${cat.color}15` : "#F8FAFC",
                display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 24, transition: "all 0.25s", transform: sel ? "scale(1.1)" : "scale(1)",
              }}>{cat.icon}</div>
              <span style={{ fontSize: 13, fontWeight: sel ? 700 : 500, color: sel ? cat.color : "#475569" }}>{cat.label}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function StepDetails({ task, setTask }) {
  const catObj = CATEGORIES.find(c => c.id === task.category);
  return (
    <div>
      <div style={{ marginBottom: 24, textAlign: "right" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, justifyContent: "flex-end", marginBottom: 4 }}>
          {catObj && <span style={{ fontSize: 20 }}>{catObj.icon}</span>}
          <div style={{ fontSize: 22, fontWeight: 800, color: "#0F172A" }}>פרטי המשימה</div>
        </div>
        <div style={{ fontSize: 14, color: "#94A3B8" }}>ככל שתפרט יותר — כך תקבל הצעות טובות יותר</div>
      </div>
      <div style={{ marginBottom: 20 }}>
        <label style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 8, display: "block", textAlign: "right" }}>כותרת קצרה *</label>
        <input value={task.title} onChange={e => setTask({ ...task, title: e.target.value })}
          placeholder='למשל: "משלוח חבילה לרחוב הרצל"' maxLength={100}
          style={{
            width: "100%", padding: "14px 16px", borderRadius: 14, border: "2px solid #E2E8F0",
            fontSize: 15, fontFamily: "'Rubik', sans-serif", direction: "rtl", outline: "none",
            boxSizing: "border-box", background: "#fff",
          }}
          onFocus={e => e.target.style.borderColor = "#10B981"}
          onBlur={e => e.target.style.borderColor = "#E2E8F0"}
        />
        <div style={{ fontSize: 11, color: "#94A3B8", marginTop: 4, textAlign: "left" }}>{task.title.length}/100</div>
      </div>
      <div style={{ marginBottom: 20 }}>
        <label style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 8, display: "block", textAlign: "right" }}>תיאור מפורט</label>
        <textarea value={task.description} onChange={e => setTask({ ...task, description: e.target.value })}
          placeholder="פרט את המשימה: מה בדיוק צריך לעשות, מתי, ופרטים נוספים..."
          maxLength={2000} rows={4}
          style={{
            width: "100%", padding: "14px 16px", borderRadius: 14, border: "2px solid #E2E8F0",
            fontSize: 14, fontFamily: "'Rubik', sans-serif", direction: "rtl", outline: "none",
            resize: "none", boxSizing: "border-box", background: "#fff", lineHeight: 1.6,
          }}
          onFocus={e => e.target.style.borderColor = "#10B981"}
          onBlur={e => e.target.style.borderColor = "#E2E8F0"}
        />
        <div style={{ fontSize: 11, color: "#94A3B8", marginTop: 4, textAlign: "left" }}>{task.description.length}/2000</div>
      </div>
      <div>
        <label style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 8, display: "block", textAlign: "right" }}>
          הוסף תמונה <span style={{ fontWeight: 400, color: "#94A3B8" }}>(רשות)</span>
        </label>
        <div style={{
          border: "2px dashed #D1D5DB", borderRadius: 16, padding: "24px 20px",
          textAlign: "center", cursor: "pointer", background: "#FAFBFC",
        }}>
          <div style={{ fontSize: 28, marginBottom: 6 }}>📷</div>
          <div style={{ fontSize: 13, color: "#64748B", fontWeight: 500 }}>לחץ להעלאת תמונה</div>
        </div>
      </div>
    </div>
  );
}

/* ─── STEP 3: PAYMENT with SMART PRICING (Feature #1) ─── */
function StepPayment({ task, setTask }) {
  const catObj = CATEGORIES.find(c => c.id === task.category);
  const priceRange = catObj?.priceRange || [50, 300];
  const avgPrice = Math.round((priceRange[0] + priceRange[1]) / 2);
  const budgetOptions = [priceRange[0], Math.round(priceRange[0] * 1.5), avgPrice, Math.round(priceRange[1] * 0.7), priceRange[1]];

  const budgetNum = parseInt(task.budget) || 0;
  const isLow = budgetNum > 0 && budgetNum < priceRange[0];
  const isHigh = budgetNum > priceRange[1];
  const isGood = budgetNum >= priceRange[0] && budgetNum <= priceRange[1];

  return (
    <div>
      <div style={{ marginBottom: 24, textAlign: "right" }}>
        <div style={{ fontSize: 22, fontWeight: 800, color: "#0F172A", marginBottom: 4 }}>תשלום ולוגיסטיקה</div>
        <div style={{ fontSize: 14, color: "#94A3B8" }}>הגדר תשלום, דחיפות ומיקום</div>
      </div>

      {/* ★ SMART PRICING SUGGESTION - Feature #1 */}
      <div style={{
        background: "linear-gradient(135deg, #EFF6FF, #F0F9FF)",
        borderRadius: 16, padding: "14px 16px", marginBottom: 20,
        border: "1px solid #BFDBFE",
        display: "flex", alignItems: "center", gap: 12,
      }}>
        <div style={{ fontSize: 28 }}>💡</div>
        <div style={{ flex: 1, textAlign: "right" }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: "#1E40AF" }}>טווח מחירים מומלץ</div>
          <div style={{ fontSize: 12, color: "#3B82F6", marginTop: 2 }}>
            משימות דומות ב{catObj?.label} עלו בין <strong>₪{priceRange[0]}</strong> ל-<strong>₪{priceRange[1]}</strong>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 6 }}>
            <div style={{ flex: 1, height: 6, borderRadius: 6, background: "#DBEAFE", position: "relative", overflow: "hidden" }}>
              <div style={{
                position: "absolute", top: 0, right: 0,
                height: "100%",
                width: budgetNum > 0 ? `${Math.min(100, (budgetNum / priceRange[1]) * 100)}%` : "0%",
                borderRadius: 6,
                background: isLow ? "#F59E0B" : isHigh ? "#EF4444" : "#10B981",
                transition: "all 0.4s ease",
              }} />
            </div>
          </div>
          {budgetNum > 0 && (
            <div style={{
              fontSize: 11, marginTop: 4, fontWeight: 600,
              color: isLow ? "#D97706" : isHigh ? "#DC2626" : "#059669",
            }}>
              {isLow && "⚠️ מחיר נמוך — ייתכן שתקבל פחות הצעות"}
              {isGood && "✅ מחיר מצוין — צפי להצעות רבות"}
              {isHigh && "🔝 מחיר גבוה — תקבל את נותני השירות הטובים ביותר"}
            </div>
          )}
        </div>
      </div>

      {/* Budget input */}
      <div style={{ marginBottom: 24 }}>
        <label style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 10, display: "block", textAlign: "right" }}>💰 תשלום על המשימה</label>
        <div style={{
          display: "flex", alignItems: "center", gap: 8,
          background: "#fff", borderRadius: 16, border: `2px solid ${isLow ? "#F59E0B" : isGood ? "#10B981" : "#E2E8F0"}`,
          padding: "4px 16px", transition: "border-color 0.3s",
        }}>
          <span style={{ fontSize: 16, color: "#64748B", fontWeight: 600 }}>₪</span>
          <input type="number" value={task.budget} onChange={e => setTask({ ...task, budget: e.target.value })}
            placeholder="הזן סכום"
            style={{
              flex: 1, padding: "12px 8px", border: "none", outline: "none",
              fontSize: 24, fontWeight: 700, fontFamily: "'Rubik', sans-serif",
              direction: "rtl", textAlign: "right", color: "#0F172A", background: "transparent",
            }}
          />
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
          {budgetOptions.map(amt => (
            <button key={amt} onClick={() => setTask({ ...task, budget: amt.toString() })} style={{
              padding: "8px 16px", borderRadius: 12,
              border: task.budget === amt.toString() ? "2px solid #10B981" : "2px solid #E2E8F0",
              background: task.budget === amt.toString() ? "#ECFDF5" : "#fff",
              color: task.budget === amt.toString() ? "#059669" : "#475569",
              fontSize: 14, fontWeight: 600, cursor: "pointer", fontFamily: "'Rubik', sans-serif",
            }}>₪{amt}</button>
          ))}
        </div>
      </div>

      {/* Urgency */}
      <div style={{ marginBottom: 24 }}>
        <label style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 10, display: "block", textAlign: "right" }}>⏰ דחיפות</label>
        <div style={{ display: "flex", gap: 8 }}>
          {URGENCY.map(u => {
            const sel = task.urgency === u.id;
            return (
              <button key={u.id} onClick={() => setTask({ ...task, urgency: u.id })} style={{
                flex: 1, padding: "14px 8px", borderRadius: 16,
                border: sel ? "2px solid #10B981" : "2px solid #E2E8F0",
                background: sel ? "#ECFDF5" : "#fff", cursor: "pointer",
                display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
              }}>
                <span style={{ fontSize: 20 }}>{u.icon}</span>
                <span style={{ fontSize: 13, fontWeight: 700, color: sel ? "#059669" : "#334155" }}>{u.label}</span>
                <span style={{ fontSize: 10, color: "#94A3B8" }}>{u.sub}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Location */}
      <div style={{ marginBottom: 24 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
          <label style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, color: "#64748B", cursor: "pointer" }}>
            <input type="checkbox" checked={task.isRemote} onChange={e => setTask({ ...task, isRemote: e.target.checked })} style={{ accentColor: "#10B981" }} />
            משימה מרחוק
          </label>
          <label style={{ fontSize: 14, fontWeight: 600, color: "#334155" }}>📍 מיקום</label>
        </div>
        {!task.isRemote && (
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {[{ icon: "📍", placeholder: "מיקום (מאיפה)", key: "locationFrom" },
              { icon: "🏁", placeholder: "יעד (לאיפה)", key: "locationTo" }].map(f => (
              <div key={f.key} style={{
                display: "flex", alignItems: "center", gap: 10,
                background: "#fff", borderRadius: 14, border: "2px solid #E2E8F0", padding: "0 16px",
              }}>
                <span style={{ fontSize: 16 }}>{f.icon}</span>
                <input value={task[f.key]} onChange={e => setTask({ ...task, [f.key]: e.target.value })}
                  placeholder={f.placeholder}
                  style={{ flex: 1, padding: "14px 8px", border: "none", outline: "none", fontSize: 14, fontFamily: "'Rubik', sans-serif", direction: "rtl", background: "transparent" }}
                />
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Proof */}
      <div>
        <label style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 10, display: "block", textAlign: "right" }}>✅ סוג הוכחה נדרש</label>
        <div style={{ display: "flex", gap: 8 }}>
          {PROOF_TYPES.map(p => {
            const sel = task.proof === p.id;
            return (
              <button key={p.id} onClick={() => setTask({ ...task, proof: p.id })} style={{
                flex: 1, padding: "14px 8px", borderRadius: 16,
                border: sel ? "2px solid #10B981" : "2px solid #E2E8F0",
                background: sel ? "#ECFDF5" : "#fff", cursor: "pointer",
                display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
              }}>
                <span style={{ fontSize: 20 }}>{p.icon}</span>
                <span style={{ fontSize: 12, fontWeight: 600, color: sel ? "#059669" : "#334155" }}>{p.label}</span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function StepSummary({ task }) {
  const catObj = CATEGORIES.find(c => c.id === task.category);
  const urgObj = URGENCY.find(u => u.id === task.urgency);
  const proofObj = PROOF_TYPES.find(p => p.id === task.proof);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => { setTimeout(() => setLoaded(true), 100); }, []);

  const Row = ({ icon, label, value, delay }) => (
    <div style={{
      display: "flex", justifyContent: "space-between", alignItems: "center",
      padding: "14px 0", borderBottom: "1px solid #F1F5F9",
      opacity: loaded ? 1 : 0, transform: loaded ? "translateY(0)" : "translateY(10px)",
      transition: `all 0.3s ease ${delay}s`,
    }}>
      <div style={{ fontSize: 14, fontWeight: 600, color: "#0F172A" }}>{value}</div>
      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
        <span style={{ fontSize: 14, color: "#64748B" }}>{label}</span>
        <span style={{ fontSize: 16 }}>{icon}</span>
      </div>
    </div>
  );

  return (
    <div>
      <div style={{ marginBottom: 24, textAlign: "right" }}>
        <div style={{ fontSize: 22, fontWeight: 800, color: "#0F172A", marginBottom: 4 }}>סיכום המשימה</div>
        <div style={{ fontSize: 14, color: "#94A3B8" }}>בדוק שהכל נכון לפני הפרסום</div>
      </div>
      <div style={{ background: "#fff", borderRadius: 20, padding: "4px 20px 8px", boxShadow: "0 2px 20px rgba(0,0,0,0.04)", border: "1px solid rgba(0,0,0,0.04)" }}>
        <Row icon={catObj?.icon} label="קטגוריה" value={catObj?.label || "—"} delay={0.05} />
        <Row icon="📝" label="כותרת" value={task.title || "—"} delay={0.1} />
        <Row icon="💰" label="תשלום" value={task.budget ? `₪${task.budget}` : "—"} delay={0.15} />
        <Row icon={urgObj?.icon} label="דחיפות" value={urgObj?.label || "—"} delay={0.2} />
        <Row icon="📍" label="מיקום" value={task.isRemote ? "מרחוק" : (task.locationFrom || "לא צוין")} delay={0.25} />
        <Row icon={proofObj?.icon} label="הוכחה" value={proofObj?.label || "—"} delay={0.3} />
      </div>
      <div style={{
        display: "flex", alignItems: "flex-start", gap: 12,
        background: "#EFF6FF", borderRadius: 16, padding: 16, marginTop: 20,
        opacity: loaded ? 1 : 0, transition: "all 0.5s ease 0.4s",
      }}>
        <div style={{ flex: 1, textAlign: "right" }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: "#1E40AF" }}>🛡️ התשלום מאובטח</div>
          <div style={{ fontSize: 12, color: "#3B82F6", lineHeight: 1.5 }}>הכסף יחויב רק כשתבחר נותן שירות, וישוחרר רק אחרי שתאשר השלמה</div>
        </div>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════
   FEATURE #3: REAL-TIME OFFERS
   ═══════════════════════════════════════════ */
function RealTimeOffers({ onBack, onAccept }) {
  const [phase, setPhase] = useState("searching"); // searching → found
  const [providers, setProviders] = useState([]);
  const [searchCount, setSearchCount] = useState(0);

  useEffect(() => {
    const t1 = setInterval(() => setSearchCount(c => c + 1), 400);
    const t2 = setTimeout(() => {
      setProviders([MOCK_PROVIDERS[2]]);
    }, 2000);
    const t3 = setTimeout(() => {
      setProviders([MOCK_PROVIDERS[2], MOCK_PROVIDERS[0]]);
    }, 3500);
    const t4 = setTimeout(() => {
      setProviders(MOCK_PROVIDERS);
      setPhase("found");
    }, 5000);
    return () => { clearInterval(t1); clearTimeout(t2); clearTimeout(t3); clearTimeout(t4); };
  }, []);

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", background: "#FAFBFC" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        padding: "16px 20px", background: "#fff", borderBottom: "1px solid #F1F5F9",
      }}>
        <div style={{ width: 36 }} />
        <div style={{ fontSize: 17, fontWeight: 700, color: "#0F172A" }}>הצעות מחיר</div>
        <button onClick={onBack} style={{
          width: 36, height: 36, borderRadius: 12, background: "#F1F5F9",
          border: "none", cursor: "pointer", fontSize: 18, color: "#475569",
          display: "flex", alignItems: "center", justifyContent: "center",
        }}>→</button>
      </div>

      <div style={{ flex: 1, padding: 20 }}>
        {/* Search animation */}
        {phase === "searching" && providers.length === 0 && (
          <div style={{ textAlign: "center", padding: "40px 0" }}>
            <div style={{ position: "relative", width: 80, height: 80, margin: "0 auto 20px" }}>
              <div style={{
                width: 80, height: 80, borderRadius: "50%",
                border: "4px solid #E2E8F0", borderTopColor: "#10B981",
                animation: "spin 1s linear infinite",
              }} />
              <div style={{
                position: "absolute", top: "50%", left: "50%", transform: "translate(-50%, -50%)",
                fontSize: 28,
              }}>🔍</div>
            </div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "#0F172A", marginBottom: 6 }}>מחפשים נותני שירות...</div>
            <div style={{ fontSize: 14, color: "#64748B" }}>
              סורקים {searchCount} נותני שירות באזור שלך
            </div>
            <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
          </div>
        )}

        {/* Available count */}
        {providers.length > 0 && (
          <div style={{
            display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
            padding: "10px 20px", borderRadius: 30, marginBottom: 16,
            background: "#ECFDF5", border: "1px solid #A7F3D0",
          }}>
            <div style={{
              width: 8, height: 8, borderRadius: "50%", background: "#10B981",
              animation: "pulse 2s infinite",
            }} />
            <span style={{ fontSize: 13, fontWeight: 600, color: "#059669" }}>
              {providers.length} הצעות התקבלו{phase === "searching" ? " — עוד מגיעות..." : ""}
            </span>
            <style>{`@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }`}</style>
          </div>
        )}

        {/* Provider cards */}
        {providers.map((p, i) => (
          <div key={p.id} style={{
            background: "#fff", borderRadius: 20, padding: 18, marginBottom: 12,
            boxShadow: "0 2px 16px rgba(0,0,0,0.04)", border: "1px solid rgba(0,0,0,0.04)",
            animation: "slideIn 0.4s ease forwards",
            animationDelay: `${i * 0.15}s`,
            opacity: 0,
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <div style={{ textAlign: "left" }}>
                <div style={{ fontSize: 22, fontWeight: 800, color: "#059669" }}>₪{p.price}</div>
                <div style={{ fontSize: 11, color: "#94A3B8" }}>זמן הגעה: {p.time}</div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <div style={{ textAlign: "right" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6, justifyContent: "flex-end" }}>
                    <span style={{ fontSize: 15, fontWeight: 700, color: "#0F172A" }}>{p.name}</span>
                    {p.badge && <span style={{
                      fontSize: 10, padding: "2px 8px", borderRadius: 10,
                      background: p.badge.includes("מומלץ") ? "#FEF3C7" : "#ECFDF5",
                      color: p.badge.includes("מומלץ") ? "#D97706" : "#059669",
                      fontWeight: 700,
                    }}>{p.badge}</span>}
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 4, justifyContent: "flex-end", marginTop: 2 }}>
                    <span style={{ fontSize: 12, color: "#64748B" }}>({p.reviews})</span>
                    <span style={{ fontSize: 12, fontWeight: 700, color: "#F59E0B" }}>⭐ {p.rating}</span>
                  </div>
                  <div style={{ fontSize: 11, color: "#94A3B8", marginTop: 2 }}>{p.completedTasks} משימות הושלמו</div>
                </div>
                <div style={{
                  width: 50, height: 50, borderRadius: 16, background: "#F1F5F9",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  fontSize: 26,
                }}>{p.avatar}</div>
              </div>
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
              <button onClick={onAccept} style={{
                flex: 1, padding: "12px 0", borderRadius: 12,
                background: "linear-gradient(135deg, #10B981, #059669)",
                border: "none", color: "#fff", fontSize: 14, fontWeight: 700,
                cursor: "pointer", boxShadow: "0 4px 16px rgba(16,185,129,0.25)",
              }}>בחר נותן שירות ✓</button>
              <button style={{
                padding: "12px 20px", borderRadius: 12,
                background: "#F1F5F9", border: "none", color: "#475569",
                fontSize: 14, fontWeight: 500, cursor: "pointer",
              }}>💬</button>
            </div>
          </div>
        ))}
        <style>{`@keyframes slideIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }`}</style>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════
   FEATURE #8: LIVE TASK TRACKER
   ═══════════════════════════════════════════ */
function LiveTracker({ onBack, onChat, onRate }) {
  const [currentStatus, setCurrentStatus] = useState(0);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    setLoaded(true);
    const timers = [];
    timers.push(setTimeout(() => setCurrentStatus(1), 1500));
    timers.push(setTimeout(() => setCurrentStatus(2), 3500));
    timers.push(setTimeout(() => setCurrentStatus(3), 5500));
    timers.push(setTimeout(() => setCurrentStatus(4), 8000));
    return () => timers.forEach(clearTimeout);
  }, []);

  const provider = MOCK_PROVIDERS[2];

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", background: "#FAFBFC" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        padding: "16px 20px", background: "#fff", borderBottom: "1px solid #F1F5F9",
      }}>
        <div style={{ width: 36 }} />
        <div style={{ fontSize: 17, fontWeight: 700, color: "#0F172A" }}>מעקב משימה</div>
        <button onClick={onBack} style={{
          width: 36, height: 36, borderRadius: 12, background: "#F1F5F9",
          border: "none", cursor: "pointer", fontSize: 18, color: "#475569",
          display: "flex", alignItems: "center", justifyContent: "center",
        }}>→</button>
      </div>

      <div style={{ flex: 1, padding: 20 }}>
        {/* Provider card */}
        <div style={{
          background: "#fff", borderRadius: 20, padding: 18,
          boxShadow: "0 2px 16px rgba(0,0,0,0.04)", marginBottom: 20,
          display: "flex", alignItems: "center", justifyContent: "space-between",
        }}>
          <button onClick={onChat} style={{
            padding: "10px 20px", borderRadius: 12,
            background: "#0F172A", border: "none", color: "#fff",
            fontSize: 13, fontWeight: 600, cursor: "pointer",
            display: "flex", alignItems: "center", gap: 6,
          }}>💬 צ'אט</button>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <div style={{ textAlign: "right" }}>
              <div style={{ fontSize: 15, fontWeight: 700, color: "#0F172A" }}>{provider.name}</div>
              <div style={{ fontSize: 12, color: "#F59E0B", fontWeight: 600 }}>⭐ {provider.rating} ({provider.reviews})</div>
            </div>
            <div style={{
              width: 48, height: 48, borderRadius: 16, background: "#F1F5F9",
              display: "flex", alignItems: "center", justifyContent: "center", fontSize: 24,
            }}>{provider.avatar}</div>
          </div>
        </div>

        {/* Timeline */}
        <div style={{
          background: "#fff", borderRadius: 20, padding: "20px 24px",
          boxShadow: "0 2px 16px rgba(0,0,0,0.04)",
        }}>
          <div style={{ fontSize: 16, fontWeight: 700, color: "#0F172A", marginBottom: 20, textAlign: "right" }}>סטטוס המשימה</div>
          {TASK_STATUSES.map((status, i) => {
            const isActive = i === currentStatus;
            const isDone = i < currentStatus;
            const isFuture = i > currentStatus;
            const isLast = i === TASK_STATUSES.length - 1;

            return (
              <div key={status.id} style={{ display: "flex", gap: 14, marginBottom: isLast ? 0 : 0 }}>
                {/* Timeline line + dot */}
                <div style={{ display: "flex", flexDirection: "column", alignItems: "center", width: 32 }}>
                  <div style={{
                    width: isActive ? 32 : 24, height: isActive ? 32 : 24,
                    borderRadius: "50%",
                    background: isDone ? status.color : isActive ? status.color : "#E2E8F0",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: isActive ? 16 : 12,
                    transition: "all 0.5s ease",
                    boxShadow: isActive ? `0 0 0 6px ${status.color}20` : "none",
                    flexShrink: 0,
                  }}>
                    {isDone ? "✓" : status.icon}
                  </div>
                  {!isLast && (
                    <div style={{
                      width: 3, flex: 1, minHeight: 30,
                      background: isDone ? "#10B981" : "#E2E8F0",
                      borderRadius: 4, margin: "4px 0",
                      transition: "background 0.5s ease",
                    }} />
                  )}
                </div>

                {/* Content */}
                <div style={{
                  flex: 1, paddingBottom: isLast ? 0 : 16,
                  opacity: isFuture ? 0.4 : 1,
                  transition: "opacity 0.5s ease",
                }}>
                  <div style={{
                    fontSize: 14, fontWeight: isActive ? 700 : 500,
                    color: isActive ? status.color : isDone ? "#0F172A" : "#94A3B8",
                    transition: "all 0.3s",
                  }}>{status.label}</div>
                  {isActive && (
                    <div style={{
                      fontSize: 12, color: "#64748B", marginTop: 4,
                      display: "flex", alignItems: "center", gap: 6,
                    }}>
                      <div style={{
                        width: 6, height: 6, borderRadius: "50%",
                        background: status.color,
                        animation: "pulse 1.5s infinite",
                      }} />
                      עכשיו
                    </div>
                  )}
                  {isDone && (
                    <div style={{ fontSize: 11, color: "#94A3B8", marginTop: 2 }}>הושלם ✓</div>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {/* Rate button (appears when done) */}
        {currentStatus >= 4 && (
          <button onClick={onRate} style={{
            width: "100%", padding: "16px 0", marginTop: 20,
            background: "linear-gradient(135deg, #F59E0B, #D97706)",
            border: "none", borderRadius: 16, color: "#fff",
            fontSize: 16, fontWeight: 700, cursor: "pointer",
            boxShadow: "0 8px 30px rgba(245,158,11,0.3)",
            animation: "slideIn 0.5s ease",
          }}>⭐ דרג את נותן השירות</button>
        )}
      </div>
      <style>{`@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }`}</style>
    </div>
  );
}

/* ═══════════════════════════════════════════
   FEATURE #7: CHAT with QUICK REPLIES
   ═══════════════════════════════════════════ */
function ChatScreen({ onBack }) {
  const [messages, setMessages] = useState([
    { id: 1, from: "provider", text: "היי! ראיתי את המשימה שלך. אני זמין ויכול להתחיל עוד 15 דקות 🚀", time: "14:23" },
    { id: 2, from: "provider", text: "יש לי ניסיון של 3 שנים במשלוחים באזור. אשמח לעזור!", time: "14:24" },
  ]);
  const [input, setInput] = useState("");
  const messagesEnd = useRef(null);
  const provider = MOCK_PROVIDERS[2];

  useEffect(() => {
    messagesEnd.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const sendMessage = (text) => {
    if (!text.trim()) return;
    const newMsg = { id: Date.now(), from: "user", text, time: new Date().toLocaleTimeString("he-IL", { hour: "2-digit", minute: "2-digit" }) };
    setMessages(prev => [...prev, newMsg]);
    setInput("");

    // Auto reply
    setTimeout(() => {
      const replies = [
        "בטח! אני מגיע בהקדם 💪",
        "אין בעיה, נסגור את הפרטים",
        "מצוין, אני בדרך!",
        "כן, יש לי ניסיון רב בתחום הזה 👍",
      ];
      setMessages(prev => [...prev, {
        id: Date.now() + 1, from: "provider",
        text: replies[Math.floor(Math.random() * replies.length)],
        time: new Date().toLocaleTimeString("he-IL", { hour: "2-digit", minute: "2-digit" }),
      }]);
    }, 1500);
  };

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", background: "#F8FAFC" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        padding: "14px 20px", background: "#fff", borderBottom: "1px solid #F1F5F9",
      }}>
        <div style={{ width: 36 }} />
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 15, fontWeight: 700, color: "#0F172A" }}>{provider.name}</div>
            <div style={{ fontSize: 11, color: "#10B981", fontWeight: 500, display: "flex", alignItems: "center", gap: 4, justifyContent: "flex-end" }}>
              <div style={{ width: 6, height: 6, borderRadius: "50%", background: "#10B981" }} />
              מחובר עכשיו
            </div>
          </div>
          <div style={{
            width: 40, height: 40, borderRadius: 14, background: "#F1F5F9",
            display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22,
          }}>{provider.avatar}</div>
        </div>
        <button onClick={onBack} style={{
          width: 36, height: 36, borderRadius: 12, background: "#F1F5F9",
          border: "none", cursor: "pointer", fontSize: 18, color: "#475569",
          display: "flex", alignItems: "center", justifyContent: "center",
        }}>→</button>
      </div>

      {/* Messages */}
      <div style={{ flex: 1, padding: "16px 20px", overflowY: "auto" }}>
        {messages.map(msg => (
          <div key={msg.id} style={{
            display: "flex", justifyContent: msg.from === "user" ? "flex-end" : "flex-start",
            marginBottom: 10,
          }}>
            <div style={{
              maxWidth: "80%", padding: "12px 16px", borderRadius: 18,
              background: msg.from === "user"
                ? "linear-gradient(135deg, #10B981, #059669)"
                : "#fff",
              color: msg.from === "user" ? "#fff" : "#0F172A",
              fontSize: 14, lineHeight: 1.5,
              boxShadow: msg.from === "user" ? "0 4px 12px rgba(16,185,129,0.2)" : "0 2px 8px rgba(0,0,0,0.04)",
              borderBottomLeftRadius: msg.from === "user" ? 18 : 4,
              borderBottomRightRadius: msg.from === "user" ? 4 : 18,
            }}>
              {msg.text}
              <div style={{
                fontSize: 10, marginTop: 4, textAlign: "left",
                opacity: 0.6,
              }}>{msg.time}</div>
            </div>
          </div>
        ))}
        <div ref={messagesEnd} />
      </div>

      {/* Quick Replies */}
      <div style={{ padding: "8px 20px", overflowX: "auto", display: "flex", gap: 8 }}>
        {QUICK_REPLIES.map(qr => (
          <button key={qr.id} onClick={() => sendMessage(qr.text)} style={{
            padding: "8px 14px", borderRadius: 20,
            background: "#fff", border: "1.5px solid #E2E8F0",
            fontSize: 12, fontWeight: 500, color: "#475569",
            cursor: "pointer", whiteSpace: "nowrap",
            display: "flex", alignItems: "center", gap: 4,
            fontFamily: "'Rubik', sans-serif",
            transition: "all 0.2s",
          }}>
            <span>{qr.icon}</span> {qr.text}
          </button>
        ))}
      </div>

      {/* Input */}
      <div style={{
        padding: "12px 20px 24px",
        background: "#fff", borderTop: "1px solid #F1F5F9",
        display: "flex", gap: 10, alignItems: "center",
      }}>
        <button onClick={() => sendMessage(input)} style={{
          width: 44, height: 44, borderRadius: 14,
          background: input.trim() ? "linear-gradient(135deg, #10B981, #059669)" : "#E2E8F0",
          border: "none", cursor: input.trim() ? "pointer" : "default",
          display: "flex", alignItems: "center", justifyContent: "center",
          fontSize: 18, color: "#fff", transition: "all 0.2s",
          transform: "scaleX(-1)",
        }}>➤</button>
        <input value={input} onChange={e => setInput(e.target.value)}
          onKeyDown={e => e.key === "Enter" && sendMessage(input)}
          placeholder="הקלד הודעה..."
          style={{
            flex: 1, padding: "12px 16px", borderRadius: 14,
            border: "2px solid #E2E8F0", outline: "none",
            fontSize: 14, fontFamily: "'Rubik', sans-serif",
            direction: "rtl", background: "#F8FAFC",
          }}
          onFocus={e => e.target.style.borderColor = "#10B981"}
          onBlur={e => e.target.style.borderColor = "#E2E8F0"}
        />
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════
   FEATURE #10: DUAL RATING (Airbnb Style)
   ═══════════════════════════════════════════ */
function DualRating({ onBack }) {
  const [stars, setStars] = useState(0);
  const [hoveredStar, setHoveredStar] = useState(0);
  const [review, setReview] = useState("");
  const [tags, setTags] = useState([]);
  const [submitted, setSubmitted] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => { setTimeout(() => setLoaded(true), 100); }, []);

  const provider = MOCK_PROVIDERS[2];
  const ratingTags = [
    { id: "punctual", label: "דייקן" },
    { id: "professional", label: "מקצועי" },
    { id: "friendly", label: "אדיב" },
    { id: "clean", label: "נקי ומסודר" },
    { id: "fast", label: "מהיר" },
    { id: "communicative", label: "תקשורת טובה" },
  ];

  const toggleTag = (id) => {
    setTags(prev => prev.includes(id) ? prev.filter(t => t !== id) : [...prev, id]);
  };

  const starLabels = ["", "גרוע", "לא טוב", "סביר", "טוב", "מעולה!"];

  if (submitted) {
    return (
      <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#FAFBFC", padding: 40, textAlign: "center" }}>
        <div style={{ fontSize: 64, marginBottom: 20, animation: "bounce 0.6s ease" }}>🎉</div>
        <div style={{ fontSize: 24, fontWeight: 800, color: "#0F172A", marginBottom: 8 }}>תודה על הדירוג!</div>
        <div style={{ fontSize: 15, color: "#64748B", lineHeight: 1.6, marginBottom: 8 }}>
          הדירוג שלך עוזר לקהילת AnySkill להמשיך להשתפר
        </div>
        <div style={{
          background: "#EFF6FF", borderRadius: 16, padding: "14px 20px",
          fontSize: 13, color: "#3B82F6", marginBottom: 30,
          border: "1px solid #BFDBFE",
        }}>
          💡 גם {provider.name} ידרג אותך — הדירוג ההדדי יופיע לשניכם
        </div>
        <button onClick={onBack} style={{
          padding: "14px 48px", borderRadius: 16,
          background: "linear-gradient(135deg, #10B981, #059669)",
          border: "none", color: "#fff", fontSize: 16, fontWeight: 700,
          cursor: "pointer", boxShadow: "0 8px 30px rgba(16,185,129,0.3)",
        }}>חזרה למשימות</button>
        <style>{`@keyframes bounce { 0% { transform: scale(0); } 50% { transform: scale(1.2); } 100% { transform: scale(1); } }`}</style>
      </div>
    );
  }

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", background: "#FAFBFC" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        padding: "16px 20px", background: "#fff", borderBottom: "1px solid #F1F5F9",
      }}>
        <div style={{ width: 36 }} />
        <div style={{ fontSize: 17, fontWeight: 700, color: "#0F172A" }}>דירוג המשימה</div>
        <button onClick={onBack} style={{
          width: 36, height: 36, borderRadius: 12, background: "#F1F5F9",
          border: "none", cursor: "pointer", fontSize: 18, color: "#475569",
          display: "flex", alignItems: "center", justifyContent: "center",
        }}>→</button>
      </div>

      <div style={{ flex: 1, padding: 20 }}>
        {/* Provider avatar */}
        <div style={{
          textAlign: "center", marginBottom: 28,
          opacity: loaded ? 1 : 0, transform: loaded ? "translateY(0)" : "translateY(20px)",
          transition: "all 0.5s ease",
        }}>
          <div style={{
            width: 80, height: 80, borderRadius: 24, background: "#F1F5F9",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 40, margin: "0 auto 12px",
            boxShadow: "0 4px 20px rgba(0,0,0,0.06)",
          }}>{provider.avatar}</div>
          <div style={{ fontSize: 20, fontWeight: 700, color: "#0F172A" }}>{provider.name}</div>
          <div style={{ fontSize: 13, color: "#64748B" }}>משלוח חבילה לרחוב הרצל</div>
        </div>

        {/* Stars */}
        <div style={{
          textAlign: "center", marginBottom: 24,
          opacity: loaded ? 1 : 0, transition: "all 0.5s ease 0.1s",
        }}>
          <div style={{ fontSize: 16, fontWeight: 600, color: "#334155", marginBottom: 12 }}>איך היה השירות?</div>
          <div style={{ display: "flex", justifyContent: "center", gap: 8, marginBottom: 8 }}>
            {[1, 2, 3, 4, 5].map(s => (
              <button key={s}
                onMouseEnter={() => setHoveredStar(s)}
                onMouseLeave={() => setHoveredStar(0)}
                onClick={() => setStars(s)}
                style={{
                  background: "none", border: "none", cursor: "pointer",
                  fontSize: 36, transition: "all 0.15s",
                  transform: (hoveredStar >= s || stars >= s) ? "scale(1.15)" : "scale(1)",
                  filter: (hoveredStar >= s || stars >= s) ? "none" : "grayscale(1) opacity(0.3)",
                }}
              >⭐</button>
            ))}
          </div>
          {(stars > 0 || hoveredStar > 0) && (
            <div style={{
              fontSize: 15, fontWeight: 700,
              color: (hoveredStar || stars) >= 4 ? "#059669" : (hoveredStar || stars) >= 3 ? "#F59E0B" : "#EF4444",
              transition: "color 0.2s",
            }}>{starLabels[hoveredStar || stars]}</div>
          )}
        </div>

        {/* Tags */}
        {stars > 0 && (
          <div style={{
            marginBottom: 24, animation: "slideIn 0.3s ease",
          }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 10, textAlign: "right" }}>מה בלט? (רשות)</div>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8, justifyContent: "flex-end" }}>
              {ratingTags.map(tag => {
                const sel = tags.includes(tag.id);
                return (
                  <button key={tag.id} onClick={() => toggleTag(tag.id)} style={{
                    padding: "8px 16px", borderRadius: 20,
                    border: sel ? "2px solid #10B981" : "2px solid #E2E8F0",
                    background: sel ? "#ECFDF5" : "#fff",
                    color: sel ? "#059669" : "#475569",
                    fontSize: 13, fontWeight: sel ? 600 : 400,
                    cursor: "pointer", fontFamily: "'Rubik', sans-serif",
                    transition: "all 0.2s",
                  }}>{tag.label}</button>
                );
              })}
            </div>
          </div>
        )}

        {/* Review text */}
        {stars > 0 && (
          <div style={{ marginBottom: 24, animation: "slideIn 0.3s ease 0.1s", animationFillMode: "backwards" }}>
            <label style={{ fontSize: 14, fontWeight: 600, color: "#334155", marginBottom: 8, display: "block", textAlign: "right" }}>
              כתוב ביקורת <span style={{ fontWeight: 400, color: "#94A3B8" }}>(רשות)</span>
            </label>
            <textarea value={review} onChange={e => setReview(e.target.value)}
              placeholder="ספר לאחרים איך עבר השירות..."
              rows={3}
              style={{
                width: "100%", padding: "14px 16px", borderRadius: 14,
                border: "2px solid #E2E8F0", outline: "none", resize: "none",
                fontSize: 14, fontFamily: "'Rubik', sans-serif", direction: "rtl",
                boxSizing: "border-box", background: "#fff", lineHeight: 1.6,
              }}
              onFocus={e => e.target.style.borderColor = "#10B981"}
              onBlur={e => e.target.style.borderColor = "#E2E8F0"}
            />
          </div>
        )}

        {/* Dual rating notice */}
        <div style={{
          background: "#FFFBEB", borderRadius: 16, padding: "14px 16px",
          border: "1px solid #FDE68A", display: "flex", alignItems: "flex-start", gap: 10,
          textAlign: "right",
        }}>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 13, fontWeight: 700, color: "#92400E" }}>⭐ דירוג הדדי בסגנון Airbnb</div>
            <div style={{ fontSize: 12, color: "#B45309", lineHeight: 1.5, marginTop: 2 }}>
              גם {provider.name} מדרג אותך. הדירוגים נחשפים רק אחרי ששניכם סיימתם — כך שניכם כנים יותר.
            </div>
          </div>
        </div>
      </div>

      {/* Submit */}
      <div style={{ padding: "16px 20px 28px", background: "#fff", borderTop: "1px solid #F1F5F9" }}>
        <button onClick={() => stars > 0 && setSubmitted(true)}
          disabled={stars === 0}
          style={{
            width: "100%", padding: "16px 0",
            background: stars > 0 ? "linear-gradient(135deg, #F59E0B, #D97706)" : "#E2E8F0",
            color: stars > 0 ? "#fff" : "#94A3B8",
            border: "none", borderRadius: 16, fontSize: 16, fontWeight: 700,
            cursor: stars > 0 ? "pointer" : "default",
            boxShadow: stars > 0 ? "0 8px 30px rgba(245,158,11,0.3)" : "none",
            transition: "all 0.3s",
          }}>⭐ שלח דירוג</button>
      </div>
      <style>{`@keyframes slideIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }`}</style>
    </div>
  );
}
