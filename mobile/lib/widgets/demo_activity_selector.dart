import 'package:flutter/material.dart';
import '../models/activity_type.dart';

class DemoActivitySelector extends StatelessWidget {
  final ActivityType selectedActivity;
  final Function(ActivityType) onActivityChanged;

  const DemoActivitySelector({
    super.key,
    required this.selectedActivity,
    required this.onActivityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'DEMO MODE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[700],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Simulating activity pattern:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<ActivityType>(
              initialValue: selectedActivity,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                ActivityType.walking,
                ActivityType.running,
                ActivityType.sitting,
                ActivityType.standing,
              ].map((activity) {
                return DropdownMenuItem(
                  value: activity,
                  child: Row(
                    children: [
                      Icon(_getActivityIcon(activity), size: 20),
                      const SizedBox(width: 8),
                      Text(activity.displayName),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  onActivityChanged(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getActivityIcon(ActivityType activity) {
    switch (activity) {
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.sitting:
        return Icons.event_seat;
      case ActivityType.standing:
        return Icons.accessibility_new;
      case ActivityType.unknown:
        return Icons.help_outline;
    }
  }
}
