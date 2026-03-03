import 'package:flutter/material.dart';

enum ActivityType {
  walking,
  running,
  sitting,
  standing,
  jumping,
  unknown;

  static ActivityType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'walking':
        return ActivityType.walking;
      case 'running':
        return ActivityType.running;
      case 'sitting':
        return ActivityType.sitting;
      case 'standing':
        return ActivityType.standing;
      case 'jumping':
        return ActivityType.jumping;
      default:
        return ActivityType.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case ActivityType.walking:
        return 'Walking';
      case ActivityType.running:
        return 'Running';
      case ActivityType.sitting:
        return 'Sitting';
      case ActivityType.standing:
        return 'Standing';
      case ActivityType.jumping:
        return 'Jumping';
      case ActivityType.unknown:
        return 'Unknown';
    }
  }

  // Short name for chart markers (max 4 chars)
  String get shortName {
    switch (this) {
      case ActivityType.walking:
        return 'Walk';
      case ActivityType.running:
        return 'Run';
      case ActivityType.sitting:
        return 'Sit';
      case ActivityType.standing:
        return 'Stand';
      case ActivityType.jumping:
        return 'Jump';
      case ActivityType.unknown:
        return '?';
    }
  }

  // Color for activity type (used in charts and markers)
  Color get color {
    switch (this) {
      case ActivityType.walking:
        return const Color(0xFF3B82F6); // Blue
      case ActivityType.running:
        return const Color(0xFFEF4444); // Red
      case ActivityType.sitting:
        return const Color(0xFF10B981); // Green
      case ActivityType.standing:
        return const Color(0xFF8B5CF6); // Purple
      case ActivityType.jumping:
        return const Color(0xFFF59E0B); // Amber
      case ActivityType.unknown:
        return const Color(0xFF6B7280); // Gray
    }
  }
}
