import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../config/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppStateProvider>();
    _urlController = TextEditingController(text: appState.websocketUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final appState = context.read<AppStateProvider>();
    appState.setWebSocketUrl(_urlController.text);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  void _resetToDefault() {
    setState(() {
      _urlController.text = AppConstants.defaultWebSocketUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WebSocket Configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'WebSocket URL',
                hintText: 'ws://192.168.1.100:8000/ws',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _resetToDefault,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text('Demo Mode', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Consumer<AppStateProvider>(
              builder: (context, appState, _) {
                return SwitchListTile(
                  title: const Text('Enable Demo Mode'),
                  subtitle: const Text(
                    'Use simulated sensor data for testing without physical sensors',
                  ),
                  value: appState.isDemoMode,
                  onChanged: (value) {
                    appState.setDemoMode(value);
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text('About', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Human Activity Recognition App\n'
              'Collects sensor data and recognizes activities.\n\n'
              'Supported sensors: Accelerometer, Gyroscope, Magnetometer\n'
              'Activities: Walking, Running, Sitting, Standing',
            ),
          ],
        ),
      ),
    );
  }
}
