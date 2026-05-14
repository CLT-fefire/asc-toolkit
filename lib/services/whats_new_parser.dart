import '../data/locale_keywords.dart';
import '../models/parsed_whats_new.dart';

/// "국: ...\n영: ...\n일: ...\n기타: ..." 형식 텍스트를 로케일별 What's New로 변환.
///
/// 항상 [availableLocales]을 함께 받아서 wildcard("기타") 채움 + 변형 매핑
/// (예: 영 → en-US가 없으면 en-GB로 fallback)을 수행한다.
class WhatsNewParser {
  /// 한 글자 짧은 prefix → 언어 family.
  /// 같은 family 안에서는 [availableLocales]에 있는 변형을 우선 선택.
  static const _shortToLang = <String, String>{
    '국': 'ko',
    '영': 'en',
    '일': 'ja',
    '중': 'zh',
    '베': 'vi',
    '인': 'id',
    '독': 'de',
    '불': 'fr',
    '서': 'es',
    '러': 'ru',
    '태': 'th',
    '아': 'ar',
    '포': 'pt',
  };

  static final _colonPattern = RegExp(r'[:：]');

  ParsedWhatsNew parse(String text, Iterable<String> availableLocales) {
    final available = availableLocales.toSet();
    final explicit = <String, String>{};
    final unknowns = <String>[];
    String? wildcardText;

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final match = _colonPattern.firstMatch(trimmed);
      if (match == null) continue; // "메타데이터" 같은 머리말 skip

      final left = trimmed.substring(0, match.start).trim();
      final right = trimmed.substring(match.end).trim();
      if (left.isEmpty || right.isEmpty) continue;

      if (_isWildcard(left)) {
        wildcardText = right;
        continue;
      }

      final locale = _bestMatch(left, available);
      if (locale == null) {
        unknowns.add(left);
        continue;
      }
      explicit[locale] = right;
    }

    final result = <String, String>{...explicit};
    if (wildcardText != null) {
      for (final loc in available) {
        result.putIfAbsent(loc, () => wildcardText!);
      }
    }

    return ParsedWhatsNew(
      whatsNewByLocale: result,
      unknownPrefixes: unknowns,
    );
  }

  bool _isWildcard(String token) {
    final t = token.toLowerCase().trim();
    return t == '기타' ||
        t == '나머지' ||
        t == '그외' ||
        t == 'etc' ||
        t == 'etc.' ||
        t == 'rest' ||
        t == 'others' ||
        t == 'default';
  }

  /// prefix를 [available] 안에서 best match locale로 변환.
  String? _bestMatch(String prefix, Set<String> available) {
    // 1. 단일 매핑 (locale_keywords.dart) 직접 적중.
    final direct = localeFromHeader(prefix);
    if (direct != null && available.contains(direct)) return direct;

    // 2. 단일 매핑은 있는데 변형 차이가 있을 경우 같은 family에서 선택.
    if (direct != null) {
      final lang = direct.split('-').first;
      final variant = _pickFromFamily(lang, available);
      if (variant != null) return variant;
    }

    // 3. 한 글자 짧은 prefix → family 직접 매핑.
    final lang = _shortToLang[prefix.trim()];
    if (lang != null) {
      final variant = _pickFromFamily(lang, available);
      if (variant != null) return variant;
    }

    // 4. prefix가 이미 ASC 코드 형태(en-US, zh-Hans 등).
    if (available.contains(prefix.trim())) return prefix.trim();

    return null;
  }

  String? _pickFromFamily(String lang, Set<String> available) {
    // 정확히 lang 매칭(예: ko, ja, vi, id)
    if (available.contains(lang)) return lang;
    // lang-* 매칭 (en-US, en-GB, zh-Hans, zh-Hant ...)
    for (final loc in available) {
      if (loc.startsWith('$lang-')) return loc;
    }
    return null;
  }
}
