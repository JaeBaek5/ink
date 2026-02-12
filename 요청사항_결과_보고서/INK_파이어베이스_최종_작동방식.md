# INK 앱 Firebase 최종 작동 방식 정리

실시간 비용 절감을 위해 **Firestore**와 **Realtime Database(RTDB)** 역할을 나눈 뒤의 최종 구조입니다.

---

## 1. 역할 분리 요약

| 구분 | Firestore | Realtime Database (RTDB) |
|------|-----------|---------------------------|
| **역할** | 영구 저장·조회, 방/사용자/친구/태그 메타 | 캔버스 실시간 이벤트만 |
| **캔버스 데이터** | 진입 시 **1회 get()** 로 초기 로드, 저장 시 **add/update** | **listen** 으로 stroke/text/shape/media **델타만** 수신 |
| **과금 축** | Read/Write **연산 수** + 저장량 | **저장(GB) + 다운로드(GB)** |
| **효과** | strokes/texts/shapes/media **snapshots() 제거** → Read 급감 | 실시간은 RTDB로 → Firestore 리스너 수 0 |

---

## 2. Firestore — 무엇에 쓰나

### 2.1 계속 실시간 스트림 쓰는 것 (변경 없음)

- **rooms**: `getRoomsStream`, `getRoomStream` — 방 목록·방 단일
- **users**: 단건 get 위주 (스트림 없음)
- **friends**: `getFriendsStream`, `getPendingRequestsStream` 등
- **tags**: `getMyTagsStream`, `getRoomTagsStream`

### 2.2 캔버스 데이터 — 스트림 제거, 1회 로드만

| 컬렉션 | 이전 | 현재 |
|--------|------|------|
| strokes | `getStrokesStream` snapshots() | **getStrokes(roomId)** 1회 get() |
| texts | `getTextsStream` snapshots() | **getTexts(roomId)** 1회 get() |
| shapes | `getShapesStream` snapshots() | **getShapes(roomId)** 1회 get() |
| media | `getMediaStream` snapshots() | **getMedia(roomId)** 1회 get() |

- 진입 시 위 4개를 **한 번만** 불러서 초기 상태로 쓰고, 이후 실시간 갱신은 **RTDB만** 사용합니다.
- `getXxxStream()` 메서드는 코드에 남아 있으나 **캔버스에서는 사용하지 않습니다** (레거시/대안용).

### 2.3 Firestore 쓰기 (저장)

- **strokes/texts/shapes/media**: 추가·수정·삭제 시 기존처럼 **add / update** (영구 저장).
- **rooms**: `updateLastEvent` — **3초 디바운스** (아래 “비용 절감” 참고).
- **audit_logs**: stroke 건별 로그 **기본 비활성** (`AuditLogService.enableStrokeAudit = false`).

---

## 3. Realtime Database (RTDB) — 실시간만

### 3.1 경로

```
/rt/rooms/{roomId}/members/{uid}   ← 멤버십 캐시 (Rules 검사용). 진입 시 true, 퇴장 시 제거.
/rt/rooms/{roomId}/events/{pushId} ← 이벤트 배치 (ts, batch)
```

- **members**: events 읽기/쓰기 허용 조건. 클라이언트는 방 진입 시 본인 uid만 `true` 설정, 퇴장 시 제거. (권장: 운영 환경에서는 Cloud Functions로 Firestore `rooms.memberIds` 와 동기화하면 더 안전.)
- **events**: 각 이벤트 배치는 **push()** 자식 아래에 저장.

### 3.2 이벤트 형식 (배치)

한 번에 **배치 1건**으로 기록. **firestoreDocId(id)·opSeq·ts** 포함으로 순서/누락 대응.

```json
{
  "ts": "<ServerValue.timestamp>",
  "batch": [
    { "type": "stroke_delta", "op": "add", "payload": { "id": "...", ... }, "opSeq": 0 },
    { "type": "text_delta", "op": "remove", "payload": { "id": "..." }, "opSeq": 1 }
  ]
}
```

