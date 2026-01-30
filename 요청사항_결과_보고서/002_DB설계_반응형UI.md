# [002] Phase 1.3 & 2 데이터베이스 설계 및 반응형 UI

## 요청 정보

- **날짜:** 2026-01-29
- **요청 내용:** 개발 순서 Phase 1.3, 2.1, 2.2 진행
  - 1.3 데이터베이스 설계
  - 2.1 반응형 레이아웃 기반
  - 2.2 하단 탭 네비게이션 완성

---

## 진행 내용

### 1.3 데이터베이스 설계

#### 1) 패키지 추가
- `cloud_firestore: ^6.1.2` – Firestore 데이터베이스

#### 2) 데이터 모델 생성

| 모델 | 파일 | 설명 |
|------|------|------|
| **UserModel** | `user_model.dart` | 사용자 정보 (uid, visibleId, displayName, photoUrl, statusMessage) |
| **FriendModel** | `friend_model.dart` | 친구 관계 (userId, friendId, status, nickname) |
| **RoomModel** | `room_model.dart` | 채팅방 (type, name, memberIds, members, lastActivityAt) |
| **MessageModel** | `message_model.dart` | 메시지 (텍스트/첨부: type, content, fileUrl, position) |
| **StrokeModel** | `stroke_model.dart` | 손글씨 스트로크 (points, style, isConfirmed) |
| **TagModel** | `tag_model.dart` | 태그 (taggerId, taggedUserId, targetType, targetId, area) |

#### 3) Firestore 컬렉션 구조

```
firestore/
├── users/{uid}
│   ├── visibleId, email, displayName, photoUrl
│   ├── statusMessage, createdAt, lastActiveAt
│
├── friends/{friendId}
│   ├── userId, friendId, status, nickname
│   ├── createdAt, acceptedAt
│
├── rooms/{roomId}
│   ├── type, name, imageUrl, memberIds
│   ├── members: { [userId]: { role, joinedAt, unreadCount } }
│   ├── createdAt, lastActivityAt, lastEventType
│
├── rooms/{roomId}/messages/{messageId}
│   ├── senderId, type, content, fileUrl
│   ├── positionX, positionY, width, height, opacity
│
├── rooms/{roomId}/strokes/{strokeId}
│   ├── senderId, points[], style{color, width, penType}
│   ├── isConfirmed, createdAt
│
└── tags/{tagId}
    ├── roomId, taggerId, taggedUserId
    ├── targetType, targetId, areaX/Y/Width/Height
```

#### 4) UserService 생성

- 사용자 생성/업데이트 (로그인 시)
- 사용자 조회 (UID, visibleId)
- 프로필 업데이트
- 랜덤 visibleId 생성

---

### 2.1 반응형 레이아웃 기반

#### 1) Responsive 유틸리티

```dart
// 브레이크포인트
phoneMaxWidth: 600
tabletMaxWidth: 1200

// DeviceType
- phone (< 600px)
- tablet (600~1200px)
- desktop (> 1200px)
```

#### 2) ResponsiveLayout 위젯

- 디바이스별 다른 위젯 렌더링
- `phone`, `tablet`, `desktop` 파라미터

#### 3) AdaptiveScaffold 위젯

| 디바이스 | 레이아웃 |
|----------|----------|
| **폰** | 하단 탭 네비게이션 + IndexedStack |
| **패드/데스크톱** | 좌측 NavigationRail + 중앙 콘텐츠 + 우측 상세 |

---

### 2.2 하단 탭 네비게이션 완성

#### 탭 화면 구성

| 순서 | 탭 | 파일 | 주요 기능 |
|------|-----|------|-----------|
| 0 | 친구 | `friends_tab.dart` | 프로필 섹션, 친구 목록 (빈 상태) |
| 1 | 채팅 | `chat_tab.dart` | 채팅 목록 (빈 상태), 새 채팅 시트 |
| 2 | 모아보기 | `tags_tab.dart` | 태그 목록 (빈 상태), 필터 시트 |
| 3 | 설정 | `settings_tab.dart` | 프로필, 알림, 테마, 캔버스, 로그아웃 |

---

## 결과

| 항목 | 상태 |
|------|------|
| Firestore 컬렉션 설계 | ✅ 완료 |
| 데이터 모델 6개 생성 | ✅ 완료 |
| UserService 생성 | ✅ 완료 |
| 디바이스 감지 (폰/패드/PC) | ✅ 완료 |
| 패드 3패널 레이아웃 | ✅ 완료 |
| 친구 탭 | ✅ 완료 |
| 채팅 탭 | ✅ 완료 |
| 모아보기 탭 | ✅ 완료 |
| 설정 탭 | ✅ 완료 |

---

