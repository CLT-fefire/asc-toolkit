import 'package:dio/dio.dart';

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
