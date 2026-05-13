import 'package:dio/dio.dart';

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

  Future<List<AppSummary>> fetchApps(Team team) async {
    final p8 = await repository.readP8(team.id);
    if (p8 == null || p8.isEmpty) {
      throw AscApiException('.p8 키가 저장되어 있지 않습니다');
    }
    final token = _signer.sign(
      issuerId: team.issuerId,
      keyId: team.keyId,
      p8Pem: p8,
    );

    final results = <AppSummary>[];
    String path = '/v1/apps';
    Map<String, dynamic>? query = {
      'limit': 200,
      'fields[apps]': 'name,bundleId,sku,primaryLocale',
    };

    while (true) {
      final Response<Map<String, dynamic>> res;
      try {
        res = await _dio.getUri<Map<String, dynamic>>(
          Uri.parse(_dio.options.baseUrl + path).replace(
            queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
          ),
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } on DioException catch (e) {
        throw _toAscException(e);
      }

      final body = res.data ?? const {};
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
