import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

/// Firestore 일시 오류 시 재시도에 사용할 코드
const _retryableCodes = {
  'unavailable',
  'resource-exhausted',
  'internal',
  'deadline-exceeded',
};

/// 일시적인 Firestore 오류인지 여부
bool isRetryableFirebaseException(Object e) {
  if (e is FirebaseException) {
    return _retryableCodes.contains(e.code);
  }
  return false;
}

/// 문서/컬렉션이 삭제된 경우(not-found)인지 여부
bool isNotFoundFirebaseException(Object e) {
  if (e is FirebaseException) {
    return e.code == 'not-found';
  }
  return false;
}

/// [fn]을 실행하고, 일시 오류 시 지수 백오프로 재시도합니다.
/// [maxAttempts]: 최대 시도 횟수 (기본 3)
/// [initialDelay]: 첫 재시도 대기 시간 (기본 1초)
Future<T> retryFirestore<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
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
/// [maxAttempts]: 오류당 최대 재시도 횟수 (기본 5)
Stream<T> streamWithRetry<T>(Stream<T> Function() createStream, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(seconds: 1),
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  var attempt = 0;
  var delay = initialDelay;

  void subscribe() {
    sub = createStream().listen(
      (data) {
        attempt = 0; // 성공 시 재시도 카운트 초기화
        controller.add(data);
      },
      onError: (e, st) {
        attempt++;
        if (attempt >= maxAttempts || !isRetryableFirebaseException(e)) {
          controller.addError(e, st);
          return;
        }
        sub?.cancel();
        Future.delayed(delay).then((_) {
          delay = Duration(
            milliseconds: (delay.inMilliseconds * 2).clamp(0, 15000),
          );
          subscribe();
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
