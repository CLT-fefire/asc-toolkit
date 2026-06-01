# asc_toolkit

App Store Connect API를 통해 **여러 팀의 앱 메타데이터**를 조회·수정하는 Flutter macOS 데스크탑 도구.

> 현재 상태: **v1.0.1 릴리즈** — 다중 팀 메타데이터 일괄 편집 + 스크린샷 일괄 업로드까지 구현. [Releases](https://github.com/CLT-fefire/asc-toolkit/releases/latest)에서 서명된 dmg 다운로드.

## 무엇을 하는 도구인가

- 팀별로 다른 App Store Connect API Key(.p8)를 등록하고
- 팀을 선택하면 해당 팀이 관리하는 **앱 목록을 한 번에 조회**
- 앱 이름·부제·카테고리·키워드·설명·"이 버전의 새로운 기능"·심사 정보·서버 알림을 **로케일 일괄 편집** (.docx/.txt/텍스트 입력 → 모든 로케일 자동 매핑)
- 디자인팀 폴더 한 번 선택 → **스크린샷 일괄 업로드** (로케일·사이즈 자동 인식)

순수 Flutter macOS 앱이라 CORS 제약 없이 App Store Connect API를 직접 호출합니다.

## 다운로드 / 설치

[**Releases**](https://github.com/CLT-fefire/asc-toolkit/releases/latest)에서 `ASC-Toolkit-<버전>-macos.dmg`를 받습니다. Dear U **Developer ID**로 코드 서명되어 있습니다.

1. dmg 열기 → `ASC Toolkit.app`을 `Applications` 폴더로 드래그
2. **최초 실행만**: Finder에서 `/Applications/ASC Toolkit.app` 우클릭 → **열기** → 대화상자에서 다시 **열기**. (서명은 됐지만 공증 전이라 더블클릭하면 "확인되지 않은 개발자" 경고가 뜹니다. 우클릭 → 열기는 한 번만, 이후 더블클릭으로 일반 실행.)

> 아래 "사전 준비 / 실행"은 소스에서 직접 빌드·개발할 때만 필요합니다. 배포용 서명 dmg는 `./tools/package_macos.sh`로 만듭니다(Developer ID 자동 감지 → 없으면 ad-hoc).

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

> .p8 파일은 PKCS#8 PEM 형식이며 절대 외부에 공유하지 마십시오. 본 앱은 파일 기반(`~/Library/Application Support/asc_toolkit/teams.json`, chmod 600)으로 저장합니다 — macOS Keychain은 쓰지 않습니다(ad-hoc 환경의 키체인 다이얼로그 반복 회피).

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
│   ├── team.dart                          # 팀 메타 모델
│   ├── app_summary.dart                   # ASC /v1/apps 응답
│   ├── app_store_version.dart             # 버전 (PREPARE_FOR_SUBMISSION 등)
│   └── app_store_version_localization.dart  # 로케일별 whatsNew/설명 등
├── services/
│   ├── team_repository.dart        # 파일 기반 팀 CRUD (~/Library/Application Support/asc_toolkit/teams.json)
│   ├── jwt_signer.dart             # ES256 JWT 생성
│   └── asc_api_client.dart         # ASC API 호출 (dio, 페이지네이션, 에러 매핑)
└── screens/
    ├── teams_screen.dart           # 팀 리스트
    ├── team_form_screen.dart       # 팀 추가/편집 폼
    ├── apps_screen.dart            # 선택된 팀의 앱 목록
    └── app_detail_screen.dart      # 버전/로케일 선택 + whatsNew 편집
```

## 저장소 & 보안 메모

- **저장 위치**: `~/Library/Application Support/asc_toolkit/teams.json`
  - 디렉토리 chmod 700, 파일 chmod 600 (현재 macOS 사용자만 읽기)
  - fastlane이 `AuthKey_*.p8`을 평문 파일로 두는 것과 동등한 보안 수준
  - macOS Keychain을 쓰지 않는 이유: ad-hoc 코드사이닝 환경에서 매 실행마다 "키체인 액세스 허용" 다이얼로그가 반복되는 문제 우회
- **JWT**: 매 요청 직전 생성 (TTL 18분, ASC 권장 최대 20분)
- **App Sandbox 비활성화** 상태로 빌드합니다.
  - Mac App Store 배포 안 함. 사내 도구로 사용
  - Mac App Store 배포가 필요해지면 Sandbox 다시 켜고 자동 사인 + keychain-access-groups 추가 필요
- 외부 배포는 `.app` 또는 `.dmg`로 충분합니다. (Gatekeeper 경고는 우클릭 → 열기로 1회 우회 또는 notarize)

## 구현된 기능 (v1.0.x)

아래 항목은 모두 구현 완료되었습니다. 자세한 사용법은 [사내 Confluence 가이드](https://everysing.atlassian.net/wiki/spaces/IMA/pages/4439343474/ASC+Toolkit) 참고.

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
