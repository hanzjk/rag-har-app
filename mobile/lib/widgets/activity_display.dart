import 'package:flutter/material.dart';
import '../models/activity_type.dart';

class ActivityDisplay extends StatefulWidget {
  final ActivityType activity;
  final bool isBuffering;
  final DateTime? lastUpdated;
  final String? reasoning;
  final VoidCallback? onStop;

  const ActivityDisplay({
    super.key,
    required this.activity,
    this.isBuffering = false,
    this.lastUpdated,
    this.reasoning,
    this.onStop,
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
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Color(0xFFF9FAFB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color(0xFFE5E7EB),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24.0),
          width: double.infinity,
      child: widget.isBuffering
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 6,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'PROCESSING',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Analyzing activity...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take up to 30 seconds',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFD1D5DB),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _getActivityColor(context, widget.activity),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _getActivityColor(context, widget.activity).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _getActivityIcon(widget.activity),
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Activity',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              widget.activity.displayName,
                              key: ValueKey(widget.activity),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.reasoning != null && widget.reasoning!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Divider(color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 20,
                        color: Color(0xFF8B5CF6),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reasoning',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.reasoning!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF374151),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (widget.lastUpdated != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Color(0xFF9CA3AF),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getTimeAgo(widget.lastUpdated),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
        ),
        // Stop button in top-right corner
        if (widget.onStop != null)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onStop,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stop_circle,
                        size: 16,
                        color: Colors.red[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Stop',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
