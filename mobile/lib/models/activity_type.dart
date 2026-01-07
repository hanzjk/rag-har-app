enum ActivityType {
  walking,
  running,
  sitting,
  standing,
  lying,
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
      case 'lying_down':
        return ActivityType.lying;
      case 'lying':
        return ActivityType.lying;
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
      case ActivityType.lying:
        return 'Lying';
      case ActivityType.jumping:
        return 'Jumping';
      case ActivityType.unknown:
        return 'Unknown';
    }
  }
}
