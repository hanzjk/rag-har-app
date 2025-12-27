enum ActivityType {
  walking,
  running,
  sitting,
  standing,
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
      case ActivityType.unknown:
        return 'Unknown';
    }
  }
}
