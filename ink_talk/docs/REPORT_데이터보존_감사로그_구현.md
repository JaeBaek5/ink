# 데이터 보존·감사 로그 구현 보고서

**대상**: INK Talk  
**내용**: 소프트 삭제, 감사 로그(append-only), Firestore 규칙, PITR·백업 운영 가이드

---

## 1. 설계 문서

다음 설계는 **`docs/DATA_RETENTION_AND_RECOVERY.md`**에 상세 정리되어 있습니다.

| 항목 | 요약 |
|------|------|
| **소프트 삭제** | `deleted` / `deletedAt` / `deletedBy`(또는 컬렉션별 `hidden`, `leftAt`) 스키마 및 컬렉션별 적용 방식 |
| **감사 로그** | `audit_logs` 컬렉션 용도, 필드 정의, 이벤트 타입, BigQuery 연동 참고 |
| **PITR + 예약 백업** | Firestore PITR 활성화, 예약 백업(내보내기) 체크리스트 |

---

## 2. 소프트 삭제 구현 현황

데이터는 삭제하지 않고 플래그·메타데이터만 기록하며, 목록/조회에서만 제외합니다.

| 대상 | 추가/적용 내용 |
|------|----------------|
| **friends** | `hiddenBy` 추가. 친구 삭제 시 “누가 숨겼는지” 저장 |
| **rooms** | 나가기 시 `members.{uid}.leftAt` 설정. 방 문서는 삭제하지 않음 |
| **strokes** | 삭제 시 `deletedAt`, `deletedBy` 저장 (기존 `isDeleted` 유지) |
| **texts** | 삭제 시 `deletedAt`, `deletedBy` 저장 |
| **shapes** | 삭제 시 `deletedAt`, `deletedBy` 저장 |
| **media** | 삭제 시 `deletedAt`, `deletedBy` 저장 |

- 캔버스에서 삭제 시 `canvas_controller`가 `userId`를 넘기고, 각 서비스에서 `deletedBy`에 기록합니다.
- 운영자는 Firestore에서 해당 필드를 초기화하여 복구할 수 있습니다.

---

## 3. 감사 로그 (append-only) 구현

### 3.1 서비스

- **파일**: `lib/services/audit_log_service.dart`
- **역할**: `audit_logs` 컬렉션에 **create만** 수행. 수정/삭제는 하지 않음.
- **실패 처리**: 로그 기록 실패 시에도 메인 플로우(친구/방/캔버스 동작)는 유지됩니다.

### 3.2 이벤트 타입

| 분류 | eventType |
|------|-----------|
| 친구 | `friend_request_sent`, `friend_request_accepted`, `friend_request_rejected`, `friend_hidden` |
| 방 | `room_created`, `room_leave` |
| 스트로크 | `stroke_created`, `stroke_deleted` |
| 텍스트 | `text_created`, `text_deleted` |
| 도형 | `shape_created`, `shape_deleted` |
| 미디어 | `media_created`, `media_deleted` |

### 3.3 연동 위치

| 구분 | 연동 시점 |
|------|------------|
| 친구 | 요청 발송·수락·거절·숨김 시 (`friend_service.dart`) |
| 방 | 방 생성·나가기 시 (`room_service.dart`) |
| 스트로크/텍스트/도형/미디어 | 생성·삭제 시 (`stroke_service`, `text_service`, `shape_service`, `media_service`) |

---

## 4. Firestore 규칙

- **`audit_logs`**
  - `read`, `create`: 인증된 사용자 허용
  - `update`, `delete`: **false** → append-only 유지
- **그 외 컬렉션**: 기존과 동일하게 인증된 사용자 read/write 허용

**배포**: `firebase deploy --only firestore`

---

## 5. 운영 참고 (PITR + 백업)

| 항목 | 방법 |
|------|------|
| **PITR** | Firestore 콘솔 → 프로젝트 설정 → PITR 활성화(지원 리전) |
| **예약 백업** | Cloud Scheduler + Firestore export로 GCS에 주기 내보내기 → 필요 시 해당 스냅샷으로 복구 |

자세한 체크리스트와 복구 관점은 **`docs/DATA_RETENTION_AND_RECOVERY.md`**를 참고하면 됩니다.

---

## 6. 관련 문서

| 문서 | 설명 |
|------|------|
| `docs/DATA_RETENTION_AND_RECOVERY.md` | 데이터 보존·복구 설계(소프트 삭제, 감사 로그, PITR·백업) |
| `docs/MONITORING_REPORT.md` | 모니터링 전략, 지표, 알림, 대시보드 권장 사항 |
| `firestore.rules` | Firestore 보안 규칙( audit_logs append-only 포함) |

---

**보고서 작성일**: 2026년 기준 반영  
**구현 범위**: 소프트 삭제 확장, audit_log_service 도입, Firestore 규칙 반영, 설계·운영 문서 정리
