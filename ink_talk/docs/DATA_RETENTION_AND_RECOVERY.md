# 데이터 보존·복구 설계

실수/악의적 삭제에 대비하고, 운영자 확인·복구·감사가 가능하도록 아래 세 가지를 함께 둡니다.

---

## 1. 소프트 삭제 (Soft Delete)

방/메시지/친구 관계를 **바로 삭제하지 않고** 플래그와 메타데이터만 기록합니다.

### 공통 스키마 (권장)

| 필드 | 타입 | 설명 |
|------|------|------|
| `deleted` | boolean | true면 삭제(숨김) 상태. 목록/조회에서 제외 |
| `deletedAt` | timestamp | 삭제(숨김) 처리 시각 |
| `deletedBy` | string | 삭제(숨김)를 수행한 사용자 uid |

### 컬렉션별 적용

| 컬렉션 | 현재 필드 | 비고 |
|--------|-----------|------|
| **friends** | `hidden`, `hiddenAt`, `hiddenBy` | 친구 삭제 = 양쪽 문서에 hidden 처리. 기록은 유지 → 관리자 확인 가능. (hiddenBy = 삭제 수행자 uid) |
| **rooms** | 멤버별 `leftAt` | 나가기 = `members.{uid}.leftAt` 설정. 방 문서는 삭제하지 않음 |
| **rooms/{id}/strokes** | `isDeleted`, `deletedAt`, `deletedBy` | 스트로크 삭제 시 업데이트만 |
| **rooms/{id}/texts** | `isDeleted`, `deletedAt`, `deletedBy` | 텍스트 삭제 시 업데이트만 |
| **rooms/{id}/shapes** | `isDeleted`, `deletedAt`, `deletedBy` | 도형 삭제 시 업데이트만 |
| **rooms/{id}/media** | `isDeleted`, `deletedAt`, `deletedBy` | 미디어 삭제 시 업데이트만 |

- **조회**: 모든 목록/스트림 쿼리에서 `deleted != true`(또는 `isDeleted == false`) 조건으로 제외.
- **복구**: 운영자가 Firestore에서 `deleted`/`isDeleted`를 false로, `deletedAt`/`deletedBy`를 제거하면 앱에서 다시 노출.

---

## 2. 변경 이력 / 감사 로그 (Append-Only)

메시지·스트로크·방·친구 등 **생성·수정·삭제 이벤트**를 별도 컬렉션에 **추가만** 하여 저장합니다.

### 컬렉션: `audit_logs`

| 필드 | 타입 | 설명 |
|------|------|------|
| `eventType` | string | 예: `stroke_created`, `stroke_deleted`, `friend_request_sent`, `room_leave` |
| `collection` | string | 대상 컬렉션 (예: `strokes`, `friends`, `rooms`) |
| `documentId` | string | 대상 문서 id |
| `roomId` | string? | 채팅방 id (서브컬렉션인 경우) |
| `userId` | string | 이벤트를 수행한 사용자(actor) uid |
| `timestamp` | timestamp | 서버 시각 권장 (`FieldValue.serverTimestamp()`) |
| `payload` | map | 이벤트별 메타 (before/after, id 목록 등). 선택 |

### 이벤트 타입 예시

- **친구**: `friend_request_sent`, `friend_request_accepted`, `friend_request_rejected`, `friend_hidden`
- **방**: `room_created`, `room_leave`
- **스트로크/텍스트/도형/미디어**: `stroke_created`, `stroke_deleted`, `text_created`, `text_deleted`, `shape_created`, `shape_deleted`, `media_created`, `media_deleted`

### 보안 규칙

- **append-only**: `audit_logs`는 **create만 허용**, update/delete는 거부 (관리자만 예외 처리 가능).
- 클라이언트는 기존 로그 수정/삭제 불가 → 감사 신뢰성 유지.

### BigQuery 연동 (선택)

- Firestore `audit_logs`를 BigQuery로 스트리밍 적재하면 대용량 조회·분석에 유리합니다.
- Firebase 콘솔에서 Firestore → BigQuery 내보내기 설정 가능.

---

## 3. PITR + 예약 백업

Firestore 복구 기능만 믿지 않고, **운영 환경에서는 아래 둘 중 하나 이상**을 권장합니다.

### Point-in-Time Recovery (PITR)

- **Firestore 네이티브 PITR** (지원 리전에서 사용 가능).
- 콘솔: Firestore → 설정 → PITR 활성화.
- 특정 시점으로 DB 상태 복구 가능.

### 예약 백업 (Scheduled Backups)

- **Firestore 내보내기**를 Cloud Scheduler + Cloud Functions(또는 GCS 내보내기)로 주기 실행.
- 내보내기 대상: GCS 버킷 (예: 일 1회 전체 export).
- 필요 시 해당 버킷 스냅샷에서 복구.

운영 체크리스트:

- [ ] PITR 활성화 또는 예약 백업 중 하나 이상 설정
- [ ] 백업/내보내기 결과 모니터링 및 알림
- [ ] 복구 절차 문서화 및 정기 점검

---

## 요약

| 항목 | 목적 |
|------|------|
| **소프트 삭제** | 삭제된 데이터를 DB에 남기고, deleted/deletedAt/deletedBy로 관리 → 운영자 확인·복구 |
| **감사 로그** | append-only `audit_logs`로 생성·수정·삭제 이력 보존 → 감사·분석·BigQuery 활용 |
| **PITR + 백업** | 실수/악의적 삭제에 대비한 시점 복구 및 정기 백업 |
