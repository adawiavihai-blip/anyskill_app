import 'package:flutter/material.dart';

class MassageSpecialty {
  final String id;
  final String nameHe;
  final String nameEn;
  final String icon;
  final String taglineHe;
  final Color bgColor;

  const MassageSpecialty({
    required this.id,
    required this.nameHe,
    required this.nameEn,
    required this.icon,
    required this.taglineHe,
    required this.bgColor,
  });
}

const List<MassageSpecialty> kMassageSpecialties = [
  MassageSpecialty(id: 'swedish',      nameHe: 'שוודי',        nameEn: 'Swedish',      icon: '🌿', taglineHe: 'קלאסי, רגיעה',       bgColor: Color(0xFFE1F5EE)),
  MassageSpecialty(id: 'deep_tissue',  nameHe: 'רקמות עמוק',   nameEn: 'Deep Tissue',  icon: '💪', taglineHe: 'שחרור, עוצמתי',      bgColor: Color(0xFFFFF1ED)),
  MassageSpecialty(id: 'pregnancy',    nameHe: 'הריון',        nameEn: 'Pregnancy',    icon: '🤰', taglineHe: 'בטוח, עדין',         bgColor: Color(0xFFFFF0F5)),
  MassageSpecialty(id: 'hot_stones',   nameHe: 'אבנים חמות',   nameEn: 'Hot Stones',   icon: '🪨', taglineHe: 'חמימות, עומק',       bgColor: Color(0xFFFFF8E7)),
  MassageSpecialty(id: 'sports',       nameHe: 'ספורט',        nameEn: 'Sports',       icon: '⚡', taglineHe: 'התאוששות',           bgColor: Color(0xFFEBF5FF)),
  MassageSpecialty(id: 'couples',      nameHe: 'זוגי',         nameEn: 'Couples',      icon: '👫', taglineHe: 'חוויה משותפת',       bgColor: Color(0xFFF3E8FF)),
  MassageSpecialty(id: 'aromatherapy', nameHe: 'ארומטרפי',     nameEn: 'Aromatherapy', icon: '🌸', taglineHe: 'שמנים אתריים',      bgColor: Color(0xFFECFDF5)),
  MassageSpecialty(id: 'thai',         nameHe: 'תאילנדי',      nameEn: 'Thai',         icon: '🇹🇭', taglineHe: 'מתיחות',             bgColor: Color(0xFFEBF5FF)),
  MassageSpecialty(id: 'reflexology',  nameHe: 'רפלקסולוגיה',  nameEn: 'Reflexology',  icon: '👣', taglineHe: 'כפות רגליים',        bgColor: Color(0xFFFFF0F5)),
  MassageSpecialty(id: 'shiatsu',      nameHe: 'שיאצו',        nameEn: 'Shiatsu',      icon: '🥢', taglineHe: 'לחיצה יפנית',       bgColor: Color(0xFFFFF8E7)),
  MassageSpecialty(id: 'lymphatic',    nameHe: 'לימפטי',       nameEn: 'Lymphatic',    icon: '🩹', taglineHe: 'ניקוז',              bgColor: Color(0xFFE1F5EE)),
  MassageSpecialty(id: 'ayurveda',     nameHe: 'איורוודה',     nameEn: 'Ayurveda',     icon: '🧘', taglineHe: 'הודי מסורתי',        bgColor: Color(0xFFF3E8FF)),
  MassageSpecialty(id: 'reiki',        nameHe: 'רייקי',        nameEn: 'Reiki',        icon: '🤲', taglineHe: 'אנרגטי',             bgColor: Color(0xFFECFDF5)),
  MassageSpecialty(id: 'infant',       nameHe: 'תינוקות',      nameEn: 'Infant',       icon: '👶', taglineHe: 'עדין',               bgColor: Color(0xFFFFF0F5)),
];

MassageSpecialty? findSpecialty(String id) {
  for (final s in kMassageSpecialties) {
    if (s.id == id) return s;
  }
  return null;
}
