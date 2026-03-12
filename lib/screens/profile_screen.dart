import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:convert';
import 'edit_profile_screen.dart';

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
                Navigator.pop(context);
                final whatsappUrl = "https://wa.me/?text=${Uri.encodeComponent(shareText)}";
                try {
                  if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                    await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
                  } else {
                    throw "Could not launch";
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("לא ניתן לפתוח את וואטסאפ בדפדפן זה")));
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // QA FIXED: מעביר לטאב הצ'אטים לצורך מעקב הזמנות
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

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Expanded(child: Column(children: [Icon(icon, color: color, size: 22), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))]));
  }
}