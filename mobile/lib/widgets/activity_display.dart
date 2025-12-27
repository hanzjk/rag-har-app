import 'package:flutter/material.dart';
import '../models/activity_type.dart';

class ActivityDisplay extends StatefulWidget {
  final ActivityType activity;
  final bool isBuffering;
  final DateTime? lastUpdated;

  const ActivityDisplay({
    super.key,
    required this.activity,
    this.isBuffering = false,
    this.lastUpdated,
  });

  @override
  State<ActivityDisplay> createState() => _ActivityDisplayState();
}

class _ActivityDisplayState extends State<ActivityDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(ActivityDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Trigger pulse animation when activity changes
    if (oldWidget.activity != widget.activity &&
        widget.activity != ActivityType.unknown &&
        !widget.isBuffering) {
      _pulseController.forward().then((_) => _pulseController.reverse());
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
      case ActivityType.walkingUpstairs:
        return Icons.stairs;
      case ActivityType.walkingDownstairs:
        return Icons.stairs;
      case ActivityType.unknown:
        return Icons.help_outline;
    }
  }

  Color _getActivityColor(BuildContext context, ActivityType activity) {
    switch (activity) {
      case ActivityType.walking:
        return Colors.blue;
      case ActivityType.running:
        return Colors.red;
      case ActivityType.sitting:
        return Colors.green;
      case ActivityType.standing:
        return Colors.orange;
      case ActivityType.walkingUpstairs:
        return Colors.purple;
      case ActivityType.walkingDownstairs:
        return Colors.teal;
      case ActivityType.unknown:
        return Colors.grey;
    }
  }

  String _getTimeAgo(DateTime? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 2) {
      return 'Just now';
    } else if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.all(24.0),
        width: double.infinity,
        child: widget.isBuffering
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(strokeWidth: 6),
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
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait ~30 seconds',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              )
            : Stack(
                children: [
                  // Main content
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Add top spacing only when LIVE badge is present
                        if (widget.activity != ActivityType.unknown)
                          const SizedBox(height: 20),

                        // Animated activity display
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: ScaleTransition(
                          key: ValueKey(widget.activity),
                          scale: _pulseAnimation,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getActivityIcon(widget.activity),
                                size: 100,
                                color: _getActivityColor(context, widget.activity),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.activity.displayName.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _getActivityColor(
                                          context, widget.activity),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Last updated timestamp
                      if (widget.lastUpdated != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.update,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getTimeAgo(widget.lastUpdated),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    ),
                  ),

                  // Live indicator badge - top right, only for non-unknown activities
                  if (widget.activity != ActivityType.unknown)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
