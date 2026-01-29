import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/activity_provider.dart';
import '../models/activity_type.dart';
import '../services/websocket_service.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Consumer<ActivityProvider>(
            builder: (context, activityProvider, _) {
              final history = activityProvider.activityHistory;

              // Calculate insights from history
              final activityCounts = <ActivityType, int>{};
              for (final prediction in history) {
                activityCounts[prediction.activity] =
                    (activityCounts[prediction.activity] ?? 0) + 1;
              }

              // Find most common activity
              ActivityType? mostCommon;
              int maxCount = 0;
              activityCounts.forEach((activity, count) {
                if (count > maxCount) {
                  maxCount = count;
                  mostCommon = activity;
                }
              });

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Activity Insights
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.insights,
                              color: Color(0xFF8B5CF6),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Activity Insights',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInsightRow(
                          'Total Activity Recognitions',
                          '${history.length}',
                          Icons.analytics_outlined,
                        ),
                        const SizedBox(height: 12),
                        _buildInsightRow(
                          'Most Common',
                          mostCommon?.displayName ?? 'N/A',
                          Icons.star_outline,
                        ),
                        const SizedBox(height: 12),
                        _buildInsightRow(
                          'Unique Activities',
                          '${activityCounts.length}',
                          Icons.category_outlined,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Activity Breakdown
                  if (activityCounts.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.pie_chart_outline,
                                color: Color(0xFF3B82F6),
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Activity Breakdown',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...activityCounts.entries.map((entry) {
                            final percentage =
                                (entry.value / history.length * 100)
                                    .toStringAsFixed(0);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _getActivityColor(
                                        entry.key,
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      _getActivityIcon(entry.key),
                                      color: _getActivityColor(entry.key),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key.displayName,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: entry.value / history.length,
                                            backgroundColor: Colors.grey[200],
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  _getActivityColor(entry.key),
                                                ),
                                            minHeight: 6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '$percentage%',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Activity History
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.history,
                                  color: Color(0xFF10B981),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Activity Recognition History',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (history.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  activityProvider.clearHistory();
                                },
                                child: Text(
                                  'Clear',
                                  style: TextStyle(
                                    color: Colors.red[400],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (history.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.timeline_outlined,
                                    size: 60,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No activity recognition data yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Start activity recognition to see activity recognition data',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: history.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: Colors.grey[200]),
                            itemBuilder: (context, index) {
                              final prediction = history[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: _getActivityColor(
                                          prediction.activity,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _getActivityIcon(prediction.activity),
                                        color: _getActivityColor(
                                          prediction.activity,
                                        ),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            prediction.activity.displayName,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateFormat(
                                              'HH:mm:ss',
                                            ).format(prediction.timestamp),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (prediction.reasoning != null)
                                      IconButton(
                                        icon: Icon(
                                          Icons.info_outline,
                                          color: Colors.grey[400],
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          _showReasoningDialog(
                                            context,
                                            prediction,
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInsightRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Color(0xFF6B7280)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  void _showReasoningDialog(
    BuildContext context,
    ActivityPrediction prediction,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getActivityIcon(prediction.activity),
              color: _getActivityColor(prediction.activity),
            ),
            const SizedBox(width: 8),
            Text(prediction.activity.displayName),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            prediction.reasoning ?? 'No reasoning available',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  IconData _getActivityIcon(ActivityType activityType) {
    switch (activityType) {
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.sitting:
        return Icons.event_seat;
      case ActivityType.standing:
        return Icons.accessibility_new;
      case ActivityType.jumping:
        return Icons.trending_up;
      case ActivityType.lying:
        return Icons.hotel;
      case ActivityType.unknown:
        return Icons.help_outline;
    }
  }

  Color _getActivityColor(ActivityType activityType) {
    switch (activityType) {
      case ActivityType.walking:
        return Color(0xFF3B82F6);
      case ActivityType.running:
        return Color(0xFFEF4444);
      case ActivityType.sitting:
        return Color(0xFF10B981);
      case ActivityType.standing:
        return Color(0xFFF59E0B);
      case ActivityType.jumping:
        return Color(0xFF8B5CF6);
      case ActivityType.lying:
        return Color(0xFF06B6D4);
      case ActivityType.unknown:
        return Color(0xFF6B7280);
    }
  }
}
