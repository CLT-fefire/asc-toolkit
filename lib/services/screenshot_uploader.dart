import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/parsed_screenshot_bundle.dart';
import '../models/team.dart';
import 'asc_api_client.dart';

/// 진행 상태 변경 콜백.
typedef ScreenshotProgress = void Function(ScreenshotUploadProgress p);

/// 그룹별 진행 상태. 한 그룹 = (locale, displayType).
class ScreenshotUploadProgress {
  ScreenshotUploadProgress({
    required this.groupIndex,
    required this.groupCount,
    required this.folderName,
    required this.locale,
    required this.completedFiles,
    required this.totalFiles,
    required this.stage,
  });

  final int groupIndex;
  final int groupCount;
  final String folderName;
  final String locale;
  final int completedFiles;
  final int totalFiles;

  /// 사람이 읽을 수 있는 현재 단계 라벨 (예: "기존 5장 삭제 중", "3/7 업로드 중").
  final String stage;
}

/// 업로드 결과 — 성공/실패 그룹 목록.
class ScreenshotUploadResult {
  ScreenshotUploadResult({
    required this.successFileCount,
    required this.failures,
  });

  final int successFileCount;
  final List<ScreenshotUploadFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

class ScreenshotUploadFailure {
  ScreenshotUploadFailure({
    required this.folderName,
    required this.locale,
    required this.fileName,
    required this.reason,
  });

