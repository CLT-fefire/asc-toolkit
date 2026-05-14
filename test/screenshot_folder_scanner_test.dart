import 'dart:io';

import 'package:asc_toolkit/services/screenshot_folder_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScreenshotFolderScanner', () {
    final sampleRoot = Directory(
      '/Users/Shared/Source/SharedDocs/knowledge/asc-toolkit/assets/AppStore-assets/02_APPSTORE',
    );

    test('디자인팀 샘플 02_APPSTORE 를 정확히 7 locale × 7장으로 인식', () {
      if (!sampleRoot.existsSync()) {
        // 샘플 폴더가 없으면 스킵 (CI 환경 등)
        return;
      }

      final bundle = ScreenshotFolderScanner().scan(sampleRoot);

      // 7개 locale 모두 인식 (각 6.9" 단일 displayType)
      expect(bundle.groups.length, 7,
          reason: '7개 locale × 1 displayType = 7 그룹');

      // 모든 그룹이 7장
      for (final g in bundle.groups) {
        expect(g.fileCount, 7,
            reason: '${g.folderName} 그룹은 7장이어야 함');
        expect(g.displayType, 'APP_IPHONE_69');

        // order 1..7 오름차순 보장
        final orders = g.files.map((f) => f.order).toList();
        expect(orders, [1, 2, 3, 4, 5, 6, 7],
            reason: '${g.folderName} order 정렬 확인');
      }

      // locale 매핑 검증 (folderName 은 macOS NFD 정규화 이슈가 있어 locale set 비교)
      final locales = bundle.groups.map((g) => g.locale).toSet();
      expect(
        locales,
        {'ko', 'en-US', 'zh-Hans', 'zh-Hant', 'vi', 'id', 'ja'},
      );

      // 루트의 앱 아이콘 jpg 는 skipped 로 기록
      final hasAppIconSkip = bundle.skippedItems
          .any((s) => s.name.contains('APPICON'));
      expect(hasAppIconSkip, isTrue,
          reason: '루트 앱 아이콘 파일은 스킵 항목에 포함되어야 함');

      // 총 파일 49장
      expect(bundle.totalFileCount, 49);
    });

    test('존재하지 않는 경로는 skippedItems 에 사유 기록', () {
      final bundle = ScreenshotFolderScanner()
          .scan(Directory('/tmp/does-not-exist-asc-toolkit-test'));
      expect(bundle.groups, isEmpty);
      expect(bundle.skippedItems, isNotEmpty);
    });
  });
}
