import 'dart:async';
import 'dart:math';
import '../models/activity_type.dart';
import 'websocket_service.dart';

class DemoService {
  Timer? _predictionTimer;
  Timer? _collectionTimer;
  final Random _random = Random();

  final StreamController<ActivityPrediction> _predictionController =
      StreamController<ActivityPrediction>.broadcast();
  final StreamController<int> _collectionSamplesController =
      StreamController<int>.broadcast();

  Stream<ActivityPrediction> get predictionStream => _predictionController.stream;
  Stream<int> get collectionSamplesStream => _collectionSamplesController.stream;

  // Time tracker for realistic motion patterns
  double _time = 0.0;

  // Mock activity sequence for realistic demo
  final List<ActivityType> _activitySequence = [
    ActivityType.standing,
    ActivityType.walking,
    ActivityType.running,
    ActivityType.walking,
    ActivityType.walkingUpstairs,
    ActivityType.walkingDownstairs,
    ActivityType.walking,
    ActivityType.sitting,
  ];
  int _currentActivityIndex = 0;

  void startMockPredictions() {
    stopMockPredictions();

    // Send predictions every 2-4 seconds
    _predictionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      final activity = _activitySequence[_currentActivityIndex];

      final prediction = ActivityPrediction(
        activity: activity,
        timestamp: DateTime.now(),
      );

      _predictionController.add(prediction);

      // Move to next activity (with some randomness)
      if (_random.nextDouble() > 0.6) {
        _currentActivityIndex = (_currentActivityIndex + 1) % _activitySequence.length;
      }
    });
  }

  void stopMockPredictions() {
    _predictionTimer?.cancel();
    _predictionTimer = null;
    _currentActivityIndex = 0;
  }

  void startMockCollection({required int samplingRate}) {
    stopMockCollection();

    int samplesSent = 0;
    _time = 0.0; // Reset time for consistent patterns
    final intervalMs = (1000 / samplingRate).round(); // Convert Hz to ms

    _collectionTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      samplesSent++;
      _collectionSamplesController.add(samplesSent);
      _time += intervalMs / 1000.0; // Increment time in seconds
      // Collection runs indefinitely until stopMockCollection() is called
    });
  }

  void stopMockCollection() {
    _collectionTimer?.cancel();
    _collectionTimer = null;
    _time = 0.0;
  }

  // Generate mock collection statistics
  Map<String, dynamic> getMockCollectionStats({
    required String activityLabel,
    required int sampleCount,
  }) {
    return {
      'activity': activityLabel,
      'samples_collected': sampleCount,
      'duration_seconds': (sampleCount / 50).toStringAsFixed(1),
      'sampling_rate': '50 Hz',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // Generate realistic walking motion sensor data
  Map<String, Map<String, double>> getMockSensorData() {
    // Walking characteristics:
    // - Step frequency: ~1.5 Hz (90 steps per minute - moderate walking pace)
    // - Accelerometer shows periodic vertical oscillations and some lateral movement
    // - Gyroscope shows small rotational movements

    final stepFrequency = 1.5; // Hz
    final omega = 2 * pi * stepFrequency; // Angular frequency

    // Add some random noise for realism (small amplitude)
    double noise() => (_random.nextDouble() - 0.5) * 0.3;

    // Accelerometer (m/s²)
    // Y-axis: Vertical oscillation around gravity (9.81 m/s²)
    // Walking creates vertical acceleration as body moves up/down with each step
    final accelY = 9.81 + sin(omega * _time) * 1.5 + noise();

    // X-axis: Lateral (side-to-side) movement
    // Walking creates some lateral sway
    final accelX = sin(omega * _time * 2) * 0.6 + noise();

    // Z-axis: Forward/backward acceleration
    // Some forward movement with each step
    final accelZ = cos(omega * _time) * 0.4 + noise();

    // Gyroscope (rad/s)
    // Small rotational movements that match the walking cycle
    // X-axis: Pitch (forward/backward tilt)
    final gyroX = sin(omega * _time) * 0.3 + noise() * 0.1;

    // Y-axis: Yaw (turning left/right)
    // Minimal during straight walking
    final gyroY = noise() * 0.05;

    // Z-axis: Roll (side-to-side tilt)
    // Alternates with each step
    final gyroZ = cos(omega * _time * 2) * 0.25 + noise() * 0.1;

    return {
      'accelerometer': {
        'x': accelX,
        'y': accelY,
        'z': accelZ,
      },
      'gyroscope': {
        'x': gyroX,
        'y': gyroY,
        'z': gyroZ,
      },
      'magnetometer': {
        'x': 20.0 + _random.nextDouble() * 2.0,
        'y': -15.0 + _random.nextDouble() * 2.0,
        'z': 40.0 + _random.nextDouble() * 2.0,
      },
    };
  }

  void dispose() {
    stopMockPredictions();
    stopMockCollection();
    _predictionController.close();
    _collectionSamplesController.close();
  }
}
