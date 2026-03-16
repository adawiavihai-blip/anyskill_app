import 'package:flutter/material.dart';

// זו הרשימה המרכזית. כל האפליקציה תמשוך מכאן את השמות.
// אם תשנה כאן ל"כושר", זה ישתנה אוטומטית גם ב"גלה" וגם ב"עריכה".
// ignore: constant_identifier_names
const List<Map<String, dynamic>> APP_CATEGORIES = [
  {'name': 'שיפוצים',       'icon': Icons.build,              'iconName': 'build',              'img': 'https://images.unsplash.com/photo-1581094794329-c8112a89af12?w=500'},
  {'name': 'ניקיון',         'icon': Icons.cleaning_services,  'iconName': 'cleaning_services',  'img': 'https://images.unsplash.com/photo-1581578731548-c64695cc6958?w=500'},
  {'name': 'צילום',          'icon': Icons.camera_alt,         'iconName': 'camera_alt',         'img': 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=500'},
  {'name': 'אימון כושר',    'icon': Icons.fitness_center,     'iconName': 'fitness_center',     'img': 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=500'},
  {'name': 'שיעורים פרטיים','icon': Icons.school,             'iconName': 'school',             'img': 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=500'},
  {'name': 'עיצוב גרפי',   'icon': Icons.palette,            'iconName': 'palette',            'img': 'https://images.unsplash.com/photo-1558655146-d09347e92766?w=500'},
];