## 변경된 파일

### 신규 생성

**모델:**
- `lib/models/user_model.dart`
- `lib/models/friend_model.dart`
- `lib/models/room_model.dart`
- `lib/models/message_model.dart`
- `lib/models/stroke_model.dart`
- `lib/models/tag_model.dart`

**서비스:**
- `lib/services/user_service.dart`

**유틸리티:**
- `lib/core/utils/responsive.dart`

**위젯:**
- `lib/widgets/layouts/adaptive_scaffold.dart`

**화면:**
- `lib/screens/home/tabs/friends_tab.dart`
- `lib/screens/home/tabs/chat_tab.dart`
- `lib/screens/home/tabs/tags_tab.dart`
- `lib/screens/home/tabs/settings_tab.dart`

### 수정

- `pubspec.yaml` – cloud_firestore 추가
- `lib/screens/home/home_screen.dart` – AdaptiveScaffold 적용

### 문서 업데이트

- `잉크_앱프로젝트_정보/개발_순서.md` – Phase 1.3, 2.1, 2.2, 2.3 체크 완료

---

## 관련 커밋

- **커밋 해시:** `be628a6`
- **커밋 메시지:** Phase 1.3 & 2 완료: DB 설계 및 반응형 UI

---

## 테스트 방법

```bash
cd /Users/ojaebaek/ink/ink_talk
flutter run
```

### 폰 테스트
1. 에뮬레이터 또는 실기기에서 실행
2. 하단 탭 4개 확인 (친구/채팅/모아보기/설정)
3. 각 탭 전환 테스트
4. 채팅 탭에서 + 버튼 → 새 채팅 시트
5. 모아보기 탭에서 필터 버튼 → 필터 시트
6. 설정 탭에서 로그아웃

### 패드/데스크톱 테스트
1. 웹 또는 패드 에뮬레이터에서 실행
2. 좌측 NavigationRail 확인
3. 중앙 콘텐츠 + 우측 상세 패널 확인
4. 가로/세로 모드 전환 테스트

---

## 기술 선택 이유

| 기술 | 선택 이유 |
|------|-----------|
| **Firestore** | 실시간 리스너 지원, NoSQL 유연성, Firebase 생태계 통합 |
| **NavigationRail** | Material 3 표준, 패드/데스크톱에 적합한 네비게이션 |
| **AdaptiveScaffold** | 폰/패드를 하나의 위젯으로 처리, 유지보수 용이 |

---

## 개발 중 발생한 오류 및 대처

### 오류 1: Firebase 패키지 버전 충돌 (firebase_database)

**증상:**
```
firebase_database ^11.3.10 depends on firebase_core ^3.15.2
ink_app depends on firebase_core ^4.4.0
```

**원인:**
- firebase_database와 firebase_core 버전 불일치

**해결:**
- firebase_database 제거
- Firestore 실시간 리스너로 대체 (snapshots() 사용)
- 나중에 필요 시 Firebase 패키지 전체 업그레이드 고려

---

### 오류 2: cloud_firestore 버전 충돌

**증상:**
```
cloud_firestore ^5.6.5 is incompatible with firebase_core ^4.4.0
```

**원인:**
- cloud_firestore 버전이 낮아서 firebase_core와 충돌

**해결:**
```yaml
# 변경 전
cloud_firestore: ^5.6.5

# 변경 후
cloud_firestore: ^6.1.2
```

---

### 오류 3: withOpacity deprecated 경고

**증상:**
```
'withOpacity' is deprecated. Use .withValues() to avoid precision loss
```

**해결:**
```dart
// 변경 전
AppColors.gold.withOpacity(0.2)

// 변경 후
AppColors.gold.withValues(alpha: 0.2)
```

---

## 알려진 제한사항 / TODO

- [ ] Firebase Realtime DB 미적용 (버전 충돌로 보류)
- [ ] 친구 목록 실제 데이터 연동
- [ ] 채팅 목록 실제 데이터 연동
- [ ] 태그 목록 실제 데이터 연동
- [ ] 프로필 편집 기능
- [ ] 새 채팅 생성 기능

---

## 참고 문서

- `잉크_앱프로젝트_정보/INK_최종_기능_명세서_v1.0.md`
- `잉크_앱프로젝트_정보/INK_디자인_명세서_v1.0.md`
- `잉크_앱프로젝트_정보/기본_디자인_색정보.md`
- `잉크_앱프로젝트_정보/개발_순서.md`

---

## 다음 단계

| Phase | 내용 |
|-------|------|
| **3.1** | 친구 목록 화면 UI + Firestore 연동 |
| **3.2** | 친구 추가 (ID/전화번호) |
| **4.1** | 채팅 목록 – 퍼즐 카드 UI |
