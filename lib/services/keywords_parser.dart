import 'dart:convert';
import 'dart:typed_data';

import '../data/locale_keywords.dart';
import '../models/parsed_keywords.dart';

/// 플레인 텍스트 키워드 파일 파서.
///
/// 가정하는 구조 (DearU 팀 표준):
/// ```
/// 한국어
/// bubble,버블,YH,...
///
/// 영어, 베트남어, 인도네시아어
/// bubble,버블,...
///
/// 일본어
/// bubble,...
/// ```
///
/// - 빈 줄은 구분자.
/// - 헤더는 콤마(`,`) 또는 슬래시(`/`)로 다중 언어 묶기 가능.
/// - 다음 비어있지 않은 줄을 해당 헤더의 모든 로케일에 키워드로 매핑.
class KeywordsParser {
  /// 파일 바이트(UTF-8 가정) 또는 UTF-16 BOM이 있을 경우도 처리.
  ParsedKeywordsFile parseBytes(Uint8List bytes) {
    final text = _decode(bytes);
    return parseText(text);
  }

  ParsedKeywordsFile parseText(String text) {
    final lines = const LineSplitter().convert(text);
    final result = <String, String>{};
    final unknowns = <String>[];

    int i = 0;
    while (i < lines.length) {
      final headerLine = lines[i].trim();
      i++;
      if (headerLine.isEmpty) continue;

      final locales = _splitHeader(headerLine);
      if (locales.isEmpty) {
        unknowns.add(headerLine);
        continue;
      }

      // 다음 비어있지 않은 줄 = 키워드 라인.
      String? keywordsLine;
      while (i < lines.length) {
        final t = lines[i].trim();
        i++;
        if (t.isEmpty) continue;
        keywordsLine = t;
        break;
      }
      if (keywordsLine == null) break;

      for (final loc in locales) {
        result[loc] = keywordsLine;
      }
    }

    return ParsedKeywordsFile(
      keywordsByLocale: result,
      unknownHeaders: unknowns,
    );
  }

  /// 헤더 한 줄을 로케일 코드 리스트로 변환.
  /// 일부 토큰만 매핑되면 매핑된 것만 사용 (전체 실패 시 빈 리스트).
  List<String> _splitHeader(String header) {
    final tokens = header
        .split(RegExp(r'[,/、]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);
    final locales = <String>[];
    for (final tok in tokens) {
      final loc = localeFromHeader(tok);
      if (loc != null && !locales.contains(loc)) {
        locales.add(loc);
      }
    }
    return locales;
  }

  String _decode(Uint8List bytes) {
    // UTF-16 BOM 감지 (드물지만 메모장이 만들 수 있음).
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      // UTF-16 LE.
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    // UTF-8 BOM 제거 후 UTF-8 디코드.
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final lo = littleEndian ? bytes[i] : bytes[i + 1];
      final hi = littleEndian ? bytes[i + 1] : bytes[i];
      units.add((hi << 8) | lo);
    }
    return String.fromCharCodes(units);
  }
}
