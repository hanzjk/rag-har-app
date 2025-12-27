import 'package:flutter/material.dart';
import '../models/sensor_data.dart';

class SensorDataDisplay extends StatelessWidget {
  final String sensorName;
  final SensorReading? reading;
  final Color color;

  const SensorDataDisplay({
    super.key,
    required this.sensorName,
    required this.reading,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors, color: color),
                const SizedBox(width: 8),
                Text(
                  sensorName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (reading != null) ...[
              _buildAxisRow('X', reading!.x, Colors.red),
              const SizedBox(height: 8),
              _buildAxisRow('Y', reading!.y, Colors.green),
              const SizedBox(height: 8),
              _buildAxisRow('Z', reading!.z, Colors.blue),
            ] else
              const Text('No data'),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisRow(String axis, double value, Color color) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            axis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value.toStringAsFixed(3),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}
