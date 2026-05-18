import 'upload_operation.dart';

/// ASC `appScreenshots` — 개별 스크린샷 이미지.
///
/// 한 set 안에 여러 개. reserve(POST) 응답 시 `uploadOperations` 가 채워져 있고,
/// commit(PATCH `uploaded:true`) 이후엔 `assetDeliveryState` 가 `COMPLETE` 로 전환된다.
class AppScreenshot {
  AppScreenshot({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.uploadOperations,
    required this.uploaded,
  });

  final String id;
  final String fileName;
  final int fileSize;
  final List<UploadOperation> uploadOperations;
  final bool uploaded;

  factory AppScreenshot.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    final ops = <UploadOperation>[];
    final rawOps = attrs['uploadOperations'];
    if (rawOps is List) {
      for (final o in rawOps) {
        if (o is Map<String, dynamic>) {
          ops.add(UploadOperation.fromAscJson(o));
        }
      }
    }
    return AppScreenshot(
      id: json['id'] as String,
      fileName: (attrs['fileName'] as String?) ?? '',
      fileSize: (attrs['fileSize'] as num?)?.toInt() ?? 0,
      uploadOperations: ops,
      uploaded: (attrs['uploaded'] as bool?) ?? false,
    );
  }
}
