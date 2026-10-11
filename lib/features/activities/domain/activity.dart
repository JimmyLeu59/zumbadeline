import 'package:flutter/material.dart';

class Activity {
  const Activity({
    required this.id,
    required this.name,
    required this.colorCode,
    required this.icon,
  });

  final String id;
  final String name;
  final String colorCode;
  final String icon;

  Color get accentColor {
    final value = int.tryParse(colorCode.replaceFirst('#', ''), radix: 16);
    return Color(0xFF000000 | (value ?? 0x006750A4));
  }

  IconData get iconData => switch (icon) {
    'mic' || 'music_note' => Icons.mic_rounded,
    'hiking' || 'sports' => Icons.hiking_rounded,
    'celebration' => Icons.celebration_rounded,
    _ => Icons.fitness_center_rounded,
  };

  factory Activity.fromMap(Map<String, dynamic> map) => Activity(
    id: map['id'] as String,
    name: map['name'] as String,
    colorCode: map['color_code'] as String? ?? '#6750A4',
    icon: map['icon'] as String? ?? 'fitness_center',
  );
}
