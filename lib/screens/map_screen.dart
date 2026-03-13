import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'expert_profile_screen.dart'; // QA FIXED: קישור לדף המומחה החדש

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";

  @override
  void initState() {
    super.initState();
    _checkPermissionAndGetLocation();
  }

  // QA FIXED: הוספת בדיקת הרשאות לפני השגת מיקום
  Future<void> _checkPermissionAndGetLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      
      LatLng pos = LatLng(position.latitude, position.longitude);
      
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }

      if (myUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(myUid).update({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }

      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 14));
      
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("מומחים מסביבך", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Color(0xFF0047AB)),
            onPressed: _getUserLocation,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // שליפת מומחים ולקוחות אונליין
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('isOnline', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          Set<Marker> markers = {};

          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            double? lat = data['latitude']?.toDouble();
            double? lng = data['longitude']?.toDouble();
            
            // זיהוי האם מדובר במומחה (בודקים אם יש לו סוג שירות שאינו 'אחר')
            bool isExpert = data['serviceType'] != null && data['serviceType'] != 'אחר';

            if (lat != null && lng != null) {
              markers.add(
                Marker(
                  markerId: MarkerId(doc.id),
                  position: LatLng(lat, lng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    isExpert ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: data['name'] ?? "משתמש",
                    snippet: isExpert 
                      ? "${data['serviceType']} ⭐ ${data['rating'] ?? '5.0'}" 
                      : "לקוח",
                    onTap: () {
                      if (isExpert) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ExpertProfileScreen(
                              expertId: doc.id,
                              expertName: data['name'] ?? "מומחה",
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              );
            }
          }

          return GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? const LatLng(32.0853, 34.7818), 
              zoom: 13
            ),
            onMapCreated: (controller) => _mapController = controller,
            markers: markers,
            myLocationEnabled: true, 
            myLocationButtonEnabled: false, // ביטלנו כי יש לנו כפתור מותאם ב-AppBar
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            style: _mapStyle, // אופציונלי: הוספת סטייל נקי למפה
          );
        },
      ),
    );
  }

  // סטייל למפה (אופציונלי - נותן מראה מקצועי יותר)
  final String? _mapStyle = null; 
}