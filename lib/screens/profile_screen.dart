import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'edit_profile_screen.dart';
import '../widgets/vip_confetti.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;

  // QA FIXED: שיתוף חכם ללא שגיאות קומפילציה
  void _shareProfile(String name, String uid) async {
    final String profileLink = "https://anyskill-6fdf3.web.app/#/expert?id=$uid";
    final String shareText = "היי! מזמין אותך לצפות בפרופיל המקצועי שלי ב-AnySkill ולהזמין שירות מאובטח בנאמנות: $profileLink";
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 15),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("שתף פרופיל להגדלת מכירות", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            ListTile(
              // QA FIXED: שימוש באייקון גנרי למניעת שגיאת Build
              leading: const CircleAvatar(backgroundColor: Color(0xFF25D366), child: Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20)),
              title: const Text("שלח ישירות לוואטסאפ"),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                final whatsappUrl = "https://wa.me/?text=${Uri.encodeComponent(shareText)}";
                try {
                  if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                    await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
                  } else {
                    throw "Could not launch";
                  }
                } catch (e) {
                  messenger.showSnackBar(const SnackBar(content: Text("לא ניתן לפתוח את וואטסאפ בדפדפן זה")));
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.copy, color: Colors.white)),
              title: const Text("העתק לינק לפרופיל"),
              onTap: () {
                Clipboard.setData(ClipboardData(text: profileLink));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("הלינק הועתק! הדבק אותו היכן שתרצה.")));
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("הפרופיל שלי", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        leading: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            return IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.green),
              onPressed: () => _shareProfile(data['name'] ?? "מומחה", user?.uid ?? ""),
              tooltip: "שתף פרופיל",
            );
          }
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
            builder: (context, snapshot) {
              var data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
              return IconButton(
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF0047AB)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => EditProfileScreen(userData: data)),
                ),
              );
            }
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: "התנתק",
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("התנתקות"),
                content: const Text("האם אתה בטוח שברצונך להתנתק?"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      FirebaseAuth.instance.signOut();
                    },
                    child: const Text("התנתק", style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 30),
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.shade100, width: 4),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                    ),
                    child: CircleAvatar(
                      radius: 65,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: (data['profileImage'] != null && data['profileImage'] != "")
                          ? NetworkImage(data['profileImage']) : null,
                      child: (data['profileImage'] == null || data['profileImage'] == "")
                          ? const Icon(Icons.person, size: 65, color: Colors.grey) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (data['isVerified'] ?? false) 
                      const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.verified, color: Colors.blue, size: 22)),
                    Text(data['name'] ?? "משתמש אנונימי", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(data['email'] ?? "", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                
                const SizedBox(height: 30),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15)],
                  ),
                  child: _buildProfileStats(data),
                ),

                const SizedBox(height: 25),

                // ── VIP Section (providers only) ──────────────────────
                if (data['isProvider'] == true) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: _buildVipSection(context, data),
                  ),
                  const SizedBox(height: 20),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("מעבר לצ'אטים למעקב אחרי עסקאות...")));
                    },
                    icon: const Icon(Icons.list_alt_rounded),
                    label: const Text("למעקב אחרי ההזמנות שלי"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200))
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                _buildAboutMe(data['aboutMe']),
                const SizedBox(height: 30),
                _buildGallery(data['gallery']),
                const SizedBox(height: 40),
                TextButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text("התנתק מהמערכת", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                ),
                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAboutMe(String? about) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Align(alignment: Alignment.centerRight, child: Text("על עצמי", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          const SizedBox(height: 10),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade100)),
            child: Text(about ?? "עדיין לא נכתב תיאור.", style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildGallery(List<dynamic>? gallery) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Padding(padding: EdgeInsets.only(right: 25, bottom: 15), child: Text("גלריית עבודות", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        if (gallery == null || gallery.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("אין תמונות בגלריה", style: TextStyle(color: Colors.grey))))
        else SizedBox(height: 160, child: ListView.builder(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: gallery.length, itemBuilder: (context, index) {
          String imgData = gallery[index].toString();
          return Container(width: 150, margin: const EdgeInsets.only(left: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)], image: DecorationImage(image: imgData.startsWith('http') ? NetworkImage(imgData) : MemoryImage(base64Decode(imgData.contains(',') ? imgData.split(',').last : imgData)) as ImageProvider, fit: BoxFit.cover)));
        })),
      ],
    );
  }

  Widget _buildProfileStats(Map<String, dynamic> data) {
    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem("דירוג", "${data['rating'] ?? '5.0'}", Icons.star, Colors.amber),
          VerticalDivider(color: Colors.grey.shade200, thickness: 1),
          _statItem("יתרה", "₪${(data['balance'] ?? 0).toStringAsFixed(0)}", Icons.account_balance_wallet, Colors.green),
          VerticalDivider(color: Colors.grey.shade200, thickness: 1),
          _statItem("עבודות", "${data['reviewsCount'] ?? '0'}", Icons.check_circle, Colors.blue),
        ],
      ),
    );
  }

  // ── VIP / Promoted Section ─────────────────────────────────────────────

  Widget _buildVipSection(BuildContext context, Map<String, dynamic> data) {
    final isPromoted  = data['isPromoted'] as bool? ?? false;
    final expiryTs    = data['promotionExpiryDate'] as Timestamp?;
    final expiryDate  = expiryTs?.toDate();
    final now         = DateTime.now();
    final isActive    = isPromoted && expiryDate != null && expiryDate.isAfter(now);
    final isExpired   = isPromoted && expiryDate != null && !expiryDate.isAfter(now);
    final daysLeft    = isActive ? expiryDate!.difference(now).inDays + 1 : 0;

    if (isActive) {
      // Active VIP card
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB347), Color(0xFFFFCC02)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text("$daysLeft ימים נותרו",
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const Row(
                  children: [
                    Icon(Icons.star_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 6),
                    Text("VIP פעיל",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "הפרופיל שלך מוצג ראשון בחיפוש עם זוהר זהוב ✨",
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white, width: 1.5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.autorenew_rounded, size: 18),
                label: Text("חדש מנוי ל-$daysLeft+ יום"),
                onPressed: () => _showVipSheet(context, data),
              ),
            ),
          ],
        ),
      );
    }

    // Expired or not-promoted — show upsell card
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isExpired)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text("פג תוקף",
                      style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                )
              else
                const SizedBox(),
              const Row(
                children: [
                  Icon(Icons.star_outline_rounded,
                      color: Colors.amber, size: 20),
                  SizedBox(width: 6),
                  Text("חשיפה מוגברת VIP",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Benefits list
          ...[
            ("🏆", "מופיע ראשון בכל תוצאות חיפוש"),
            ("✨", "זוהר זהוב ותג 'מומלץ' על הכרטיס"),
            ("📈", "עד 5× יותר צפיות בפרופיל"),
            ("🔥", "עדיפות בבקשות דחופות"),
          ].map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(b.$2,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87)),
                    const SizedBox(width: 8),
                    Text(b.$1, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC300),
                foregroundColor: Colors.black87,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.star_rounded, size: 20),
              label: const Text("הצטרף ל-VIP — ₪99/חודש",
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: () => _showVipSheet(context, data),
            ),
          ),
        ],
      ),
    );
  }

  void _showVipSheet(BuildContext context, Map<String, dynamic> data) {
    final balance = (data['balance'] as num? ?? 0).toDouble();
    final hasBalance = balance >= 99;
    bool _isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),

              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB347), Color(0xFFFFCC02)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Text("הצטרף ל-VIP",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Price
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("₪",
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const Text("99",
                      style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                          height: 1)),
                  const Padding(
                    padding: EdgeInsets.only(top: 28),
                    child: Text("/חודש",
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "יתרה נוכחית: ₪${balance.toStringAsFixed(0)}",
                style: TextStyle(
                    color: hasBalance ? Colors.green[600] : Colors.red[600],
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Benefits summary
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  children: [
                    ("🏆", "מופיע ראשון בכל תוצאות חיפוש"),
                    ("✨", "זוהר זהוב + תג 'מומלץ'"),
                    ("📈", "עד 5× יותר צפיות"),
                    ("🔥", "עדיפות בבקשות דחופות"),
                  ].map((b) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(b.$2,
                                style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            Text(b.$1,
                                style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                      )).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // CTA button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasBalance
                        ? const Color(0xFFFFC300)
                        : Colors.grey[300],
                    foregroundColor:
                        hasBalance ? Colors.black87 : Colors.grey[500],
                    minimumSize: const Size(double.infinity, 58),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: hasBalance && !_isLoading
                      ? () async {
                          setSheet(() => _isLoading = true);
                          try {
                            await FirebaseFunctions.instance
                                .httpsCallable('activateVipSubscription')
                                .call();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              VipConfetti.show(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFFFFC300),
                                  content: Text(
                                    "🎉 ברוך הבא ל-VIP! הפרופיל שלך מוצג ראשון מעכשיו",
                                    style: TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  duration: Duration(seconds: 4),
                                ),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              setSheet(() => _isLoading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    backgroundColor: Colors.red,
                                    content: Text("שגיאה: $e")),
                              );
                            }
                          }
                        }
                      : null,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black87))
                      : Text(
                          hasBalance
                              ? "⭐ הפעל VIP — ₪99 מהיתרה"
                              : "יתרה לא מספיקה (נדרש ₪99)",
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              if (!hasBalance) ...[
                const SizedBox(height: 10),
                Text(
                  "טען את הארנק שלך כדי להפעיל VIP",
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}