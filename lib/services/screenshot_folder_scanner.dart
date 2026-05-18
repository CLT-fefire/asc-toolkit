import 'dart:io';

import '../data/screenshot_locale_map.dart';
import '../models/parsed_screenshot_bundle.dart';

/// 디자인팀이 전달한 부모 폴더(`02_APPSTORE/`)를 스캔해
/// (locale, displayType) 그룹으로 묶은 [ParsedScreenshotBundle] 을 반환.
///
/// 규칙:
/// - 1단계 하위 디렉터리 이름에서 locale 추출 (`01_KR` → `ko`)
/// - 디렉터리 안 `.jpg/.jpeg/.png` 만 대상
/// - 파일명 안 `_{SIZE}_` 로 displayType, 끝 `_NN` 으로 order 추출
/// - locale 인식 못 한 폴더, displayType/order 인식 못 한 파일, 그리고
///   루트에 놓인 파일(앱 아이콘 등)은 [SkippedItem] 으로 기록
class ScreenshotFolderScanner {
  static const _imageExts = {'.jpg', '.jpeg', '.png'};

  ParsedScreenshotBundle scan(Directory root) {
    final groups = <ScreenshotGroup>[];
    final skipped = <SkippedItem>[];

    if (!root.existsSync()) {
      return ParsedScreenshotBundle(
        rootPath: root.path,
        groups: const [],
        skippedItems: [SkippedItem(name: root.path, reason: '폴더가 존재하지 않음')],
      );
    }

    final entries = root.listSync()..sort((a, b) => a.path.compareTo(b.path));

    for (final entry in entries) {
      final name = entry.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      if (entry is File) {
        if (_isImageFile(name)) {
          skipped.add(SkippedItem(
            name: name,
            reason: '루트 파일은 스크린샷 폴더 밖이므로 스킵 (앱 아이콘 등)',
          ));
        }
        continue;
      }
      if (entry is! Directory) continue;

      final locale = localeFromFolderName(name);
      if (locale == null) {
        skipped.add(SkippedItem(
          name: name,
          reason: '폴더명에서 locale 인식 실패',
        ));
        continue;
      }

      final perDisplayType = <String, List<ScreenshotFile>>{};
      final dirFiles = entry.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final f in dirFiles) {
        final fileName = f.uri.pathSegments.last;
        if (!_isImageFile(fileName)) continue;

        final displayType = displayTypeFromFileName(fileName);
        final order = orderFromFileName(fileName);
        if (displayType == null || order == null) {
          skipped.add(SkippedItem(
            name: '$name/$fileName',
            reason: '파일명에서 디스플레이 타입 또는 순번 인식 실패',
          ));
          continue;
        }

        perDisplayType.putIfAbsent(displayType, () => []).add(
              ScreenshotFile(file: f, order: order),
            );
      }

      for (final dt in perDisplayType.keys) {
        final files = perDisplayType[dt]!
          ..sort((a, b) => a.order.compareTo(b.order));
        groups.add(ScreenshotGroup(
          folderName: name,
          locale: locale,
          displayType: dt,
          files: files,
        ));
      }
    }

    return ParsedScreenshotBundle(
      rootPath: root.path,
      groups: groups,
      skippedItems: skipped,
    );
  }

  bool _isImageFile(String name) {
    final lower = name.toLowerCase();
    return _imageExts.any((ext) => lower.endsWith(ext));
  }
}
