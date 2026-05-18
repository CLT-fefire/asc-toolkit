/// 디자인팀이 전달하는 스크린샷 폴더/파일명 → ASC 식별자 매핑.
///
/// ## 폴더 패턴
/// `{NN}_{LOCALE_CODE}(부가설명)?`
/// - 예: `01_KR`, `03_CH_S(간체)`, `04_CH_T(번체)`
///
/// ## 파일 패턴
/// `APPSTORE_*_{LOCALE}_{SIZE}_{NN}.{jpg|png|jpeg}`
/// - 예: `APPSTORE_STARSHIP_KR_6_9INCH_07.jpg`
/// - `NN` 은 ASC 등록 순서 (1부터)
const Map<String, String> kFolderToAscLocale = {
  'KR': 'ko',
  'EN': 'en-US',
  'CH_S': 'zh-Hans',
  'CH_T': 'zh-Hant',
  'VI': 'vi',
  'IN': 'id',
  'JP': 'ja',
};

/// 파일명 안 `_{SIZE}_` 토큰 → ASC `screenshotDisplayType` enum.
///
/// ⚠️ ASC 의 enum 이름과 실제 디스플레이 인치 표기는 일치하지 않는다.
/// Apple 은 신규 디바이스(예: iPhone 16 Pro Max 6.9") 가 나와도 enum 을 새로 추가하지 않고,
/// 기존 enum 의 허용 해상도만 확장한다. 1320×2868 (6.9") 은 `APP_IPHONE_67` 로 들어간다.
/// 매핑 근거: fastlane PR #29760 `DEVICE_RESOLUTIONS` 정의.
/// https://github.com/fastlane/fastlane/pull/29760
const Map<String, String> kFilenameSizeToAscType = {
  // 디자인팀 표기 "6.9인치" (1320×2868) → ASC 는 6.7" 카테고리로 통합 수신.
  '6_9INCH': 'APP_IPHONE_67',
  // 1290×2796 등 기존 6.7" 도 같은 enum.
  '6_7INCH': 'APP_IPHONE_67',
  // 1284×2778, 1242×2688 (iPhone XS Max 등).
  '6_5INCH': 'APP_IPHONE_65',
  // 디자인팀 표기 "6.1인치" — fastlane 기준 `APP_IPHONE_58` 은 6.1" 디스플레이 (iPhone 11/12/13/14, 1170×2532).
  // ASC enum 의 `APP_IPHONE_61` 은 실제로는 6.3" (iPhone 14 Pro/15/16, 1179×2556).
  // 우리 디자인팀이 어느 디바이스용을 의미하는지는 첫 6.1INCH 자산 들어올 때 확정 필요.
  // 우선 더 흔한 6.1" (= ASC 의 _58) 로 매핑. 6.3" 면 _61.
  '6_1INCH': 'APP_IPHONE_58',
  '5_5INCH': 'APP_IPHONE_55',
  // ASC `APP_IPAD_PRO_3GEN_129` 가 실제로는 13" iPad (2064×2752 포함).
  '13INCH': 'APP_IPAD_PRO_3GEN_129',
  '12_9INCH': 'APP_IPAD_PRO_129',
  '11INCH': 'APP_IPAD_PRO_3GEN_11',
};

/// 폴더명에서 locale code 추출 + ASC locale 반환.
///
/// - `01_KR` → `ko`
/// - `03_CH_S(간체)` → `zh-Hans`  (괄호 이후는 무시)
/// - 알 수 없으면 null
String? localeFromFolderName(String folderName) {
  // 앞쪽 숫자 prefix(`01_`) 제거
  var s = folderName.trim();
  final prefixMatch = RegExp(r'^\d+_').firstMatch(s);
  if (prefixMatch != null) {
    s = s.substring(prefixMatch.end);
  }
  // 괄호 이후 부가설명 제거
  final parenIndex = s.indexOf('(');
  if (parenIndex >= 0) {
    s = s.substring(0, parenIndex);
  }
  return kFolderToAscLocale[s.trim()];
}

/// 파일명에서 `_{SIZE}_` 토큰을 찾아 ASC display type 반환.
///
/// - `APPSTORE_STARSHIP_KR_6_9INCH_07.jpg` → `APP_IPHONE_69`
/// - 매칭 실패 시 null
String? displayTypeFromFileName(String fileName) {
  for (final entry in kFilenameSizeToAscType.entries) {
    if (fileName.contains('_${entry.key}_')) {
      return entry.value;
    }
  }
  return null;
}

/// 파일명 끝 `_NN.{ext}` 의 순번 추출.
///
/// - `APPSTORE_STARSHIP_KR_6_9INCH_07.jpg` → 7
/// - 매칭 실패 시 null
int? orderFromFileName(String fileName) {
  final match = RegExp(r'_(\d+)\.[A-Za-z]+$').firstMatch(fileName);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