- **type**: `stroke_delta`, `text_delta`, `shape_delta`, `media_delta`
- **op**: `add`, `update`, `remove`
- **payload**: 모델 직렬화. **id** = Firestore 문서 ID (firestoreDocId). createdAt 등은 millis.
- **opSeq**: 배치 내 순서. 클라이언트는 opSeq 기준 정렬 후 적용 → add → update 순서 보장, 유령 update 방지.

### 3.3 전송 방식 (앱 → RTDB)

- **RtdbRoomService.pushEvent(roomId, type, op, payload)** 로 버퍼에만 넣고,
- **300ms 디바운스** 후 해당 방의 버퍼를 **한 배치**로 push (각 항목에 opSeq 부여).
- 배치당 1회 쓰기로 RTDB 쓰기 횟수 절감.

### 3.4 수신 방식 (RTDB → 앱) — 다운로드 폭탄 방지

- **쿼리**: `orderByChild('ts').startAt(sinceMs).limitToLast(200)` 으로 구독.
  - **limitToLast(200)**: 최근 200개 배치만 수신 → 과거 이벤트 대량 다운로드 방지.
  - **startAt(sinceMs)**: 진입 시점(`_rtdbJoinTime`) 이후 이벤트만.
- 배치 수신 시 `ts >= sinceMs` 한 번 더 필터, 배치 내 이벤트는 **opSeq** 기준 정렬 후 **add → update → remove** 순으로 적용.
- **이벤트 정리(권장)**: events는 “짧게 쓰고 버리는 버스”. **Cloud Functions** 로 일정 시간(예: 1시간) 지난 이벤트 삭제(GC) 하면 RTDB 저장·다운로드 비용이 안정화됩니다. (또는 링 버퍼 구조로 전환 가능.)

### 3.5 보안 규칙 (배포용)

- 루트: `.read` / `.write` = false.
- **rt/rooms/$roomId/members**
  - `.read`: `auth != null`
  - **$uid**: `.write`: `auth.uid == $uid` (본인만 설정/삭제)
- **rt/rooms/$roomId/events**
  - `.read` / `.write`: `auth != null` **그리고**  
    `root.child('rt').child('rooms').child($roomId).child('members').child(auth.uid).val() == true`  
  → **방 멤버십 캐시가 있는 사용자만** 이벤트 읽기/쓰기 가능. (`auth != null` 만으로는 아무 roomId나 접근 가능해져 보안상 부족하므로 위 조건 필수.)

---

## 4. 캔버스 진입 시 흐름 (방 들어갈 때)

1. **구독 정리**  
   기존 Firestore 스트림·RTDB 스트림 구독 모두 cancel.
2. **Firestore 1회 로드**  
   `getStrokes(roomId)`, `getTexts(roomId)`, `getShapes(roomId)`, `getMedia(roomId)` 호출 →  
   `_serverStrokes`, `_serverTexts`, `_serverShapes`, `_serverMedia`, `_mediaCropRects` 등 초기화.
3. **RTDB 멤버십 설정**  
   `setRoomMember(roomId, userId, true)` → `/rt/rooms/{roomId}/members/{uid} = true`.  
   (Rules에서 events 접근 허용용. 방 목록은 이미 Firestore에서 멤버만 보이므로, 진입 시점에만 설정.)
4. **RTDB 구독**  
   `_rtdbJoinTime = now - 10초` 설정 후  
   `roomEventsStream(roomId, sinceMs: _rtdbJoinTime)` → `orderByChild('ts').startAt(sinceMs).limitToLast(200).onChildAdded` 로 실시간 이벤트만 수신.
5. **퇴장 시**  
   `dispose()` 에서 `setRoomMember(roomId, userId, false)` 호출로 members에서 본인 제거.
6. **이후**  
   모든 캔버스 실시간 갱신은 RTDB 이벤트로만 처리 (Firestore strokes/texts/shapes/media 리스너 없음).

---

## 5. 캔버스 저장/삭제 시 흐름 (쓰기)

- **영구 저장**: 기존처럼 **Firestore** 에만 **add** 또는 **update** (strokes/texts/shapes/media/rooms 등).
- **실시간 알림**: 같은 동작에 대해 **RTDB** 로 **pushEvent** 한 번 호출 (위 300ms 버퍼링 적용).

