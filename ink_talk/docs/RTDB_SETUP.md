# Realtime Database (RTDB) 설정

## Permission denied 시 확인 사항

캔버스 입장 시 로그에 `setValue at .../members/... failed: DatabaseError: Permission denied` 또는 `RTDB setRoomMember 재시도 후 실패` 가 나오면 아래를 확인하세요.

### 1. RTDB 규칙 배포 (필수)

**반드시 `ink_talk` 디렉터리에서** 다음을 실행해 규칙을 배포하세요.  
(`firebase.json`과 `database.rules.json`이 있는 위치)

```bash
cd ink_talk
firebase deploy --only database
```

배포 후 Firebase 콘솔 → Realtime Database → 규칙 탭에서 아래와 같은지 확인하세요.

- `rt/rooms/{roomId}/members/{uid}`: `auth != null && auth.uid == $uid` 일 때만 쓰기 허용
- `rt/rooms/{roomId}/events`: `auth != null` 이고 `members` 에서 `auth.uid` 값이 `true` 일 때만 읽기/쓰기 허용

규칙이 배포되지 않으면 기본값(전체 거부)이라 **Permission denied** 가 발생합니다.

### 2. 저번 테스트에서 작성한 내용이 안 보일 때

- **캔버스 진입 시** Firestore에서 손글씨/텍스트/미디어를 먼저 로드한 뒤 **즉시 화면에 그립니다.**  
  그 다음 RTDB `setRoomMember` 를 호출합니다.  
  따라서 **RTDB Permission denied 가 나와도, 이미 Firestore에 저장된 이전 작성 내용은 먼저 표시**됩니다.
- 여전히 안 보이면: 같은 방(roomId)으로 들어갔는지, 이전 실행에서 저장이 완료된 뒤 앱을 종료했는지 확인하세요.  
  (저장 중에 커서/앱이 꺼지면 해당 분만 Firestore에 없을 수 있음)
- RTDB `setRoomMember` 가 실패하면 **실시간 이벤트 스트림**만 동작하지 않고, Firestore 1회 로드분은 그대로 보입니다.

### 3. Firestore 인덱스 (최신 N건 쿼리)

`getStrokesPageNewest` / `getTextsPageNewest` / `getMediaPageNewest` 사용을 위해  
`firestore.indexes.json` 에 `createdAt` DESC 인덱스가 추가되어 있습니다.  
한 번 배포해 두세요.

```bash
firebase deploy --only firestore:indexes
```
