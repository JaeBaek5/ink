import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// RTDB 실시간 이벤트 1건 (batch 내 요소). opSeq로 add → update 순서 보장.
class RoomDeltaEvent {
  final String type;
  final String op;
  final Map<String, dynamic> payload;
  final int opSeq;

  RoomDeltaEvent({required this.type, required this.op, required this.payload, this.opSeq = 0});
}

/// RTDB 배치 1건 (ts + batch)
class RoomEventBatch {
  final int ts; // server timestamp millis
  final List<RoomDeltaEvent> events;

  RoomEventBatch({required this.ts, required this.events});
}

/// 실시간은 RTDB, 영구 저장은 Firestore. /rt/rooms/{roomId}/events 에 배치 전송.
class RtdbRoomService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  static const Duration bufferInterval = Duration(milliseconds: 300);

  final Map<String, List<Map<String, dynamic>>> _buffer = {};
  final Map<String, Timer?> _timers = {};

  DatabaseReference _eventsRef(String roomId) =>
      _db.child('rt').child('rooms').child(roomId).child('events');

  DatabaseReference _membersRef(String roomId) =>
      _db.child('rt').child('rooms').child(roomId).child('members');

  /// 방 멤버십 캐시 설정 (Rules: events 읽기/쓰기는 members/{uid}==true 일 때만)
  /// 진입 시 true, 퇴장 시 false. Firestore에서 멤버 확인 후 호출.
  /// 권한 거부 시 인증 지연일 수 있어 1회 재시도.
  Future<void> setRoomMember(String roomId, String uid, bool isMember) async {
    Future<void> run() async {
      if (isMember) {
        await _membersRef(roomId).child(uid).set(true);
      } else {
        await _membersRef(roomId).child(uid).remove();
      }
    }
    try {
      await run();
    } catch (e) {
      final isPermissionDenied = e.toString().contains('Permission denied') ||
          e.toString().contains('permission_denied');
      if (isPermissionDenied) {
        await Future.delayed(const Duration(milliseconds: 800));
        try {
          await run();
        } catch (e2) {
          if (kDebugMode) debugPrint('RTDB setRoomMember 재시도 후 실패: $e2');
        }
      } else if (kDebugMode) {
        debugPrint('RTDB setRoomMember 실패: $e');
      }
    }
  }

  /// 배치에 이벤트 추가 후 300ms 디바운스로 전송. payload에 firestoreDocId(id), opSeq 포함.
  void pushEvent(String roomId, String type, String op, Map<String, dynamic> payload) {
    _buffer.putIfAbsent(roomId, () => []);
    _buffer[roomId]!.add({
      'type': type,
      'op': op,
      'payload': payload,
    });
    _timers[roomId]?.cancel();
    _timers[roomId] = Timer(bufferInterval, () => _flush(roomId));
  }

  Future<void> _flush(String roomId) async {
    _timers.remove(roomId);
    final list = _buffer.remove(roomId);
    if (list == null || list.isEmpty) return;
    try {
      final batch = <Map<String, dynamic>>[];
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        batch.add({
          'type': e['type'],
          'op': e['op'],
          'payload': e['payload'],
          'opSeq': i,
        });
      }
      await _eventsRef(roomId).push().set({
        'ts': ServerValue.timestamp,
        'batch': batch,
      });
    } catch (e) {
      debugPrint('RTDB flush 실패: $e');
    }
  }

  /// 최근 N건만 구독 (다운로드 폭탄 방지). orderByChild('ts').startAt(sinceMs).limitToLast(N)
  static const int eventsLimitLast = 200;

  /// 방 이벤트 스트림. limitToLast(N) + startAt(sinceMs) 로 과거 대량 다운로드 방지.
  Stream<RoomEventBatch> roomEventsStream(String roomId, {required int sinceMs}) {
    final ref = _eventsRef(roomId);
    final query = ref
        .orderByChild('ts')
        .startAt(sinceMs)
        .limitToLast(eventsLimitLast);
    return query.onChildAdded.map<RoomEventBatch?>( (DatabaseEvent event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return null;
      final map = snapshot.value as Map<dynamic, dynamic>?;
      if (map == null) return null;
      final ts = map['ts'];
      final batchRaw = map['batch'];
      if (ts == null || batchRaw == null) return null;
      final tsMs = ts is int ? ts : (ts is num ? ts.toInt() : 0);
      if (tsMs < sinceMs) return null;
      final batchList = batchRaw as List<dynamic>? ?? [];
      final events = <RoomDeltaEvent>[];
      for (final item in batchList) {
        final m = item as Map<dynamic, dynamic>?;
        if (m == null) continue;
        final type = m['type']?.toString() ?? '';
        final op = m['op']?.toString() ?? 'add';
        final payload = m['payload'];
        final payloadMap = payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{};
        final opSeq = m['opSeq'] is int ? m['opSeq'] as int : 0;
        events.add(RoomDeltaEvent(type: type, op: op, payload: payloadMap, opSeq: opSeq));
      }
      events.sort((a, b) => a.opSeq.compareTo(b.opSeq));
      if (events.isEmpty) return null;
      return RoomEventBatch(ts: tsMs, events: events);
    }).where((batch) => batch != null).cast<RoomEventBatch>();
  }

  /// 구독 해제 시 사용할 수 있도록 ref 반환 (cancel 시 ref.off() 필요 시)
  Query roomEventsQuery(String roomId) => _eventsRef(roomId);

  void dispose() {
    for (final t in _timers.values) {
      t?.cancel();
    }
    _timers.clear();
    _buffer.clear();
  }
}