| 동작 | Firestore | RTDB |
|------|-----------|------|
| 스트로크 1획 저장 | saveStroke (add) | pushEvent('stroke_delta', 'add', payload) |
| 스트로크 확정 | confirmStroke (update) | pushEvent('stroke_delta', 'update', { id, isConfirmed }) |
| 스트로크 삭제 | deleteStroke / deleteStrokes | pushEvent('stroke_delta', 'remove', { id }) |
| 텍스트 추가 | saveText (add) | pushEvent('text_delta', 'add', payload) |
| 텍스트 삭제 | deleteText (update) | pushEvent('text_delta', 'remove', { id }) |
| 도형 추가 | saveShape (add) | pushEvent('shape_delta', 'add', payload) |
| 도형 삭제 | deleteShape (update) | pushEvent('shape_delta', 'remove', { id }) |
| 미디어 추가 | saveMedia (add) | pushEvent('media_delta', 'add', payload) |
| 미디어 삭제 | deleteMedia (update) | pushEvent('media_delta', 'remove', { id }) |

- **rooms** 의 “마지막 이벤트” 갱신은 **updateLastEvent** 로 하며, 아래 비용 절감 때문에 **3초 디바운스** 적용.

---

## 6. 비용 절감 조치 요약

| 조치 | 내용 | 효과 |
|------|------|------|
| **캔버스 실시간을 RTDB로** | strokes/texts/shapes/media **snapshots() 제거**, 진입 시 get() 1회 + RTDB listen | 방 인원 수만큼 Firestore Read가 나가던 구조 제거 |
| **updateLastEvent 디바운스** | 3초에 1회만 `rooms` 문서 update | 스트로크/텍스트/미디어 저장마다 room write 하던 것 대폭 감소 |
| **audit_log 스트로크 건별 비활성** | `AuditLogService.enableStrokeAudit = false` (기본) | stroke 생성/삭제 시 audit_log add 제거 → write 감소 |
| **미디어 이동·리사이즈** | 드래그/리사이즈 **중**에는 로컬만, **끝날 때** Firestore 1회 update | moveMedia/resizeMedia 호출마다 update 하던 것 제거 |
| **RTDB 배치** | 300ms 단위로 이벤트 묶어서 1건 push | RTDB 쓰기 횟수 감소 |

---

## 7. 보안·동기화·비용 안정화 체크리스트

| 항목 | 적용 여부 | 비고 |
|------|-----------|------|
| **RTDB Rules** | ✅ | events는 **members/{auth.uid} == true** 일 때만 read/write. `auth != null` 만 사용 금지. |
| **RTDB 구독** | ✅ | **limitToLast(200) + orderByChild('ts').startAt(joinTime)** 적용 → 과거 이벤트 대량 다운로드 방지. |
| **RTDB 이벤트 정리** | 권장 | TTL/GC용 **Cloud Functions** 로 오래된 events 삭제, 또는 링 버퍼 구조 전환. |
| **이벤트 payload** | ✅ | **id**(firestoreDocId), **opSeq**(배치 내 순서), **ts**(배치 수준) 포함. 클라에서 opSeq 정렬 후 적용. |
| **순서/유령 update** | ✅ | add → update 순서 보장(opSeq), update 시 기존 항목 없으면 무시. |
| **Firestore 저장** | ✅ | **획 종료/입력 종료/드래그 종료**에만 write. 진행 중 연발 write 금지(이미 반영). |
| **updateLastEvent 디바운스** | ✅ | 3초 유지. |
| **audit_logs stroke 건별** | ✅ | OFF 유지. |

## 8. 정리

- **Firestore**: 영구 데이터 + 방/유저/친구/태그 메타. 캔버스는 **초기 1회 로드**와 **저장용 add/update** 만 사용.
- **RTDB**: 캔버스 **실시간** 전용. `/rt/rooms/{roomId}/members` 로 멤버십 제한, `/events` 에 배치로 이벤트 기록·구독. **limitToLast + startAt** 으로 다운로드 제한, **opSeq** 로 순서 보장.
- 위 비용 절감 및 보안·동기화 조치가 반영된 구조가 최종 작동 방식입니다.

*작성 기준: ink_talk/lib 서비스·캔버스 컨트롤러 및 database.rules.json.*