  final String folderName;
  final String locale;
  final String? fileName; // null = 그룹 단위 실패 (set 생성/삭제 등)
  final String reason;
}

/// 부모 폴더에서 스캔된 그룹들을 ASC 에 업로드.
///
/// 정책 (사용자 확인됨):
/// - 같은 (locale, displayType) 에 기존 set 이 있으면 set 안 스크린샷 전부 삭제 후 재업로드
/// - 그룹 단위로 격리: 한 그룹 실패해도 다음 그룹 진행
/// - 그룹 내 파일 실패도 격리 (그룹 중간에 멈추지 않음)
/// - 그룹 내 모든 파일 업로드 완료 시 set relationships PATCH 로 순서 명시
class ScreenshotUploader {
  ScreenshotUploader({required this.api, Dio? uploadDio})
      : _uploadDio = uploadDio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(minutes: 5),
              receiveTimeout: const Duration(minutes: 5),
            ));

  final AscApiClient api;
  final Dio _uploadDio;

  /// 한 bundle 의 모든 그룹을 순차 업로드.
  ///
  /// [localizationIdByLocale]: locale → AppStoreVersionLocalization id 매핑
  /// (호출자가 ASC fetchLocalizations 로 미리 만들어 전달).
  Future<ScreenshotUploadResult> upload({
    required Team team,
    required ParsedScreenshotBundle bundle,
    required Map<String, String> localizationIdByLocale,
    ScreenshotProgress? onProgress,
  }) async {
    final failures = <ScreenshotUploadFailure>[];
    var successCount = 0;

    for (var gi = 0; gi < bundle.groups.length; gi++) {
      final group = bundle.groups[gi];
      final vlocId = localizationIdByLocale[group.locale];
      if (vlocId == null) {
        failures.add(ScreenshotUploadFailure(
          folderName: group.folderName,
          locale: group.locale,
          fileName: null,
          reason:
              'ASC 버전에 ${group.locale} 로컬라이제이션이 없습니다. 먼저 ASC에서 추가해 주세요.',
        ));
        continue;
      }

      try {
        onProgress?.call(ScreenshotUploadProgress(
          groupIndex: gi,
          groupCount: bundle.groups.length,
          folderName: group.folderName,
          locale: group.locale,
          completedFiles: 0,
          totalFiles: group.fileCount,
          stage: 'set 조회 중',
        ));

        final setId = await _ensureSet(team, vlocId, group.displayType);

        onProgress?.call(ScreenshotUploadProgress(
          groupIndex: gi,
          groupCount: bundle.groups.length,
          folderName: group.folderName,
          locale: group.locale,
          completedFiles: 0,
          totalFiles: group.fileCount,
          stage: '기존 스크린샷 정리 중',
        ));

        final existingIds = await api.fetchScreenshotIdsInSet(team, setId);
        for (final id in existingIds) {
          try {
            await api.deleteScreenshot(team, id);
          } catch (e) {
            // 개별 삭제 실패는 기록하고 계속 (남아 있으면 reorder 단계에서 정정됨)
            failures.add(ScreenshotUploadFailure(
              folderName: group.folderName,
              locale: group.locale,
              fileName: null,
              reason: '기존 스크린샷 삭제 실패: $e',
            ));
          }
        }

        final uploadedIds = <String>[];
        for (var fi = 0; fi < group.files.length; fi++) {
          final f = group.files[fi];
          onProgress?.call(ScreenshotUploadProgress(
            groupIndex: gi,
            groupCount: bundle.groups.length,
            folderName: group.folderName,
            locale: group.locale,
            completedFiles: fi,
            totalFiles: group.fileCount,
            stage: '${fi + 1}/${group.fileCount} 업로드 중',
          ));

          try {
            final shotId = await _uploadOneFile(team, setId, f);
            uploadedIds.add(shotId);
            successCount++;
          } catch (e) {
            failures.add(ScreenshotUploadFailure(
              folderName: group.folderName,
              locale: group.locale,
              fileName: f.fileName,
              reason: e.toString(),
            ));
          }
        }

        if (uploadedIds.length >= 2) {
          try {
            await api.reorderScreenshotsInSet(team, setId, uploadedIds);
          } catch (e) {
            failures.add(ScreenshotUploadFailure(
              folderName: group.folderName,
              locale: group.locale,
              fileName: null,
              reason: '순서 재배열 실패 (이미지는 업로드됨): $e',
            ));
          }
        }

        onProgress?.call(ScreenshotUploadProgress(
          groupIndex: gi,
          groupCount: bundle.groups.length,
          folderName: group.folderName,
          locale: group.locale,
          completedFiles: uploadedIds.length,
          totalFiles: group.fileCount,
          stage: '완료',
        ));
      } catch (e) {
        failures.add(ScreenshotUploadFailure(
          folderName: group.folderName,
          locale: group.locale,
          fileName: null,
          reason: e.toString(),
        ));
      }
    }

    return ScreenshotUploadResult(
      successFileCount: successCount,
      failures: failures,
    );
  }

  /// set 이 있으면 그 id, 없으면 새로 생성한 id 반환.
  Future<String> _ensureSet(
    Team team,
    String vlocId,
    String displayType,
  ) async {
    final existing = await api.fetchScreenshotSets(
      team,
      vlocId,
      displayType: displayType,
    );
    if (existing.isNotEmpty) return existing.first.id;
    final created = await api.createScreenshotSet(team, vlocId, displayType);
    return created.id;
  }

  /// 한 파일: reserve → 멀티파트 PUT → commit. 반환값은 screenshot id.
  Future<String> _uploadOneFile(
    Team team,
    String setId,
    ScreenshotFile file,
  ) async {
    final bytes = await file.file.readAsBytes();
    final size = bytes.lengthInBytes;
    final md5Hex = md5.convert(bytes).toString();

    final reserved = await api.reserveScreenshot(
      team,
      setId,
      file.fileName,
      size,
    );

    if (reserved.uploadOperations.isEmpty) {
      throw Exception('reserve 응답에 uploadOperations 가 없음');
    }

    for (final op in reserved.uploadOperations) {
      final end = op.offset + op.length;
      if (op.offset < 0 || end > size) {
        throw Exception(
          '잘못된 byte range: offset=${op.offset}, length=${op.length}, fileSize=$size',
        );
      }
      final chunk = Uint8List.sublistView(bytes, op.offset, end);
      await _putBinary(op.url, op.requestHeaders, chunk);
    }

    await api.commitScreenshot(team, reserved.id, md5Hex);
    return reserved.id;
  }

  Future<void> _putBinary(
    String url,
    Map<String, String> headers,
    Uint8List bytes,
  ) async {
    try {
      await _uploadDio.putUri<dynamic>(
        Uri.parse(url),
        data: Stream.value(bytes),
        options: Options(
          headers: {
            ...headers,
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      );
    } on DioException catch (e) {
      throw Exception(
        'presigned PUT 실패 [${e.response?.statusCode}]: ${e.message ?? e.toString()}',
      );
    }
  }
}
