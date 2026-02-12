# INK 앱 Firestore 읽기·쓰기 전체 목록

코드 기준으로 Firestore에서 이루어지는 **읽기(Read)** 와 **쓰기(Write)** 연산을 컬렉션·서비스·메서드 단위로 정리한 보고서입니다.

---

## 1. 컬렉션별 요약

| 컬렉션 | 경로 | 읽기(리스너/get) | 쓰기(add/set/update/delete/batch) |
|--------|------|------------------|-----------------------------------|
| rooms | `rooms/{roomId}` | 3 | 10+ |
| strokes | `rooms/{roomId}/strokes` | 2 | 7 |
| texts | `rooms/{roomId}/texts` | 2 | 4 |
| shapes | `rooms/{roomId}/shapes` | 1 | 5 |
| media | `rooms/{roomId}/media` | 1 | 5 |
| users | `users/{userId}` | 6 | 4 |
| friends | `friends` (서브컬렉션 없음) | 5 | 10+ |
| tags | `tags` | 3 | 3 |
| audit_logs | `audit_logs` | 0 | 1 (add만) |

---

## 2. 읽기(Read) 연산 — 전체 목록

### 2.1 rooms

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| room_service.dart | getRoomsStream | **snapshots()** | 내 채팅방 목록 실시간 스트림 (memberIds arrayContains, lastActivityAt orderBy) |
| room_service.dart | getRoom | **doc(roomId).get()** | 채팅방 단일 조회 (Source 옵션 가능) |
| room_service.dart | getRoomStream | **doc(roomId).snapshots()** | 채팅방 단일 실시간 스트림 |
| room_service.dart | getDirectRoom | **query.get()** | 1:1 방 조회 (type=direct, memberIds arrayContains) |
| room_service.dart | createOrGetDirectRoom | **query.get()** | 1:1 방 생성 전 기존 방 조회 (동일 쿼리) |
| room_service.dart | leaveRoom, inviteMembers 등 | **getRoom(roomId)** 내부에서 get() | 방 정보 읽기 |
| room_service.dart | getMemberUserInfo | **usersCollection.doc(userId).get()** | 멤버 사용자 정보 조회 |
| room_service.dart | resetCanvas | **roomRef.collection(sub).limit(400).get()** 반복 | strokes/shapes/texts/media 서브컬렉션 배치 조회 |

### 2.2 rooms/{roomId}/strokes

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| stroke_service.dart | getStrokesStream | **snapshots()** | 스트로크 실시간 스트림 (isDeleted=false, createdAt orderBy) |
| stroke_service.dart | countStrokesFromSenderAfter | **query.get()** | 차단 기간 중 발신자별 스트로크 수 (친구 차단 관리용) |

### 2.3 rooms/{roomId}/texts

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| text_service.dart | getTextsStream | **snapshots()** | 텍스트 실시간 스트림 |
| text_service.dart | countTextsFromSenderAfter | **query.get()** | 차단 기간 중 발신자별 텍스트 수 |

### 2.4 rooms/{roomId}/shapes

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| shape_service.dart | getShapesStream | **snapshots()** | 도형 실시간 스트림 |

### 2.5 rooms/{roomId}/media

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| media_service.dart | getMediaStream | **snapshots()** | 미디어 실시간 스트림 |

### 2.6 users

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| user_service.dart | createOrUpdateUser | **docRef.get()** (2회) | 로그인 시 사용자 문서 존재 여부 확인, 업데이트 후 재조회 |
| user_service.dart | getUserById | **doc(uid).get()** | UID로 사용자 조회 |
| user_service.dart | getUserByVisibleId | **where('visibleId').limit(1).get()** | visibleId로 사용자 조회 |
| user_service.dart | checkVisibleIdAvailable | getUserByVisibleId 내부 get() | ID 중복 검사 |
| user_service.dart | searchUsers | **where visibleId range .limit(20).get()** | 사용자 검색 (이름/ID) |
| user_service.dart | updateProfile | getUserByVisibleId 내부 get() | visibleId 중복 확인 |
| room_service.dart | getMemberUserInfo | **usersCollection.doc(userId).get()** | 방 멤버 사용자 정보 |
| friend_service.dart | addFriendById | **usersCollection.where('visibleId').limit(1).get()** | 친구 ID로 사용자 조회 |
| friend_service.dart | addFriendByPhone | **usersCollection.where('phoneNumber').limit(1).get()** | 전화번호로 사용자 조회 |
| friend_service.dart | getFriendUserInfo | **usersCollection.doc(friendId).get()** | 친구 사용자 정보 |
| contact_service.dart | findRegisteredUsers | **users.where('phoneNumber', whereIn: batch).get()** | 연락처 기반 가입자 조회 (30개 단위) |

