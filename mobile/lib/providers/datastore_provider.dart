import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/websocket_service.dart';

class DataStoreProvider extends ChangeNotifier {
  final WebSocketService _websocketService;

  List<DataStore> _datastores = [];
  DataStore? _currentDatastore;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<String>? _messageSubscription;

  List<DataStore> get datastores => _datastores;
  DataStore? get currentDatastore => _currentDatastore;
  bool get isLoading => _isLoading;
  String? get error => _error;

  DataStoreProvider({required WebSocketService websocketService})
      : _websocketService = websocketService {
    _setupMessageListener();
  }

  void _setupMessageListener() {
    _messageSubscription = _websocketService.messageStream.listen((message) {
      try {
        final data = jsonDecode(message);
        final type = data['type'];

        switch (type) {
          case 'datastores_list':
            _handleDatastoresList(data);
            break;
          case 'datastore_created':
            _handleDatastoreCreated(data);
            break;
          case 'datastore_deleted':
            _handleDatastoreDeleted(data);
            break;
          case 'datastore_switched':
            _handleDatastoreSwitched(data);
            break;
          case 'current_datastore':
            _handleCurrentDatastore(data);
            break;
          case 'datastore_error':
            _handleDatastoreError(data);
            break;
        }
      } catch (e) {
        // Ignore non-datastore messages
      }
    });
  }

  void _handleDatastoresList(Map<String, dynamic> data) {
    _isLoading = false;
    if (data['success'] == true) {
      final list = data['datastores'] as List<dynamic>? ?? [];
      _datastores = list.map((d) => DataStore.fromJson(d)).toList();
      _error = null;

      // Update current datastore from list
      final activeStore = _datastores.where((d) => d.isActive).firstOrNull;
      if (activeStore != null) {
        _currentDatastore = activeStore;
      }
    } else {
      _error = data['error'] ?? 'Failed to load data stores';
    }
    notifyListeners();
  }

  void _handleDatastoreCreated(Map<String, dynamic> data) {
    _isLoading = false;
    if (data['success'] == true) {
      _error = null;
      // Refresh the list
      refreshDatastores();
    } else {
      _error = data['error'] ?? 'Failed to create data store';
      notifyListeners();
    }
  }

  void _handleDatastoreDeleted(Map<String, dynamic> data) {
    _isLoading = false;
    if (data['success'] == true) {
      _error = null;
      // Refresh the list
      refreshDatastores();
    } else {
      _error = data['error'] ?? 'Failed to delete data store';
      notifyListeners();
    }
  }

  void _handleDatastoreSwitched(Map<String, dynamic> data) {
    _isLoading = false;
    if (data['success'] == true) {
      _currentDatastore = DataStore(
        name: data['name'] ?? '',
        collectionName: data['collection_name'] ?? '',
        sampleCount: data['sample_count'] ?? 0,
        isDefault: data['is_default'] ?? false,
        isActive: true,
      );
      _error = null;
      // Refresh the list to update active states
      refreshDatastores();
    } else {
      _error = data['error'] ?? 'Failed to switch data store';
      notifyListeners();
    }
  }

  void _handleCurrentDatastore(Map<String, dynamic> data) {
    _currentDatastore = DataStore(
      name: data['name'] ?? '',
      collectionName: data['collection_name'] ?? '',
      sampleCount: data['sample_count'] ?? 0,
      isDefault: data['is_default'] ?? false,
      isActive: true,
    );
    notifyListeners();
  }

  void _handleDatastoreError(Map<String, dynamic> data) {
    _isLoading = false;
    _error = data['error'] ?? 'An error occurred';
    notifyListeners();
  }

  void refreshDatastores() {
    _isLoading = true;
    _error = null;
    notifyListeners();
    _websocketService.listDatastores();
  }

  void createDatastore(String name) {
    _isLoading = true;
    _error = null;
    notifyListeners();
    _websocketService.createDatastore(name);
  }

  void deleteDatastore(String collectionName) {
    _isLoading = true;
    _error = null;
    notifyListeners();
    _websocketService.deleteDatastore(collectionName);
  }

  void setDatastore(String collectionName) {
    _isLoading = true;
    _error = null;
    notifyListeners();
    _websocketService.setDatastore(collectionName);
  }

  void getCurrentDatastore() {
    _websocketService.getCurrentDatastore();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}
