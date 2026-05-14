import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../data/locale_keywords.dart';
import '../models/parsed_docx.dart';

/// `.docx` 파일(=zip + XML)을 ASC 메타데이터로 파싱.
///
/// 가정하는 문서 구조 (DearU 팀 표준):
/// ```
/// 한국어                       ← 언어 헤더
/// bubble for YH: 최애와...     ← "이름: 부제"
/// 프로모션 후보 줄들           ← 옵션
/// --------------               ← 구분선 (8자 이상 dash)
/// [서비스 소개] ...            ← 설명 본문
/// ...
/// 영어                          ← 다음 언어
/// bubble for YH: Private...
/// ...
/// ```
class DocxParser {
  /// 부제·이름 분리 시 사용. 일부 언어는 콜론을 빼고 공백으로 구분할 수도 있어
  /// 양쪽 모두 시도. 안전한 fallback은 이름 후보 prefix("bubble for ...") 기준.
  static const _colonSeparators = [':', ':']; // ASCII + 전각

  /// 본문 구분선 매칭. 5자 이상 dash 연속.
  static final _dividerPattern = RegExp(r'^[-—–]{5,}$');

  /// 파싱 진입점. .docx 바이트를 받아 [ParsedDocx] 반환.
  ParsedDocx parse(Uint8List bytes) {
    final paragraphs = _extractParagraphs(bytes);
    return _parseParagraphs(paragraphs);
  }

  // ---- .docx → 줄(paragraph) 리스트 ----

  List<String> _extractParagraphs(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () =>
          throw const FormatException('잘못된 .docx — word/document.xml 없음'),
    );
    final raw = entry.content as List<int>;
    final xmlStr = utf8.decode(raw);
    final doc = XmlDocument.parse(xmlStr);

    final paragraphs = <String>[];
    for (final p in doc.descendantElements
        .where((e) => e.name.local == 'p')) {
      final buf = StringBuffer();
      for (final node in p.descendants) {
        if (node is XmlElement && node.name.local == 't') {
          buf.write(node.innerText);
        } else if (node is XmlElement && node.name.local == 'br') {
          buf.write('\n');
        } else if (node is XmlElement && node.name.local == 'tab') {
          buf.write('\t');
        }
      }
      paragraphs.add(buf.toString());
    }
    return paragraphs;
  }

  // ---- 줄 리스트 → ParsedDocx ----

  ParsedDocx _parseParagraphs(List<String> paragraphs) {
    final sections = <String, ParsedLocaleSection>{};
    final unknowns = <String>[];

    // 1차: 언어 헤더 인덱스 식별.
    final markers = <_LangMarker>[];
    for (var i = 0; i < paragraphs.length; i++) {
      final line = paragraphs[i].trim();
      if (line.isEmpty) continue;
      final locale = localeFromHeader(line);
      if (locale != null) {
        markers.add(_LangMarker(
          index: i,
          header: line,
          locale: locale,
        ));
      }
    }

    if (markers.isEmpty) {
      return ParsedDocx(sections: {}, unknownHeaders: const []);
    }

    // 2차: 각 마커마다 다음 마커 직전까지의 범위를 한 섹션으로.
    for (var m = 0; m < markers.length; m++) {
      final marker = markers[m];
      final endIdx =
          m + 1 < markers.length ? markers[m + 1].index : paragraphs.length;
      final lines = paragraphs.sublist(marker.index + 1, endIdx);
      final section = _parseSection(
        locale: marker.locale,
        headerKeyword: marker.header,
        lines: lines,
      );
      sections[marker.locale] = section;
    }

    // 알려지지 않은 헤더 라인 (단독 라인 + 매핑 없음 + 영문/한글 시작)도 별도 수집.
    // 실제로 매핑 없는 케이스가 드물어 단순 휴리스틱만.
    for (final line in paragraphs) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (markers.any((m) => m.header == t)) continue;
      // 짧은 라인 + 한국어 "～어" 또는 영어 capitalized name 패턴이면 후보
      if (t.length <= 15 &&
          (t.endsWith('어') || RegExp(r'^[A-Z][a-zA-Z ]+$').hasMatch(t)) &&
          localeFromHeader(t) == null) {
        unknowns.add(t);
      }
    }

    return ParsedDocx(
      sections: sections,
      unknownHeaders: unknowns,
    );
  }

  ParsedLocaleSection _parseSection({
    required String locale,
    required String headerKeyword,
    required List<String> lines,
  }) {
    String? name;
    String? subtitle;
    String? promotionalText;
    String? description;

    // 1. 첫 비어있지 않은 라인 → "이름: 부제"
    var idx = 0;
    while (idx < lines.length && lines[idx].trim().isEmpty) {
      idx++;
    }
    if (idx < lines.length) {
      final headerLine = lines[idx].trim();
      final parsed = _splitNameSubtitle(headerLine);
      name = parsed.$1;
      subtitle = parsed.$2;
      idx++;
    }

    // 2. 구분선 이전까지 → 프로모션 텍스트 후보
    final promoBuf = <String>[];
    while (idx < lines.length) {
      final t = lines[idx].trim();
      if (_dividerPattern.hasMatch(t)) {
        idx++; // 구분선 자체 건너뜀
        break;
      }
      if (t.isNotEmpty) promoBuf.add(t);
      idx++;
    }
    if (promoBuf.isNotEmpty) {
      promotionalText = promoBuf.join(' ');
    }

    // 3. 구분선 이후 끝까지 → 설명 (paragraph 단위 줄바꿈 유지)
    if (idx < lines.length) {
      final descLines = lines.sublist(idx).map((l) => l.trimRight()).toList();
      // 양 끝 공백 줄 제거
      while (descLines.isNotEmpty && descLines.first.trim().isEmpty) {
        descLines.removeAt(0);
      }
      while (descLines.isNotEmpty && descLines.last.trim().isEmpty) {
        descLines.removeLast();
      }
      if (descLines.isNotEmpty) {
        description = descLines.join('\n');
      }
    }

    return ParsedLocaleSection(
      locale: locale,
      headerKeyword: headerKeyword,
      name: name,
      subtitle: subtitle,
      promotionalText: promotionalText,
      description: description,
    );
  }

  /// "이름: 부제" → (이름, 부제).
  /// 콜론이 없으면 전체를 이름으로 처리 (부제는 null).
  (String, String?) _splitNameSubtitle(String line) {
    for (final sep in _colonSeparators) {
      final idx = line.indexOf(sep);
      if (idx > 0) {
        final name = line.substring(0, idx).trim();
        final subtitle = line.substring(idx + sep.length).trim();
        return (name, subtitle.isEmpty ? null : subtitle);
      }
    }
    return (line.trim(), null);
  }
}

class _LangMarker {
  _LangMarker({
    required this.index,
    required this.header,
    required this.locale,
  });
  final int index;
  final String header;
  final String locale;
}
