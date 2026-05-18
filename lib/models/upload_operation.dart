/// ASC `appScreenshots.attributes.uploadOperations[]` 한 항목.
///
/// reserve 단계 응답에 들어있는 presigned-URL 멀티파트 업로드 디스크립터.
/// 각 op 는 원본 바이트 배열의 `[offset, offset+length)` 범위를 그대로 PUT.
class UploadOperation {
  UploadOperation({
    required this.method,
    required this.url,
    required this.offset,
    required this.length,
    required this.requestHeaders,
  });

  /// 보통 `PUT`
  final String method;

  /// presigned URL
  final String url;

  /// 원본 파일에서의 시작 byte
  final int offset;

  /// 이 op 가 책임지는 byte 수
  final int length;

  /// 헤더 배열. ASC는 `{name, value}` 형식으로 줌.
  final Map<String, String> requestHeaders;

  factory UploadOperation.fromAscJson(Map<String, dynamic> json) {
    final headers = <String, String>{};
    final rawHeaders = json['requestHeaders'];
    if (rawHeaders is List) {
      for (final h in rawHeaders) {
        if (h is Map<String, dynamic>) {
          final name = h['name'] as String?;
          final value = h['value'] as String?;
          if (name != null && value != null) {
            headers[name] = value;
          }
        }
      }
    }
    return UploadOperation(
      method: (json['method'] as String?) ?? 'PUT',
      url: json['url'] as String? ?? '',
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      length: (json['length'] as num?)?.toInt() ?? 0,
      requestHeaders: headers,
    );
  }
}
