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

/// `assetDeliveryState` 폴링 결과.
class _DeliveryResult {
  _DeliveryResult(this.state, this.errors);
  final String state;
  final List<dynamic> errors;
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

  bool _cancelled = false;

  /// 진행 중인 업로드를 graceful 중단 요청.
  ///
  /// 이미 ASC 로 보낸 reserve/PUT/commit/폴링은 끝까지 진행되지만, 다음 파일·다음 그룹은
  /// 시작되지 않는다. 중단된 파일/그룹은 `ScreenshotUploadFailure(reason: "사용자가 업로드를 중단")`
  /// 로 결과에 포함되어 호출자가 부분 결과를 확인할 수 있다.
  void cancel() {
    _cancelled = true;
  }

  bool get isCancelled => _cancelled;

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

      // 그룹 시작 전 취소 확인: 중단 후의 모든 그룹·파일은 failures 로 기록해 사용자가
      // 어디까지 진행됐는지 결과 다이얼로그에서 확인 가능.
      if (_cancelled) {
        for (final f in group.files) {
          failures.add(ScreenshotUploadFailure(
            folderName: group.folderName,
            locale: group.locale,
            fileName: f.fileName,
            reason: '사용자가 업로드를 중단함 (시작 전)',
          ));
        }
        continue;
      }

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

          // 다음 파일 시작 전 취소 확인. 현재 그룹의 남은 파일과 다음 그룹은
          // failures 로 기록 (현재 진행 중인 파일까지는 위 try 안에서 자연 종료).
          if (_cancelled) {
            for (final remaining in group.files.skip(fi)) {
              failures.add(ScreenshotUploadFailure(
                folderName: group.folderName,
                locale: group.locale,
                fileName: remaining.fileName,
                reason: '사용자가 업로드를 중단함',
              ));
            }
            break;
          }

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
  ///
  /// ⚠️ ASC API 의 `filter[screenshotDisplayType]` 가 실측 상 무시되어 vloc 전체 set 을
  /// 돌려준다. existing.first 를 그대로 쓰면 displayType 이 다른 set 에 등록 시도하다
  /// IMAGE_INCORRECT_DIMENSIONS 로 거부됨. 따라서 클라이언트에서 명시적 매칭.
  Future<String> _ensureSet(
    Team team,
    String vlocId,
    String displayType,
  ) async {
    final allSets = await api.fetchScreenshotSets(team, vlocId);
    final matched =
        allSets.where((s) => s.screenshotDisplayType == displayType).toList();
    if (matched.isNotEmpty) return matched.first.id;
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

    // commit 만으로는 ASC 가 데이터를 정상 수신했는지 알 수 없음.
    // assetDeliveryState 가 AWAITING_UPLOAD/FAILED 면 사용자에게 친화적 사유로 throw.
    final delivery = await _confirmDelivery(team, reserved.id);
    if (delivery.state == 'AWAITING_UPLOAD' || delivery.state == 'FAILED') {
      throw Exception(_friendlyDeliveryError(delivery));
    }

    return reserved.id;
  }

  /// commit 직후 ASC 처리 결과를 폴링.
  ///
  /// ASC 는 commit(uploaded:true) 후 비동기로 이미지 검증(해상도/포맷/사이즈 등)을 수행.
  /// 결과로 `assetDeliveryState.state` 가:
  /// - `UPLOAD_COMPLETE`: byte 수신, 검증 대기 (폴링 계속)
  /// - `COMPLETE`: 검증 통과, ASC 웹에 노출됨
  /// - `FAILED`: 검증 거부 (`errors[]` 에 사유)
  /// 로 전환된다. 최대 12초간 1초 간격 폴링.
  Future<_DeliveryResult> _confirmDelivery(
    Team team,
    String screenshotId,
  ) async {
    String lastState = '';
    List<dynamic> lastErrors = const [];
    for (var attempt = 0; attempt < 12; attempt++) {
      // 사용자가 중단했으면 폴링도 즉시 종료. 현재까지 본 state 를 그대로 반환.
      if (_cancelled) return _DeliveryResult(lastState, lastErrors);
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      try {
        final attrs = await api.fetchScreenshotAttributes(team, screenshotId);
        final asset = attrs['assetDeliveryState'];
        if (asset is Map<String, dynamic>) {
          lastState = (asset['state'] as String?) ?? '';
          final errs = asset['errors'];
          lastErrors = (errs is List) ? errs : const [];
        }
        if (lastState == 'COMPLETE' || lastState == 'FAILED') {
          return _DeliveryResult(lastState, lastErrors);
        }
        // PUT 미수신이 1초 후에도 그대로면 진짜 미도달.
        if (lastState == 'AWAITING_UPLOAD' && attempt >= 1) {
          return _DeliveryResult(lastState, lastErrors);
        }
      } catch (_) {
        // 일시적 GET 실패는 다음 시도로 넘어감.
      }
    }
    return _DeliveryResult(lastState, lastErrors);
  }

  Future<void> _putBinary(
    String url,
    Map<String, String> headers,
    Uint8List bytes,
  ) async {
    try {
      final res = await _uploadDio.putUri<dynamic>(
        Uri.parse(url),
        // Uint8List 를 직접 전달해야 dio 가 contentLength/body 를 일관되게 보냄.
        // Stream.value(bytes) 로 보내면 일부 dio 버전에서 chunked 와 명시적 contentLength
        // 가 충돌해 빈 body 가 가는 사례가 있음 (옵션 D 첫 검증에서 모든 파일이 코드 흐름은
        // 통과했지만 ASC 에 데이터 미도달).
        data: bytes,
        options: Options(
          headers: headers,
          // 명시 — 일부 S3 호환 백엔드는 missing length 시 0 bytes 로 처리.
          contentType: headers['Content-Type'] ?? 'application/octet-stream',
          responseType: ResponseType.plain,
          // 2xx 외엔 throw.
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw Exception('presigned PUT 실패: HTTP $status');
      }
    } on DioException catch (e) {
      throw Exception(
        'presigned PUT 실패 [${e.response?.statusCode}]: ${e.message ?? e.toString()}',
      );
    }
  }
}

/// ASC `assetDeliveryState` 거부 사유 → 사용자가 행동 가능한 한 줄 메시지.
String _friendlyDeliveryError(_DeliveryResult delivery) {
  if (delivery.state == 'AWAITING_UPLOAD') {
    return 'ASC 가 이미지 데이터를 수신하지 못함 '
        '(presigned PUT 단계 네트워크/전송 실패 가능성)';
  }
  String? code;
  if (delivery.errors.isNotEmpty && delivery.errors.first is Map) {
    code = (delivery.errors.first as Map)['code']?.toString();
  }
  switch (code) {
    case 'IMAGE_INCORRECT_DIMENSIONS':
      return '이미지 해상도가 ASC displayType 의 허용 범위 밖. '
          '(예: 6.9" 1320×2868 자산은 APP_IPHONE_67 카테고리로 들어가야 함)';
    case 'IMAGE_DELIVERY_FAILED':
      return 'ASC 이미지 처리 실패. 잠시 후 재시도하거나 ASC 상태 확인.';
    case null:
      return 'ASC 처리 실패 (state=${delivery.state})';
    default:
      return 'ASC 거부: $code';
  }
}
