# asc_toolkit

App Store Connect API를 통해 **여러 팀의 앱 메타데이터**를 조회·수정하는 Flutter macOS 데스크탑 도구.

> 현재 상태: **PoC 1단계 — 다중 팀 등록 + 앱 목록 조회**까지 완료. 메타데이터 수정 기능은 후속.

## 무엇을 하는 도구인가

- 팀별로 다른 App Store Connect API Key(.p8)를 등록하고
- 팀을 선택하면 해당 팀이 관리하는 **앱 목록을 한 번에 조회**
- (예정) 앱 이름·부제·카테고리·키워드·설명·"이 버전의 새로운 기능"·심사 정보·스크린샷 등 수정

순수 Flutter macOS 앱이라 CORS 제약 없이 App Store Connect API를 직접 호출합니다.

## 사전 준비

### 1) Flutter 환경
```bash
flutter --version    # 3.41.x stable 이상
flutter doctor
```

### 2) App Store Connect API Key 발급
1. https://appstoreconnect.apple.com → 사용자 및 액세스 → 통합 → 팀 키
2. **Key Name** 입력, **Access** 선택 (App Manager 또는 Admin 권장)
3. 생성 직후 **.p8 파일을 1회만 다운로드** (재다운로드 불가)
4. 화면에서 **Issuer ID**, **Key ID** 복사

> .p8 파일은 PKCS#8 PEM 형식이며 절대 외부에 공유하지 마십시오. 본 앱은 `flutter_secure_storage`(macOS Keychain)에만 저장합니다.

## 실행

```bash
cd /Users/Shared/Source/asc_toolkit
flutter pub get
flutter run -d macos
```

첫 실행 후:

1. **"팀 추가"** 클릭
2. 팀 표시 이름(예: `DearU 메인`, `Fork JYP`) / Issuer ID / Key ID 입력
3. **.p8 키 첨부** 버튼으로 다운로드한 키 파일 선택
4. **저장** → 팀 리스트에 추가됨
5. 팀을 탭하면 해당 팀의 **앱 목록 조회**

## 디렉토리 구조

```
lib/
├── main.dart                       # 진입점 + MaterialApp
├── models/
│   ├── team.dart                   # 팀 메타 모델
│   └── app_summary.dart            # ASC /v1/apps 응답
├── services/
│   ├── team_repository.dart        # Keychain 기반 팀 CRUD
│   ├── jwt_signer.dart             # ES256 JWT 생성
│   └── asc_api_client.dart         # ASC API 호출 (dio, 페이지네이션 포함)
└── screens/
    ├── teams_screen.dart           # 팀 리스트
    ├── team_form_screen.dart       # 팀 추가/편집 폼
    └── apps_screen.dart            # 선택된 팀의 앱 목록
```

## 보안 메모

- .p8 키 본문은 macOS Keychain (`flutter_secure_storage`)에 저장
- JWT는 매 요청 직전 생성 (TTL 18분, ASC 권장 최대 20분)
- **App Sandbox 비활성화** 상태로 빌드합니다.
  - 이유: Sandbox 환경에서 Keychain 쓰기는 `keychain-access-groups` + Apple Developer Team 자동 사인이 필수인데, 사내 도구라 굳이 그 셋업을 가져갈 필요가 없음
  - Mac App Store 배포가 필요해지면 Sandbox 다시 켜고 자동 사인 + keychain-access-groups 추가 필요
- 외부 배포는 `.app` 또는 `.dmg`로 충분합니다. (Gatekeeper 경고는 우클릭 → 열기로 1회 우회 또는 notarize)

## 다음 단계 (Roadmap)

PoC 1차에서 검증된 호출 패턴(`JWT → Bearer → /v1/apps`)을 기반으로 다음 항목을 점진적으로 추가:

| 항목 | API 엔드포인트 |
| --- | --- |
| 앱 이름, 부제 | `appInfoLocalizations` / `appStoreVersionLocalizations` |
| 카테고리 | `appInfos` PATCH |
| 설명·키워드·프로모션 텍스트·"이 버전의 새로운 기능" | `appStoreVersionLocalizations` PATCH |
| 앱 심사 정보 | `appStoreReviewDetails` PATCH |
| 스크린샷 업로드 | `appScreenshotSets` reserve → PUT → commit |
| Word(.docx) 자동 파싱 | 별도 모듈 (zip + XML) |

## 트러블슈팅

| 현상 | 원인 | 해결 |
| --- | --- | --- |
| `SocketException: Operation not permitted` | macOS Sandbox에서 네트워크 차단 | `Runner/*.entitlements`의 `com.apple.security.network.client=true` 확인 |
| `HTTP 401 NOT_AUTHORIZED` | JWT 만료 또는 Issuer/Key/p8 불일치 | 팀 편집 화면에서 정보 재확인. 시계 동기화 확인 (`exp`는 UTC) |
| `HTTP 403 FORBIDDEN` | API Key 권한 부족 | App Store Connect에서 Key의 Access 레벨을 App Manager 이상으로 |
| `flutter run` 실행 후 빈 화면 | DevTools 워밍업 | 첫 빌드 시 30~60초 소요. 콘솔 로그 확인 |
