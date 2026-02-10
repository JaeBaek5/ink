# 보고서: 에뮬레이터 vs 실제 디바이스 Firestore 오류 차이

**작성일**: 2025-01-29  
**대상 앱**: INK Talk  
**요약**: 동일 빌드에서 에뮬레이터에서는 Firestore 관련 오류가 발생하고, 실제 디바이스에서는 동일 오류가 발생하지 않는 현상을 정리한 보고서입니다.

---

## 1. 관찰 내용

| 환경           | Firestore 오류 발생 여부 | 비고 |
|----------------|---------------------------|------|
| **에뮬레이터** | 발생함                     | `cloud_firestore/unavailable` 등 일시 오류 확인 |
| **실제 디바이스** | 발생하지 않음             | 동일 기능 정상 동작 |

- **발생했던 오류 예시**  
  `FirebaseException ([cloud_firestore/unavailable] The service is currently unavailable. This is a most likely a transient condition and may be corrected by retrying with a backoff.)`

- **조건**  
  - 동일한 소스/빌드  
  - 동일한 Firebase 프로젝트(프로덕션 Firestore) 사용  
  - 에뮬레이터용/실기기용으로 Firestore 엔드포인트를 다르게 쓰지 않음(에뮬레이터 미사용)

---

## 2. 원인 분석

에뮬레이터에서만 오류가 나고 실제 디바이스에서는 나지 않는 이유를 환경 차이로 정리했습니다.

### 2.1 네트워크 환경

- **에뮬레이터**  
  - 호스트(개발 PC)의 네트워크를 가상 네트워크 계층을 통해 사용  
  - 회사/학교 Wi‑Fi, VPN, 방화벽 등으로 Google/Firebase 트래픽이 제한·지연될 수 있음  
  - 그 결과 `unavailable`, `deadline-exceeded` 등 일시 오류가 더 자주 발생할 수 있음  

- **실제 디바이스**  
  - 다른 Wi‑Fi 또는 이동통신(LTE/5G) 사용 가능  
  - 위와 같은 제한이 없거나 적어, Firestore 연결이 상대적으로 안정적  

### 2.2 Google Play Services / 플랫폼

- **에뮬레이터**  
  - Google Play/Google APIs 미포함 이미지 사용 시 Firebase 연동이 불안정할 수 있음  
  - 가상 디바이스 특성상 네트워크·타이밍이 실제와 다르게 동작할 수 있음  

- **실제 디바이스**  
  - Google Play Services 정상 탑재, 실제 네트워크 스택 사용으로 연결이 안정적  

### 2.3 성능·타이밍

- 에뮬레이터는 CPU/메모리 제한으로 인해 응답이 느려질 수 있고, 이로 인해 Firestore 요청이 타임아웃되거나 일시 오류로 처리될 가능성이 높음  
- 실제 디바이스는 상대적으로 일정한 성능으로 요청이 완료되어 동일 코드에서도 오류가 덜 발생함  

---

## 3. 앱 측 대응(이미 적용된 사항)

Firestore 일시 오류에 대한 재시도·재연결 로직이 적용되어 있습니다.

- **일회성 호출**  
  `retryFirestore()`: 최대 3회, 지수 백오프(1초 → 2초 → 4초, 최대 15초)  
  - `room_service`, `friend_service` 등 주요 Firestore 읽기/쓰기에 적용  

- **실시간 스트림**  
  `streamWithRetry()`: 스트림 오류 시 재연결, 최대 5회 재시도  
  - 채팅방 목록, 친구 목록, 받은 요청, 차단 목록, 채팅방 단일 스트림 등에 적용  

위 조치로 에뮬레이터에서도 일시 오류가 발생할 경우 자동 재시도·재연결이 이루어지며, 실제 디바이스에서는 원래부터 오류가 적어 동일 로직으로 안정성이 유지됩니다.

---

## 4. 결론 및 권장 사항

- **결론**  
  - 에뮬레이터에서만 Firestore 오류가 발생하고 실제 디바이스에서는 발생하지 않는 현상은 **실행 환경 차이(네트워크, Play Services, 성능)** 로 설명 가능합니다.  
  - 동일 빌드·동일 Firebase 설정임에도 환경에 따라 일시 오류 발생 빈도가 달라지는 것으로 보입니다.  

- **권장 사항**  
  1. **실제 디바이스에서의 동작을 기준**으로 판단하는 것을 권장합니다.  
  2. 에뮬레이터 테스트 시  
     - Google Play 포함 에뮬레이터 이미지 사용  
     - VPN/방화벽 제한이 있는 네트워크 회피 또는 다른 네트워크로 교차 확인  
  3. 중요한 기능(채팅, 친구, 방 생성 등)은 **실기기에서 한 번 더 검증**하는 것을 권장합니다.  

---

## 5. 참고

- Firestore 일시 오류 재시도: `lib/core/utils/firestore_retry.dart`  
- 적용 서비스: `lib/services/room_service.dart`, `lib/services/friend_service.dart`  
- 적용 프로바이더: `lib/providers/room_provider.dart`, `lib/providers/friend_provider.dart`  
