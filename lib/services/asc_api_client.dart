import 'package:dio/dio.dart';

import '../models/app_category.dart';
import '../models/app_info.dart';
import '../models/app_info_localization.dart';
import '../models/app_notification_config.dart';
import '../models/app_screenshot.dart';
import '../models/app_screenshot_set.dart';
import '../models/app_store_review_detail.dart';
import '../models/app_store_version.dart';
import '../models/app_store_version_localization.dart';
import '../models/app_summary.dart';
import '../models/team.dart';
import 'jwt_signer.dart';
import 'team_repository.dart';

class AscApiException implements Exception {
  AscApiException(
    this.message, {
    this.statusCode,
    this.detail,
    this.method,
    this.path,
  });
  final String message;
  final int? statusCode;
  final String? detail;
  final String? method;
  final String? path;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' [HTTP $statusCode]';
    final where = (method == null || path == null) ? '' : '\n  → $method $path';
    final extra = detail == null || detail!.isEmpty ? '' : '\n$detail';
    return 'AscApiException$code: $message$where$extra';
  }
}

class AscApiClient {
  AscApiClient({
    required this.repository,
    JwtSigner? signer,
    Dio? dio,
  })  : _signer = signer ?? JwtSigner(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.appstoreconnect.apple.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              contentType: 'application/json',
              responseType: ResponseType.json,
            ));

  final TeamRepository repository;
  final JwtSigner _signer;
  final Dio _dio;

  Future<Map<String, String>> _authHeader(Team team) async {
    final p8 = await repository.readP8(team.id);
    if (p8 == null || p8.isEmpty) {
      throw AscApiException('.p8 키가 저장되어 있지 않습니다');
    }
    final token = _signer.sign(
      issuerId: team.issuerId,
      keyId: team.keyId,
      p8Pem: p8,
    );
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<AppSummary>> fetchApps(Team team) async {
    final headers = await _authHeader(team);

    final results = <AppSummary>[];
    String path = '/v1/apps';
    Map<String, dynamic>? query = {
      'limit': 200,
      'fields[apps]': 'name,bundleId,sku,primaryLocale',
    };

    while (true) {
      final body = await _getJson(path, query: query, headers: headers);
      final data = (body['data'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(AppSummary.fromAscJson);
      results.addAll(data);

      final next = ((body['links'] as Map<String, dynamic>?)?['next']) as String?;
      if (next == null || next.isEmpty) break;
      final nextUri = Uri.parse(next);
      path = nextUri.path;
      query = nextUri.queryParameters;
    }

    return results;
  }

  Future<List<AppStoreVersion>> fetchVersions(Team team, String appId) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/apps/$appId/appStoreVersions',
      query: const {
        'limit': 50,
        'fields[appStoreVersions]': 'versionString,platform,appStoreState',
      },
      headers: headers,
    );
    return (body['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AppStoreVersion.fromAscJson)
        .toList(growable: false);
  }

  Future<List<AppStoreVersionLocalization>> fetchLocalizations(
    Team team,
    String versionId,
  ) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/appStoreVersions/$versionId/appStoreVersionLocalizations',
      query: const {
        'limit': 50,
        'fields[appStoreVersionLocalizations]':
            'locale,whatsNew,description,keywords,promotionalText,supportUrl,marketingUrl',
      },
      headers: headers,
    );
    return (body['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AppStoreVersionLocalization.fromAscJson)
        .toList(growable: false);
  }

  /// 단일 필드 변경용 편의 메서드. 내부적으로 [updateLocalizationFields] 호출.
  Future<AppStoreVersionLocalization> updateWhatsNew(
    Team team,
    String localizationId,
    String whatsNew,
  ) =>
      updateLocalizationFields(team, localizationId, {'whatsNew': whatsNew});

  /// 여러 필드를 한 번의 PATCH로 갱신.
  ///
  /// [attributes]는 비어 있지 않아야 함 (호출자가 변경 감지 후 호출).
  ///
  /// 허용 필드 (ASC `appStoreVersionLocalizations`):
  /// - whatsNew (max 4000)
  /// - description (max 4000)
  /// - keywords (max 100, 콤마 구분)
  /// - promotionalText (max 170)
  /// - supportUrl (URL)
  /// - marketingUrl (URL, optional)
  Future<AppStoreVersionLocalization> updateLocalizationFields(
    Team team,
    String localizationId,
    Map<String, String?> attributes,
  ) async {
    assert(attributes.isNotEmpty, 'updateLocalizationFields: 빈 변경 호출 불가');
    final headers = await _authHeader(team);
    final body = await _patchJson(
      '/v1/appStoreVersionLocalizations/$localizationId',
      headers: headers,
      payload: {
        'data': {
          'type': 'appStoreVersionLocalizations',
          'id': localizationId,
          'attributes': attributes,
        }
      },
    );
    final data = body['data'] as Map<String, dynamic>;
    return AppStoreVersionLocalization.fromAscJson(data);
  }

  // ---- App Info (B.2 이름/부제 + B.3 카테고리) ----

  Future<List<AppInfo>> fetchAppInfos(Team team, String appId) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/apps/$appId/appInfos',
      query: const {
        'limit': 50,
        'include': 'primaryCategory,secondaryCategory',
        // state(신)와 appStoreState(구) 둘 다 요청 — 모델에서 fallback 처리
        'fields[appInfos]':
            'state,appStoreState,primaryCategory,secondaryCategory',
      },
      headers: headers,
    );
    return (body['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AppInfo.fromAscJson)
        .toList(growable: false);
  }

  Future<List<AppInfoLocalization>> fetchAppInfoLocalizations(
    Team team,
    String appInfoId,
  ) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/appInfos/$appInfoId/appInfoLocalizations',
      query: const {
        'limit': 50,
        'fields[appInfoLocalizations]':
            'locale,name,subtitle,privacyPolicyUrl,privacyPolicyText',
      },
      headers: headers,
    );
    return (body['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AppInfoLocalization.fromAscJson)
        .toList(growable: false);
  }

  /// 이름·부제 등 로케일별 필드 PATCH.
  ///
  /// 허용 필드 (ASC `appInfoLocalizations`):
  /// - name (max 30)
  /// - subtitle (max 30)
  /// - privacyPolicyUrl (URL)
  /// - privacyPolicyText (max 1000)
  Future<AppInfoLocalization> updateAppInfoLocalizationFields(
    Team team,
    String localizationId,
    Map<String, String?> attributes,
  ) async {
    assert(attributes.isNotEmpty,
        'updateAppInfoLocalizationFields: 빈 변경 호출 불가');
    final headers = await _authHeader(team);
    final body = await _patchJson(
      '/v1/appInfoLocalizations/$localizationId',
      headers: headers,
      payload: {
        'data': {
          'type': 'appInfoLocalizations',
          'id': localizationId,
          'attributes': attributes,
        }
      },
    );
    return AppInfoLocalization.fromAscJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  /// iOS 플랫폼의 모든 카테고리. 트리 구성용으로 사용 (parent ↔ children).
  Future<List<AppCategory>> fetchCategories(
    Team team, {
    String platform = 'IOS',
  }) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/appCategories',
      query: {
        'filter[platforms]': platform,
        'limit': 200,
        'include': 'parent',
        'fields[appCategories]': 'platforms,parent',
      },
      headers: headers,
    );
    return (body['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AppCategory.fromAscJson)
        .toList(growable: false);
  }

  /// 카테고리 변경. relationships PATCH (attributes 없음).
  /// [primaryCategoryId]는 필수. [secondaryCategoryId]는 null 가능 (제거).
  Future<void> updateAppInfoCategories(
    Team team,
    String appInfoId, {
    required String primaryCategoryId,
    String? secondaryCategoryId,
  }) async {
    final headers = await _authHeader(team);
    final relationships = <String, dynamic>{
      'primaryCategory': {
        'data': {'type': 'appCategories', 'id': primaryCategoryId},
      },
      'secondaryCategory': {
        'data': secondaryCategoryId == null
            ? null
            : {'type': 'appCategories', 'id': secondaryCategoryId},
      },
    };
    await _patchJson(
      '/v1/appInfos/$appInfoId',
      headers: headers,
      payload: {
        'data': {
          'type': 'appInfos',
          'id': appInfoId,
          'relationships': relationships,
        }
      },
    );
  }

  // ---- App Store Server Notifications V2 ----

  /// 앱의 알림 URL 설정 (production + sandbox).
  Future<AppNotificationConfig> fetchAppNotificationConfig(
    Team team,
    String appId,
  ) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/apps/$appId',
      query: const {
        'fields[apps]': 'subscriptionStatusUrl,subscriptionStatusUrlVersion,'
            'subscriptionStatusUrlForSandbox,'
            'subscriptionStatusUrlVersionForSandbox',
      },
      headers: headers,
    );
    return AppNotificationConfig.fromAscJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  /// 알림 URL/Version PATCH. [attributes]에 변경된 필드만 포함.
  Future<AppNotificationConfig> updateAppNotificationConfig(
    Team team,
    String appId,
    Map<String, String?> attributes,
  ) async {
    assert(attributes.isNotEmpty,
        'updateAppNotificationConfig: 빈 변경 호출 불가');
    final headers = await _authHeader(team);
    final body = await _patchJson(
      '/v1/apps/$appId',
      headers: headers,
      payload: {
        'data': {
          'type': 'apps',
          'id': appId,
          'attributes': attributes,
        }
      },
    );
    return AppNotificationConfig.fromAscJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  // ---- App Store Review Detail (B.4) ----

  /// 버전별 심사 정보 1개. 없을 수 있음 (null).
  Future<AppStoreReviewDetail?> fetchReviewDetail(
    Team team,
    String versionId,
  ) async {
    final headers = await _authHeader(team);
    try {
      final body = await _getJson(
        '/v1/appStoreVersions/$versionId/appStoreReviewDetail',
        query: const {
          'fields[appStoreReviewDetails]':
              'contactFirstName,contactLastName,contactPhone,contactEmail,'
              'demoAccountName,demoAccountPassword,demoAccountRequired,notes',
        },
        headers: headers,
      );
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      return AppStoreReviewDetail.fromAscJson(data);
    } on AscApiException catch (e) {
      // 심사 정보가 아직 생성되지 않은 경우 ASC가 404로 응답할 수 있음
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 심사 정보 PATCH. 일부 필드는 bool([demoAccountRequired])이라 dynamic 타입.
  Future<AppStoreReviewDetail> updateReviewDetailFields(
    Team team,
    String reviewDetailId,
    Map<String, dynamic> attributes,
  ) async {
    assert(attributes.isNotEmpty, 'updateReviewDetailFields: 빈 변경 호출 불가');
    final headers = await _authHeader(team);
    final body = await _patchJson(
      '/v1/appStoreReviewDetails/$reviewDetailId',
      headers: headers,
      payload: {
        'data': {
          'type': 'appStoreReviewDetails',
          'id': reviewDetailId,
          'attributes': attributes,
        }
      },
    );
    return AppStoreReviewDetail.fromAscJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  // ---- 스크린샷 (옵션 D) ----

  /// 한 [vlocId] 의 [displayType] set 목록. 보통 0 또는 1개.
  Future<List<AppScreenshotSet>> fetchScreenshotSets(
    Team team,
    String vlocId, {
    String? displayType,
  }) async {
    final headers = await _authHeader(team);
    final query = <String, dynamic>{
      'limit': 50,
      'fields[appScreenshotSets]': 'screenshotDisplayType',
    };
    if (displayType != null) {
      query['filter[screenshotDisplayType]'] = displayType;
    }
    final body = await _getJson(
      '/v1/appStoreVersionLocalizations/$vlocId/appScreenshotSets',
      query: query,
      headers: headers,
    );
    return (body['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AppScreenshotSet.fromAscJson)
        .toList(growable: false);
  }

  /// 해당 vlocId·displayType 의 set 을 새로 생성.
  Future<AppScreenshotSet> createScreenshotSet(
    Team team,
    String vlocId,
    String displayType,
  ) async {
    final headers = await _authHeader(team);
    final body = await _postJson(
      '/v1/appScreenshotSets',
      headers: headers,
      payload: {
        'data': {
          'type': 'appScreenshotSets',
          'attributes': {'screenshotDisplayType': displayType},
          'relationships': {
            'appStoreVersionLocalization': {
              'data': {
                'type': 'appStoreVersionLocalizations',
                'id': vlocId,
              }
            }
          },
        }
      },
    );
    return AppScreenshotSet.fromAscJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  /// set 안의 스크린샷 id 목록 (삭제 또는 reorder 용).
  Future<List<String>> fetchScreenshotIdsInSet(
    Team team,
    String setId,
  ) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/appScreenshotSets/$setId/appScreenshots',
      query: const {
        'limit': 50,
        'fields[appScreenshots]': 'fileName',
      },
      headers: headers,
    );
    return (body['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((j) => j['id'] as String)
        .toList(growable: false);
  }

  /// 개별 스크린샷 삭제.
  Future<void> deleteScreenshot(Team team, String screenshotId) async {
    final headers = await _authHeader(team);
    await _deleteJson(
      '/v1/appScreenshots/$screenshotId',
      headers: headers,
    );
  }

  /// reserve: 업로드 op 목록을 받음. PUT/commit 은 호출자가 처리.
  Future<AppScreenshot> reserveScreenshot(
    Team team,
    String setId,
    String fileName,
    int fileSize,
  ) async {
    final headers = await _authHeader(team);
    final body = await _postJson(
      '/v1/appScreenshots',
      headers: headers,
      payload: {
        'data': {
          'type': 'appScreenshots',
          'attributes': {
            'fileName': fileName,
            'fileSize': fileSize,
          },
          'relationships': {
            'appScreenshotSet': {
              'data': {'type': 'appScreenshotSets', 'id': setId}
            }
          },
        }
      },
    );
    return AppScreenshot.fromAscJson(
      body['data'] as Map<String, dynamic>,
    );
  }

  /// commit: PUT 완료 후 `uploaded:true` + md5 체크섬 PATCH.
  Future<void> commitScreenshot(
    Team team,
    String screenshotId,
    String md5HexChecksum,
  ) async {
    final headers = await _authHeader(team);
    await _patchJson(
      '/v1/appScreenshots/$screenshotId',
      headers: headers,
      payload: {
        'data': {
          'type': 'appScreenshots',
          'id': screenshotId,
          'attributes': {
            'uploaded': true,
            'sourceFileChecksum': md5HexChecksum,
          },
        }
      },
    );
  }

  /// commit 직후 ASC 가 데이터를 정상 수신했는지 확인.
  ///
  /// 반환 값은 ASC `assetDeliveryState.state` ─ 대표 값:
  /// - `AWAITING_UPLOAD`: PUT 미수신 (= 사실상 실패)
  /// - `UPLOAD_COMPLETE`: PUT 수신, ASC 처리 대기
  /// - `COMPLETE`: 사용 가능
  /// - `FAILED`: ASC 처리 실패
  Future<String> fetchScreenshotDeliveryState(
    Team team,
    String screenshotId,
  ) async {
    final headers = await _authHeader(team);
    final body = await _getJson(
      '/v1/appScreenshots/$screenshotId',
      query: const {'fields[appScreenshots]': 'assetDeliveryState'},
      headers: headers,
    );
    final data = body['data'] as Map<String, dynamic>?;
    final attrs = (data?['attributes'] as Map<String, dynamic>?) ?? const {};
    final asset = attrs['assetDeliveryState'];
    if (asset is Map<String, dynamic>) {
      return (asset['state'] as String?) ?? '';
    }
    return '';
  }

  /// set 안 스크린샷 순서 명시. ASC 자동 정렬 안전망.
  Future<void> reorderScreenshotsInSet(
    Team team,
    String setId,
    List<String> orderedIds,
  ) async {
    final headers = await _authHeader(team);
    await _patchJson(
      '/v1/appScreenshotSets/$setId/relationships/appScreenshots',
      headers: headers,
      payload: {
        'data': [
          for (final id in orderedIds)
            {'type': 'appScreenshots', 'id': id},
        ],
      },
    );
  }

  // ---- 내부 헬퍼 ----

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic>? query,
    required Map<String, String> headers,
  }) async {
    try {
      final res = await _dio.getUri<Map<String, dynamic>>(
        Uri.parse(_dio.options.baseUrl + path).replace(
          queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
        ),
        options: Options(headers: headers),
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _toAscException(e, method: 'GET', path: path);
    }
  }

  Future<Map<String, dynamic>> _patchJson(
    String path, {
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final res = await _dio.patchUri<Map<String, dynamic>>(
        Uri.parse(_dio.options.baseUrl + path),
        data: payload,
        options: Options(headers: headers),
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _toAscException(e, method: 'PATCH', path: path);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final res = await _dio.postUri<Map<String, dynamic>>(
        Uri.parse(_dio.options.baseUrl + path),
        data: payload,
        options: Options(headers: headers),
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _toAscException(e, method: 'POST', path: path);
    }
  }

  Future<void> _deleteJson(
    String path, {
    required Map<String, String> headers,
  }) async {
    try {
      await _dio.deleteUri<dynamic>(
        Uri.parse(_dio.options.baseUrl + path),
        options: Options(headers: headers),
      );
    } on DioException catch (e) {
      throw _toAscException(e, method: 'DELETE', path: path);
    }
  }

  AscApiException _toAscException(
    DioException e, {
    String? method,
    String? path,
  }) {
    final res = e.response;
    final status = res?.statusCode;
    final raw = res?.data;
    String? detail;
    if (raw is Map && raw['errors'] is List && (raw['errors'] as List).isNotEmpty) {
      final first = (raw['errors'] as List).first as Map<String, dynamic>;
      detail = [first['title'], first['detail']].whereType<String>().join(' — ');
    } else if (raw != null) {
      detail = raw.toString();
    }
    return AscApiException(
      e.message ?? 'App Store Connect API 호출 실패',
      statusCode: status,
      detail: detail,
      method: method,
      path: path,
    );
  }
}
