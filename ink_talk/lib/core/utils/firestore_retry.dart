import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

/// Firestore 일시 오류 시 재시도에 사용할 코드
const _retryableCodes = {
  'unavailable',
  'cloud_firestore/unavailable',
  'resource-exhausted',
  'internal',
  'deadline-exceeded',
};

/// 일시적인 Firestore 오류인지 여부
bool isRetryableFirebaseException(Object e) {
  if (e is FirebaseException) {
    final code = e.code;
    if (_retryableCodes.contains(code)) return true;
    if (code.endsWith('/unavailable') || code == 'unavailable') return true;
    if (e.message?.contains('unavailable') == true) return true;
  }
  // 플러그인/버전에 따라 메시지로만 표시되는 경우
  final msg = e.toString().toLowerCase();
  if (msg.contains('unavailable') && msg.contains('firestore')) return true;
  return false;
}

/// 문서/컬렉션이 삭제된 경우(not-found)인지 여부
bool isNotFoundFirebaseException(Object e) {
  if (e is FirebaseException) {
    return e.code == 'not-found';
  }
  return false;
}

/// 권한 없음(permission-denied). 로그아웃 등으로 인증이 없을 때 발생. 재시도 불가.
bool isPermissionDeniedFirebaseException(Object e) {
  if (e is FirebaseException) {
    return e.code == 'permission-denied' || e.code == 'cloud_firestore/permission-denied';
  }
  final msg = e.toString().toLowerCase();
  return msg.contains('permission') && msg.contains('denied');
}

/// [fn]을 실행하고, 일시 오류 시 지수 백오프로 재시도합니다.
/// [maxAttempts]: 최대 시도 횟수 (기본 8)
/// [initialDelay]: 첫 재시도 대기 시간 (기본 3초)
Future<T> retryFirestore<T>(
  Future<T> Function() fn, {
  int maxAttempts = 8,
  Duration initialDelay = const Duration(seconds: 3),
}) async {
  var attempt = 0;
  var delay = initialDelay;

  while (true) {
    attempt++;
    try {
      return await fn();
    } catch (e) {
      if (attempt >= maxAttempts || !isRetryableFirebaseException(e)) {
        rethrow;
      }
      await Future.delayed(delay);
      delay = Duration(
        milliseconds: (delay.inMilliseconds * 2).clamp(0, 15000),
      );
    }
  }
}

/// Firestore 스트림에서 일시 오류 시 재연결 후 계속 구독합니다.
/// [createStream]: 재연결 시 호출할 스트림 생성 함수
/// [maxAttempts]: 오류당 최대 재시도 횟수 (기본 15)
Stream<T> streamWithRetry<T>(Stream<T> Function() createStream, {
  int maxAttempts = 15,
  Duration initialDelay = const Duration(seconds: 3),
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  var attempt = 0;
  var delay = initialDelay;

  void subscribe() {
    sub = createStream().listen(
      (data) {
        attempt = 0; // 성공 시 재시도 카운트·대기시간 초기화
        delay = initialDelay;
        controller.add(data);
      },
      onError: (e, st) {
        // 로그아웃 등으로 권한 없음 시: 재시도·에러 전파 없이 스트림만 종료 (예외 대화상자 방지)
        if (isPermissionDeniedFirebaseException(e)) {
          sub?.cancel();
          if (!controller.isClosed) controller.close();
          return;
        }
        attempt++;
        if (attempt >= maxAttempts || !isRetryableFirebaseException(e)) {
          controller.addError(e, st);
          return;
        }
        sub?.cancel();
        final wait = delay;
        delay = Duration(
          milliseconds: (delay.inMilliseconds * 2).clamp(0, 20000),
        );
        Future.delayed(wait).then((_) {
          if (!controller.isClosed) subscribe();
        });
      },
      onDone: () => controller.close(),
      cancelOnError: false,
    );
  }

  controller = StreamController<T>(
    onListen: subscribe,
    onCancel: () => sub?.cancel(),
  );
  return controller.stream;
}
