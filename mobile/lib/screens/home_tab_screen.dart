import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/activity_provider.dart';
import '../providers/app_state_provider.dart';
import '../models/activity_type.dart';

class HomeTabScreen extends StatefulWidget {
  const HomeTabScreen({super.key});

  @override
  State<HomeTabScreen> createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends State<HomeTabScreen> {
  String _getActivityDescription(ActivityType activity) {
    switch (activity) {
      case ActivityType.running:
        return 'High-intensity movement with fast pace detected';
      case ActivityType.walking:
        return 'Steady movement with moderate pace detected';
      case ActivityType.sitting:
        return 'Minimal movement detected, user at rest';
      case ActivityType.standing:
        return 'Stationary position with slight movements';
      case ActivityType.walkingUpstairs:
        return 'Upward movement with elevated effort detected';
      case ActivityType.walkingDownstairs:
        return 'Downward movement with controlled pace';
      case ActivityType.unknown:
        return 'Analyzing movement patterns...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Activity Detected Card
              Consumer2<ActivityProvider, AppStateProvider>(
                builder: (context, activityProvider, appState, _) {
                  final currentActivity = activityProvider.currentActivity;
                  final isEnabled = appState.activityRecognitionEnabled;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isEnabled
                            ? [Color(0xFF8B5CF6), Color(0xFF9333EA)]
                            : [Color(0xFF9CA3AF), Color(0xFF6B7280)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isEnabled
                            ? Color(0xFFC084FC).withOpacity(0.3)
                            : Color(0xFF9CA3AF).withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isEnabled ? Icons.sensors : Icons.sensors_off,
                              color: Colors.white,
                              size: 20
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isEnabled ? 'Activity Detected' : 'Activity Recognition Disabled',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (isEnabled)
                          Text(
                            currentActivity.displayName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (isEnabled)
                          const SizedBox(height: 4),
                        Text(
                          isEnabled
                              ? _getActivityDescription(currentActivity)
                              : 'Enable Activity Recognition in Settings to start tracking',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Devices',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.phone_android,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Phone',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.battery_std,
                                        color: Colors.white,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '87%',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Stats Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  _buildStatCard(
                    icon: Icons.directions_walk,
                    iconColor: Color(0xFF3B82F6),
                    title: 'Steps',
                    value: '8,547',
                    change: '+12% vs yesterday',
                    changePositive: true,
                  ),
                  _buildStatCard(
                    icon: Icons.local_fire_department,
                    iconColor: Color(0xFFFF6B00),
                    title: 'Calories',
                    value: '520',
                    unit: 'kcal',
                    change: '+8% vs yesterday',
                    changePositive: true,
                  ),
                  _buildStatCard(
                    icon: Icons.access_time,
                    iconColor: Color(0xFF10B981),
                    title: 'Active Time',
                    value: '75',
                    unit: 'min',
                    change: '-5% vs yesterday',
                    changePositive: false,
                  ),
                  _buildStatCard(
                    icon: Icons.favorite,
                    iconColor: Color(0xFFEF4444),
                    title: 'Heart Rate',
                    value: '78',
                    unit: 'bpm',
                    change: null,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Quick Start Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Color(0xFFE5E7EB),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Start',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickStartButton(
                            icon: Icons.directions_walk,
                            label: 'Walk',
                            color: Color(0xFFDDEEFF),
                            iconColor: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickStartButton(
                            icon: Icons.directions_run,
                            label: 'Run',
                            color: Color(0xFFFFE5E5),
                            iconColor: Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickStartButton(
                            icon: Icons.fitness_center,
                            label: 'Workout',
                            color: Color(0xFFE0F5E9),
                            iconColor: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? unit,
    String? change,
    bool? changePositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
              if (change != null) ...[
                const SizedBox(height: 4),
                Text(
                  change,
                  style: TextStyle(
                    fontSize: 12,
                    color: changePositive == true
                        ? Color(0xFF059669)
                        : Color(0xFFDC2626),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStartButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: iconColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
