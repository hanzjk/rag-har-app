enum ActivityType {
  walking,
  running,
  sitting,
  standing,
  walkingUpstairs,
  walkingDownstairs,
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
      case 'walking_upstairs':
      case 'walkingupstairs':
        return ActivityType.walkingUpstairs;
      case 'walking_downstairs':
      case 'walkingdownstairs':
        return ActivityType.walkingDownstairs;
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
      case ActivityType.walkingUpstairs:
        return 'Walking Upstairs';
      case ActivityType.walkingDownstairs:
        return 'Walking Downstairs';
      case ActivityType.unknown:
        return 'Unknown';
    }
  }
}
