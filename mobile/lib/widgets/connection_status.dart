import 'package:flutter/material.dart';
import '../services/websocket_service.dart' as ws;

class ConnectionStatusBanner extends StatelessWidget {
  final ws.ConnectionState connectionState;

  const ConnectionStatusBanner({
    super.key,
    required this.connectionState,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    IconData icon;
    String text;

    switch (connectionState) {
      case ws.ConnectionState.connected:
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
        text = 'Connected';
        break;
      case ws.ConnectionState.connecting:
        backgroundColor = Colors.orange;
        icon = Icons.sync;
        text = 'Connecting...';
        break;
      case ws.ConnectionState.disconnected:
        backgroundColor = Colors.grey;
        icon = Icons.cloud_off;
        text = 'Disconnected';
        break;
      case ws.ConnectionState.error:
        backgroundColor = Colors.red;
        icon = Icons.error;
        text = 'Connection Error';
        break;
    }

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
