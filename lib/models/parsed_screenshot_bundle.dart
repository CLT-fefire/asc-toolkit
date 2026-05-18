import 'dart:io';

/// 한 (locale, displayType) 그룹의 스크린샷 파일 목록.
///
/// 파일은 `order` 오름차순으로 정렬되어 있으며, ASC 업로드 순서가 된다.
class ScreenshotGroup {
  ScreenshotGroup({
    required this.folderName,
    required this.locale,
    required this.displayType,
    required this.files,
  });

  /// 원본 폴더명 (`01_KR` 등) — UI 표시용
  final String folderName;

  /// ASC locale (예: `ko`, `en-US`)
  final String locale;

  /// ASC `screenshotDisplayType` (예: `APP_IPHONE_69`)
  final String displayType;

  /// `order` 오름차순으로 정렬된 파일 목록
  final List<ScreenshotFile> files;

  int get fileCount => files.length;
}

/// 그룹에 속한 한 파일.
class ScreenshotFile {
  ScreenshotFile({
    required this.file,
    required this.order,
  });

  final File file;

  /// 파일명 끝 `_NN` 의 NN — ASC 등록 순서 (1부터)
  final int order;

  String get fileName => file.uri.pathSegments.last;
}

/// 부모 폴더 스캔 결과 묶음.
class ParsedScreenshotBundle {
  ParsedScreenshotBundle({
    required this.rootPath,
    required this.groups,
    required this.skippedItems,
  });

  /// 사용자가 선택한 부모 폴더 절대 경로 (`02_APPSTORE`)
  final String rootPath;

  /// 인식된 (locale, displayType) 그룹 목록
  final List<ScreenshotGroup> groups;

  /// 스킵된 항목 (이유 동봉) — UI에 안내 표시
  final List<SkippedItem> skippedItems;

  int get totalFileCount =>
      groups.fold<int>(0, (sum, g) => sum + g.fileCount);

  bool get isEmpty => groups.isEmpty;
}

/// 스킵된 폴더/파일 + 사유 (예: 앱 아이콘, 인식 실패한 폴더명).
class SkippedItem {
  SkippedItem({required this.name, required this.reason});

  final String name;
  final String reason;
}
