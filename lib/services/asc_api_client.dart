import 'package:dio/dio.dart';

import '../models/app_store_version.dart';
import '../models/app_store_version_localization.dart';
import '../models/app_summary.dart';
import '../models/team.dart';
import 'jwt_signer.dart';
import 'team_repository.dart';

class AscApiException implements Exception {
  AscApiException(this.message, {this.statusCode, this.detail});
  final String message;
  final int? statusCode;
  final String? detail;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' [HTTP $statusCode]';
    final extra = detail == null || detail!.isEmpty ? '' : '\n$detail';
    return 'AscApiException$code: $message$extra';
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

  Future<AppStoreVersionLocalization> updateWhatsNew(
    Team team,
    String localizationId,
    String whatsNew,
  ) async {
    final headers = await _authHeader(team);
    final body = await _patchJson(
      '/v1/appStoreVersionLocalizations/$localizationId',
      headers: headers,
      payload: {
        'data': {
          'type': 'appStoreVersionLocalizations',
          'id': localizationId,
          'attributes': {'whatsNew': whatsNew},
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
      throw _toAscException(e);
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
      throw _toAscException(e);
    }
  }

  AscApiException _toAscException(DioException e) {
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
    );
  }
}
