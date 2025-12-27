import 'package:flutter/material.dart';
import '../models/activity_type.dart';

class ActivityDisplay extends StatelessWidget {
  final ActivityType activity;
  final double confidence;
  final bool isBuffering;

  const ActivityDisplay({
    super.key,
    required this.activity,
    required this.confidence,
    this.isBuffering = false,
  });

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

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.7) return Colors.green;
    if (confidence >= 0.4) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.all(24.0),
        width: double.infinity,
        child: isBuffering
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'BUFFERING',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Collecting sensor data...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait ~2 seconds',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getActivityIcon(activity),
                    size: 100,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    activity.displayName.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: confidence,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getConfidenceColor(confidence),
                    ),
                    minHeight: 8,
                  ),
                ],
              ),
      ),
    );
  }
}
