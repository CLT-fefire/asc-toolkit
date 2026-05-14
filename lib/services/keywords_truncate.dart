/// ASC 키워드 100자 제한에 맞춰 콤마 단위로 안전하게 자르는 헬퍼.
/// 부분 토큰이 생기지 않도록 콤마 경계에서만 컷한다.
String truncateKeywords(String input, int max) {
  final compact = input.replaceAll(RegExp(r'\s*,\s*'), ',').trim();
  if (compact.length <= max) return compact;
  final tokens = compact.split(',');
  final buf = StringBuffer();
  for (final t in tokens) {
    final extra = buf.isEmpty ? t.length : t.length + 1; // +1 for comma
    if (buf.length + extra > max) break;
    if (buf.isNotEmpty) buf.write(',');
    buf.write(t);
  }
  return buf.toString();
}
