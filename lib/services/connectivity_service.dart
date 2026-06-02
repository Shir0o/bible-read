import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectionStatus { online, offline }

class ConnectivityService {
  final Connectivity _connectivity;
  final StreamController<ConnectionStatus> _controller =
      StreamController<ConnectionStatus>.broadcast();

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  Stream<ConnectionStatus> get status => _controller.stream;

  Future<void> _init() async {
    final result = await _connectivity.checkConnectivity();
    _updateStatus(result);
    _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    // connectivity_plus 6.x returns a List<ConnectivityResult>
    if (results.contains(ConnectivityResult.none)) {
      _controller.add(ConnectionStatus.offline);
    } else {
      _controller.add(ConnectionStatus.online);
    }
  }

  Future<ConnectionStatus> checkStatus() async {
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      return ConnectionStatus.offline;
    }
    return ConnectionStatus.online;
  }

  void dispose() {
    _controller.close();
  }
}
