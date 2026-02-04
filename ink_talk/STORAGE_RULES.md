# Firebase Storage 보안 규칙

## 오류 확인

사진/영상 추가 시 **반응이 없거나** **"업로드에 실패했습니다"**가 나오면, Firebase Storage **보안 규칙** 오류일 가능성이 큽니다.

- 콘솔에서 확인: [Firebase Console](https://console.firebase.google.com) → 프로젝트 **ink-talk-24c71** → **Storage** → **규칙** 탭
- 기본 규칙이 `allow read, write: if false;`이면 모든 요청이 거부됩니다.

## 앱에서 사용하는 경로

- 업로드/다운로드 경로: `rooms/{roomId}/media/{파일명}`
- 예: 테스트 채팅방 ID가 `abc123`이면 → `rooms/abc123/media/1738xxxxx_image.jpg`

## 규칙 적용 방법

### 방법 1: Firebase 콘솔에서 직접 수정 (가장 빠름)

1. [Firebase Console](https://console.firebase.google.com) → 프로젝트 선택
2. **Storage** → **규칙** 탭
3. 아래 규칙으로 **전체 교체** 후 **게시**

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /rooms/{roomId}/media/{fileName} {
      allow read, write: if request.auth != null;
    }
  }
}
```

4. **게시** 클릭

### 방법 2: Firebase CLI로 배포

프로젝트 루트에서 Firebase CLI로 Storage 규칙을 배포할 수 있습니다.

```bash
cd ink_talk
firebase deploy --only storage
```

(최초 사용 시 `firebase init`에서 Storage 규칙 파일 경로를 `storage.rules`로 지정해야 합니다.)

## 규칙 설명

- `request.auth != null`: **로그인한 사용자**만 허용 (Google 로그인 등)
- `rooms/{roomId}/media/{fileName}`: 채팅방별 미디어 경로만 허용
- 테스트 채팅방에서도 동일한 규칙으로 동작합니다.

규칙 적용 후 앱에서 다시 사진 추가를 시도해 보세요.

---

## 테스트 후 복구 (기록)

- **적용 일자**: 테스트용으로 위 규칙(`allow read, write: if request.auth != null`)을 Firebase 콘솔에 **교체·게시**한 상태입니다.
- **복구 시점**: 테스트가 끝나면 **Storage 보안 규칙 복구**를 진행하세요.
- **복구 방법**:
  1. [Firebase Console](https://console.firebase.google.com) → 프로젝트 **ink-talk-24c71** → **Storage** → **규칙**
  2. 운영/배포 정책에 맞게 규칙 수정 후 **게시**
     - 예: 방 멤버만 허용하도록 Firestore 등으로 검증하는 규칙으로 변경
     - 또는 배포 전에 원래 사용하던 규칙이 있었다면 그대로 복구
- **로컬 규칙 파일**: `ink_talk/storage.rules` 에도 동일 내용이 있으므로, 복구 시 이 파일을 수정한 뒤 `firebase deploy --only storage` 로 배포해도 됩니다.
