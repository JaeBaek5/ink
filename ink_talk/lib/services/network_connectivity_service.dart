import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 네트워크 연결 상태
enum NetworkStatus {
  none,
  wifi,
  mobile,
  other,
}

/// 네트워크 연결 감지 서비스 (재연결 배너·대기열용)
class NetworkConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  NetworkStatus _status = NetworkStatus.none;
  NetworkStatus get status => _status;

  /// 온라인 여부 (none이 아니면 true)
  bool get isOnline {
    switch (_status) {
      case NetworkStatus.none:
        return false;
      case NetworkStatus.wifi:
      case NetworkStatus.mobile:
      case NetworkStatus.other:
        return true;
    }
  }

  NetworkConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateFromResult(result);
    } catch (e) {
      debugPrint('연결 상태 확인 실패: $e');
    }
    _subscription = _connectivity.onConnectivityChanged.listen(_updateFromResult);
  }

  void _updateFromResult(List<ConnectivityResult> result) {
    final first = result.isNotEmpty ? result.first : ConnectivityResult.none;
    final next = switch (first) {
      ConnectivityResult.wifi => NetworkStatus.wifi,
      ConnectivityResult.mobile => NetworkStatus.mobile,
      ConnectivityResult.ethernet => NetworkStatus.other,
      ConnectivityResult.vpn => NetworkStatus.other,
      ConnectivityResult.other => NetworkStatus.other,
      _ => NetworkStatus.none,
    };
    if (next != _status) {
      _status = next;
      notifyListeners();
    }
  }

  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