### 2.7 friends

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| friend_service.dart | getFriendsStream | **snapshots()** | 친구 목록 실시간 (userId, status=accepted) |
| friend_service.dart | getPendingRequestsStream | **snapshots()** | 받은 친구 요청 실시간 (friendId, status=pending) |
| friend_service.dart | getSentRequestsStream | **snapshots()** | 보낸 친구 요청 실시간 (userId, status pending/rejected) |
| friend_service.dart | getBlockedUsersStream | **snapshots()** | 차단 목록 실시간 |
| friend_service.dart | addFriendById | **friendsCollection.where(...).get()** 2회 | 내→상대, 상대→내 문서 조회 |
| friend_service.dart | acceptFriendRequest | **doc(requestId).get()** | 요청 문서 조회 |
| friend_service.dart | rejectFriendRequest | **doc(requestId).get()** | 요청 문서 조회 |
| friend_service.dart | removeFriend | **where(...).get()** 2회 | 내 문서·상대 문서 조회 |
| friend_service.dart | blockFriend | **where(...).get()** | 내→상대 문서 조회 |
| friend_service.dart | unblockFriend | **where(...).get()** | 차단 문서 조회 |
| friend_service.dart | updateFriendNickname | **where(...).get()** | 수락된 친구 문서 조회 |
| contact_service.dart | _checkIfFriend | **friends.where(userId, friendId).limit(1).get()** | 이미 친구인지 확인 |

### 2.8 tags

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| tag_service.dart | getMyTagsStream | **snapshots()** | 내가 태그된 태그 실시간 (taggedUserId) |
| tag_service.dart | getRoomTagsStream | **snapshots()** | 특정 방의 태그 실시간 (roomId, taggedUserId) |
| tag_service.dart | getFilteredTags | **query.get()** | 필터된 태그 일회성 조회 (userId, roomId, targetType 등) |

---

## 3. 쓰기(Write) 연산 — 전체 목록

### 3.1 rooms

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| room_service.dart | createOrGetDirectRoom | **add(roomData)** + **docRef.get()** | 1:1 방 생성 |
| room_service.dart | createGroupRoom | **add(roomData)** + **docRef.get()** | 그룹 방 생성 |
| room_service.dart | leaveRoom | **doc(roomId).update({members})** | 방 나가기 (members.leftAt 등) |
| room_service.dart | inviteMembers | **doc(roomId).update({memberIds, members})** | 멤버 초대 |
| room_service.dart | updateMemberRole | **doc(roomId).update(members.$memberId.role)** | 멤버 역할 변경 |
| room_service.dart | updateRoom | **doc(roomId).update(updates)** | 방 정보 수정 (이름, 이미지, exportAllowed 등) |
| room_service.dart | markAsRead | **doc(roomId).update(members.$userId.unreadCount)** | 읽음 처리 |
| room_service.dart | updateLastEvent | **doc(roomId).update(lastActivityAt, lastEventType 등)** | 마지막 이벤트 업데이트 (스트로크/텍스트/미디어 등 저장 시 호출) |
| room_service.dart | resetCanvas | **batch.update(doc.reference, isDeleted 등)** 반복 | 캔버스 초기화 (strokes/shapes/texts/media 일괄 소프트 삭제) |

### 3.2 rooms/{roomId}/strokes

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| stroke_service.dart | saveStroke | **add(stroke.toFirestore())** | 스트로크 저장 (1획 = 1 write) |
| stroke_service.dart | confirmStroke | **doc(strokeId).update({isConfirmed: true})** | 스트로크 확정 |
| stroke_service.dart | updateStrokePoints | **doc(strokeId).update({points})** | 스트로크 포인트 업데이트 (선택 이동 시) |
| stroke_service.dart | deleteStroke | **doc(strokeId).update(isDeleted 등)** | 스트로크 소프트 삭제 |
| stroke_service.dart | deleteStrokes | **batch.update(...)** N건 | 여러 스트로크 일괄 소프트 삭제 |
| stroke_service.dart | restoreStroke | **doc(strokeId).update({isDeleted: false})** | 스트로크 복구 (Undo) |

### 3.3 rooms/{roomId}/texts

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| text_service.dart | saveText | **add(text.toFirestore())** | 텍스트 저장 |
| text_service.dart | updateText | **doc(textId).update(updates)** | 텍스트 내용/위치 수정 |
| text_service.dart | deleteText | **doc(textId).update(isDeleted 등)** | 텍스트 소프트 삭제 |

### 3.4 rooms/{roomId}/shapes

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| shape_service.dart | saveShape | **add(shape.toFirestore())** | 도형 저장 |
| shape_service.dart | updateShape | **doc(shapeId).update(updates)** | 도형 위치/스타일/zIndex 등 수정 |
| shape_service.dart | deleteShape | **doc(shapeId).update(isDeleted 등)** | 도형 소프트 삭제 |
| shape_service.dart | restoreShape | **doc(shapeId).update({isDeleted: false})** | 도형 복구 (Undo) |
| shape_service.dart | bringToFront / sendToBack | updateShape 호출 | zIndex만 업데이트 |

### 3.5 rooms/{roomId}/media

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| media_service.dart | saveMedia | **add(media.toFirestore())** | 미디어 메타 저장 (Storage URL 등) |
| media_service.dart | updateMedia | **doc(mediaId).update(updates)** | 위치/크기/회전/crop/zIndex 등 수정 |
| media_service.dart | deleteMedia | **doc(mediaId).update(isDeleted 등)** | 미디어 소프트 삭제 |
| media_service.dart | restoreMedia | **doc(mediaId).update({isDeleted: false})** | 미디어 복구 (Undo) |

### 3.6 users

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| user_service.dart | createOrUpdateUser | **docRef.update(...)** 또는 **docRef.set(...)** | 로그인 시 사용자 생성/최종 활동 시간 등 업데이트 |
| user_service.dart | updateProfile | **doc(currentUserId).update(updates)** | 프로필(displayName, statusMessage, visibleId) 수정 |
| user_service.dart | deleteUserDocument | **doc(uid).delete()** | 탈퇴 시 사용자 문서 삭제 |

### 3.7 friends

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| friend_service.dart | addFriendById | **doc.reference.update(...)** (거절→재요청 시) 또는 **add({...})** | 친구 요청 (새 문서 또는 기존 문서 업데이트) |
| friend_service.dart | acceptFriendRequest | **batch.update(docRef)** + **batch.set(reverseDocRef)** | 요청 수락 (원본 업데이트 + 역방향 문서 생성) |
| friend_service.dart | rejectFriendRequest | **docRef.update({status: rejected})** | 요청 거절 |
| friend_service.dart | removeFriend | **batch.update(...)** 다수 | 친구 삭제 (hidden 처리, 쌍방 문서) |
| friend_service.dart | blockFriend | **docs.first.reference.update(...)** 또는 **add({...})** | 친구 차단 |
| friend_service.dart | unblockFriend | **doc.reference.update(...)** | 차단 해제 |
| friend_service.dart | updateFriendNickname | **query.docs.first.reference.update(updates)** | 친구 별명 설정 |

### 3.8 tags

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| tag_service.dart | createTag | **add(tag.toFirestore())** | 태그 생성 |
| tag_service.dart | markAsRead | **doc(tagId).update({isRead: true})** | 태그 읽음 처리 |
| tag_service.dart | deleteTag | **doc(tagId).delete()** | 태그 삭제 |

### 3.9 audit_logs

| 파일 | 메서드/위치 | 연산 | 설명 |
|------|-------------|------|------|
| audit_log_service.dart | log (및 logStrokeCreated 등) | **add({eventType, collection, documentId, userId, ...})** | 감사 로그 추가 (스트로크/텍스트/도형/미디어/방/친구 생성·삭제 등 시 1회씩 호출) |

---

## 4. 호출 관계 요약 (쓰기 발생 경로)

- **스트로크 1획**: saveStroke(1 write) + logStrokeCreated(1 write) + updateLastEvent(1 write) → **방당 최소 3 writes**
- **스트로크 확정**: confirmStroke(1 write)
- **스트로크 이동**: 선택 N개 이동 시 updateStrokePoints N회 → **N writes**
- **스트로크 삭제**: deleteStroke(1) 또는 deleteStrokes(batch) + logStrokeDeleted N회
- **텍스트/도형/미디어**: save 1회 + audit log 1회 + updateLastEvent 1회
- **방 생성**: add(room) 1회 + get() 1회 + logRoomCreated 1회
- **친구 요청**: add 또는 update 1회 + log 1회; 수락 시 batch 2 writes + log 1회

---

## 5. Firebase Storage (Firestore 아님)

- **media_service.dart**: `FirebaseStorage.instance.ref().putFile()` / `putData()` — 이미지·영상·PDF 업로드. 다운로드 URL은 Firestore `media` 문서에 저장.

---

*작성 기준: ink_talk/lib 내 서비스·모델 코드. 읽기 = get() 및 snapshots() 구독, 쓰기 = add/set/update/delete/batch.*
