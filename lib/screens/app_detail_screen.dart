import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_category.dart';
import '../models/app_info.dart';
import '../models/app_info_localization.dart';
import '../models/app_notification_config.dart';
import '../models/app_store_review_detail.dart';
import '../models/app_store_version.dart';
import '../models/app_store_version_localization.dart';
import '../models/app_summary.dart';
import '../models/parsed_docx.dart';
import '../models/parsed_keywords.dart';
import '../models/parsed_whats_new.dart';
import '../models/team.dart';
import '../services/asc_api_client.dart';
import '../services/docx_parser.dart';
import '../services/keywords_parser.dart';
import '../services/keywords_truncate.dart';
import '../services/team_repository.dart';
import '../services/whats_new_parser.dart';
import 'app_detail/app_info_section.dart';
import 'app_detail/notification_config_section.dart';
import 'app_detail/review_detail_section.dart';
import 'app_detail/section_widgets.dart';
import 'app_detail/version_localization_section.dart';

class AppDetailScreen extends StatefulWidget {
  const AppDetailScreen({
    super.key,
    required this.team,
    required this.app,
    required this.repository,
  });

  final Team team;
  final AppSummary app;
  final TeamRepository repository;

  @override
  State<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends State<AppDetailScreen> {
  late final AscApiClient _client =
      AscApiClient(repository: widget.repository);
  final DocxParser _docxParser = DocxParser();
  final KeywordsParser _keywordsParser = KeywordsParser();
  final WhatsNewParser _whatsNewParser = WhatsNewParser();

  // 워드 파싱 결과 (로케일별 섹션)
  ParsedDocx? _parsedDocx;
  String? _docxFileName;

  // 키워드 텍스트 파싱 결과 (로케일별 키워드)
  ParsedKeywordsFile? _parsedKeywords;
  String? _keywordsFileName;

  // What's New 텍스트 파싱 결과 (로케일별 텍스트)
  ParsedWhatsNew? _parsedWhatsNew;
  String? _whatsNewRawText;

  bool _applyingAll = false;

  // 버전
  List<AppStoreVersion> _versions = const [];
  AppStoreVersion? _selectedVersion;

  // 버전 로컬라이제이션
  List<AppStoreVersionLocalization> _versionLocs = const [];
  AppStoreVersionLocalization? _selectedVersionLoc;

  // 앱 정보
  AppInfo? _selectedAppInfo;
  List<AppInfoLocalization> _appInfoLocs = const [];
  AppInfoLocalization? _selectedAppInfoLoc;

  // 카테고리 (앱 전체에 1번만 fetch)
  List<AppCategory> _categories = const [];

  // 심사 정보 (선택된 버전 기준)
  AppStoreReviewDetail? _reviewDetail;

  // App Store 서버 알림 V2 (앱 단위 1개)
  AppNotificationConfig? _notificationConfig;

  // 로딩 상태
  bool _loading = false;
  bool _switchingVersion = false;
  bool _switchingLocale = false;
  Object? _error;

  String? _selectedLocale;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _loadAll();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  /// 앱 전체에서 Cmd+숫자를 가로채 로케일 칩과 동기화한다.
  /// `CallbackShortcuts`는 Flutter focus 트리에 의존해 앱 전환 후 돌아오면
  /// 끊기는 경우가 있어, focus와 무관한 hardware 레벨 핸들러를 사용.
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isMetaPressed) return false;
    // Shift/Ctrl/Alt가 동시에 눌렸다면 별도 단축키 — 우리가 처리하지 않음.
    if (HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    for (final entry in _digitKeys.entries) {
      if (entry.value == event.logicalKey) {
        _selectLocaleByIndex(entry.key);
        return true; // 이벤트 소비
      }
    }
    return false;
  }

  // ---- 초기 + 전체 로드 ----

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _versions = const [];
      _selectedVersion = null;
      _versionLocs = const [];
      _selectedVersionLoc = null;
      _selectedAppInfo = null;
      _appInfoLocs = const [];
      _selectedAppInfoLoc = null;
      _categories = const [];
      _reviewDetail = null;
      _notificationConfig = null;
      _selectedLocale = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _client.fetchVersions(widget.team, widget.app.id),
        _client.fetchAppInfos(widget.team, widget.app.id),
        _client.fetchCategories(widget.team),
        _client.fetchAppNotificationConfig(widget.team, widget.app.id),
      ]);
      if (!mounted) return;

      final versions = results[0] as List<AppStoreVersion>;
      final appInfos = results[1] as List<AppInfo>;
      final categories = results[2] as List<AppCategory>;
      final notifConfig = results[3] as AppNotificationConfig;

      // editable AppInfo 우선 (PREPARE_FOR_SUBMISSION 등).
      // 없으면 LIVE(READY_FOR_DISTRIBUTION) 같은 read-only AppInfo로 fallback.
      final editableInfo = appInfos.where((i) => i.isEditable);
      final pickedAppInfo = editableInfo.isNotEmpty
          ? editableInfo.first
          : (appInfos.isNotEmpty ? appInfos.first : null);

      setState(() {
        _versions = versions;
        _selectedVersion = versions.isNotEmpty ? versions.first : null;
        _selectedAppInfo = pickedAppInfo;
        _categories = categories;
        _notificationConfig = notifConfig;
      });

      await Future.wait<void>([
        if (_selectedVersion != null) _loadVersionDeps(_selectedVersion!),
        if (_selectedAppInfo != null) _loadAppInfoLocs(_selectedAppInfo!),
      ]);
      if (mounted) _applyDefaultLocale();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 버전 단위 로드 (localizations + review detail).
  Future<void> _loadVersionDeps(AppStoreVersion version) async {
    final results = await Future.wait<dynamic>([
      _client.fetchLocalizations(widget.team, version.id),
      _client.fetchReviewDetail(widget.team, version.id),
    ]);
    if (!mounted) return;
    setState(() {
      _versionLocs = results[0] as List<AppStoreVersionLocalization>;
      _reviewDetail = results[1] as AppStoreReviewDetail?;
    });
  }

  Future<void> _loadAppInfoLocs(AppInfo info) async {
    final locs = await _client.fetchAppInfoLocalizations(widget.team, info.id);
    if (!mounted) return;
    setState(() => _appInfoLocs = locs);
  }

  /// 앱의 primaryLocale 기준으로 양쪽 로케일을 초기 선택.
  void _applyDefaultLocale() {
    final primary = widget.app.primaryLocale;
    final candidates = <String>{
      for (final v in _versionLocs) v.locale,
      for (final a in _appInfoLocs) a.locale,
    };
    if (candidates.isEmpty) return;
    final pick = candidates.contains(primary) ? primary : candidates.first;
    _selectLocale(pick);
  }

  void _selectLocale(String locale) {
    setState(() {
      _selectedLocale = locale;
      _selectedVersionLoc = _versionLocs
          .where((l) => l.locale == locale)
          .cast<AppStoreVersionLocalization?>()
          .firstWhere((_) => true, orElse: () => null);
      _selectedAppInfoLoc = _appInfoLocs
          .where((l) => l.locale == locale)
          .cast<AppInfoLocalization?>()
          .firstWhere((_) => true, orElse: () => null);
    });
  }

  // ---- 셀렉터 이벤트 ----

  Future<void> _onSelectVersion(AppStoreVersion? v) async {
    if (v == null || v.id == _selectedVersion?.id) return;
    setState(() {
      _selectedVersion = v;
      _switchingVersion = true;
      _versionLocs = const [];
      _selectedVersionLoc = null;
      _reviewDetail = null;
    });
    try {
      await _loadVersionDeps(v);
      if (mounted && _selectedLocale != null) _selectLocale(_selectedLocale!);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _switchingVersion = false);
    }
  }

  void _onSelectLocale(String? locale) {
    if (locale == null || locale == _selectedLocale) return;
    setState(() => _switchingLocale = true);
    _selectLocale(locale);
    setState(() => _switchingLocale = false);
  }

  // ---- 첫 출시 판단 ----

  bool get _isFirstSubmission {
    if (_versions.isEmpty) return false;
    const everPublished = {
      'READY_FOR_SALE',
      'READY_FOR_DISTRIBUTION',
      'PENDING_DEVELOPER_RELEASE',
      'PENDING_APPLE_RELEASE',
      'REPLACED_WITH_NEW_VERSION',
      'DEVELOPER_REMOVED_FROM_SALE',
      'NOT_APPLICABLE',
    };
    return !_versions.any((v) => everPublished.contains(v.appStoreState));
  }

  // ---- 섹션 업데이트 콜백 ----

  void _onVersionLocUpdated(AppStoreVersionLocalization updated) {
    setState(() {
      _versionLocs = _versionLocs
          .map((l) => l.id == updated.id ? updated : l)
          .toList(growable: false);
      if (_selectedVersionLoc?.id == updated.id) {
        _selectedVersionLoc = updated;
      }
    });
  }

  void _onAppInfoLocUpdated(AppInfoLocalization updated) {
    setState(() {
      _appInfoLocs = _appInfoLocs
          .map((l) => l.id == updated.id ? updated : l)
          .toList(growable: false);
      if (_selectedAppInfoLoc?.id == updated.id) {
        _selectedAppInfoLoc = updated;
      }
    });
  }

  Future<void> _onCategoriesUpdated() async {
    // 카테고리 PATCH는 응답에 attributes만 와서 relationships id가 안 옴 → AppInfo 재조회
    final infos = await _client.fetchAppInfos(widget.team, widget.app.id);
    if (!mounted) return;
    final currentId = _selectedAppInfo?.id;
    final refreshed =
        infos.where((i) => i.id == currentId).cast<AppInfo?>().firstWhere(
              (_) => true,
              orElse: () => null,
            );
    if (refreshed != null) {
      setState(() => _selectedAppInfo = refreshed);
    }
  }

  void _onReviewDetailUpdated(AppStoreReviewDetail updated) {
    setState(() => _reviewDetail = updated);
  }

  void _onNotificationConfigUpdated(AppNotificationConfig updated) {
    setState(() => _notificationConfig = updated);
  }

  // ---- 워드 파일 첨부 ----

  Future<void> _pickDocx() async {
    const docxGroup = XTypeGroup(
      label: 'App Description (.docx)',
      extensions: <String>['docx'],
    );
    const anyGroup = XTypeGroup(label: '모든 파일');

    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[docxGroup, anyGroup],
    );
    if (file == null) return;

    try {
      final bytes = await file.readAsBytes();
      final parsed = _docxParser.parse(bytes);
      if (!mounted) return;
      setState(() {
        _parsedDocx = parsed;
        _docxFileName = file.name;
      });
      final summary = parsed.sections.isEmpty
          ? '인식된 언어 헤더가 없습니다.'
          : '${parsed.sections.length}개 언어 인식: '
              '${parsed.sections.keys.join(", ")}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('워드 파일 파싱 완료 — $summary'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('워드 파싱 실패: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _clearDocx() {
    setState(() {
      _parsedDocx = null;
      _docxFileName = null;
    });
  }

  // ---- 키워드 텍스트 파일 첨부 ----

  Future<void> _pickKeywords() async {
    const txtGroup = XTypeGroup(
      label: 'Keywords (.txt)',
      extensions: <String>['txt'],
    );
    const anyGroup = XTypeGroup(label: '모든 파일');

    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[txtGroup, anyGroup],
    );
    if (file == null) return;

    try {
      final bytes = await file.readAsBytes();
      final parsed = _keywordsParser.parseBytes(bytes);
      if (!mounted) return;
      setState(() {
        _parsedKeywords = parsed;
        _keywordsFileName = file.name;
      });
      final summary = parsed.isEmpty
          ? '인식된 언어 헤더가 없습니다.'
          : '${parsed.keywordsByLocale.length}개 로케일 인식: '
              '${parsed.keywordsByLocale.keys.join(", ")}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('키워드 파일 파싱 완료 — $summary'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('키워드 파싱 실패: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _clearKeywords() {
    setState(() {
      _parsedKeywords = null;
      _keywordsFileName = null;
    });
  }

  // ---- What's New 붙여넣기 ----

  Future<void> _pickWhatsNew() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _WhatsNewPasteDialog(initial: _whatsNewRawText ?? ''),
    );
    if (!mounted || result == null) return;
    final text = result.trim();
    if (text.isEmpty) {
      _clearWhatsNew();
      return;
    }
    final parsed = _whatsNewParser.parse(
      text,
      _versionLocs.map((l) => l.locale),
    );
    setState(() {
      _parsedWhatsNew = parsed;
      _whatsNewRawText = text;
    });
    final summary = parsed.isEmpty
        ? '인식된 로케일이 없습니다.'
        : '${parsed.whatsNewByLocale.length}개 로케일 인식: '
            '${parsed.whatsNewByLocale.keys.join(", ")}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("What's New 파싱 완료 — $summary"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearWhatsNew() {
    setState(() {
      _parsedWhatsNew = null;
      _whatsNewRawText = null;
    });
  }

  /// 첨부된 파일(.docx + .txt)을 모든 로케일에 일괄 PATCH.
  ///
  /// 각 로케일에 대해:
  /// - VersionLocalization: description / keywords
  /// - AppInfoLocalization: name / subtitle
  ///
  /// 현재 로케일의 카테고리 변경은 별도로 처리 (카테고리는 로케일 비종속).
  Future<void> _applyAll() async {
    setState(() => _applyingAll = true);
    int patched = 0;
    int skipped = 0;
    final errors = <String>[];

    final parsedDocx = _parsedDocx;
    final parsedKeywords = _parsedKeywords;
    final parsedWhatsNew = _parsedWhatsNew;
    final isFirstSub = _isFirstSubmission;

    // ---- 버전 로컬라이제이션: whatsNew + description + keywords ----
    for (final loc in _versionLocs) {
      final parsedSection = parsedDocx?.sections[loc.locale];
      final parsedKw = parsedKeywords?.keywordsFor(loc.locale);
      final parsedWn = parsedWhatsNew?.whatsNewFor(loc.locale);
      final diff = <String, String>{};

      if (!isFirstSub && parsedWn != null && parsedWn.isNotEmpty) {
        if (parsedWn.length < 4) {
          errors.add(
              '${loc.locale} What\'s New: ASC 정책상 최소 4자 (현재 ${parsedWn.length}자)');
        } else if (parsedWn != loc.whatsNew) {
          diff['whatsNew'] = parsedWn;
        }
      }
      if (parsedSection?.description != null &&
          parsedSection!.description!.isNotEmpty &&
          parsedSection.description != loc.description) {
        diff['description'] = parsedSection.description!;
      }
      if (parsedKw != null) {
        final truncated = truncateKeywords(parsedKw, 100);
        if (truncated.isNotEmpty && truncated != loc.keywords) {
          diff['keywords'] = truncated;
        }
      }

      if (diff.isEmpty) {
        skipped++;
        continue;
      }
      try {
        final updated = await _client.updateLocalizationFields(
          widget.team,
          loc.id,
          diff,
        );
        if (!mounted) return;
        _onVersionLocUpdated(updated);
        patched++;
      } catch (e) {
        errors.add('${loc.locale} 버전 정보: ${_friendlyError(e)}');
      }
    }

    // ---- 앱 정보 로컬라이제이션: name + subtitle ----
    final appInfoEditable = _selectedAppInfo?.isEditable ?? false;
    if (appInfoEditable) {
      for (final loc in _appInfoLocs) {
        final parsedSection = parsedDocx?.sections[loc.locale];
        if (parsedSection == null) {
          skipped++;
          continue;
        }
        final diff = <String, String>{};

        // 사전 검증 — 30자 제한을 클라이언트에서 미리 컷.
        // ASC에 보내봐야 400 떨어지고 다른 필드 PATCH도 영향 받음.
        if (parsedSection.name != null &&
            parsedSection.name!.isNotEmpty &&
            parsedSection.name != loc.name) {
          if (parsedSection.name!.length > 30) {
            errors.add(
                '${loc.locale} 앱 이름: 30자 초과 (${parsedSection.name!.length}자) — '
                '"${parsedSection.name}"');
          } else {
            diff['name'] = parsedSection.name!;
          }
        }
        if (parsedSection.subtitle != null &&
            parsedSection.subtitle!.isNotEmpty &&
            parsedSection.subtitle != loc.subtitle) {
          if (parsedSection.subtitle!.length > 30) {
            errors.add(
                '${loc.locale} 부제: 30자 초과 (${parsedSection.subtitle!.length}자) — '
                '"${parsedSection.subtitle}"');
          } else {
            diff['subtitle'] = parsedSection.subtitle!;
          }
        }
        if (diff.isEmpty) {
          skipped++;
          continue;
        }
        try {
          final updated = await _client.updateAppInfoLocalizationFields(
            widget.team,
            loc.id,
            diff,
          );
          if (!mounted) return;
          _onAppInfoLocUpdated(updated);
          patched++;
        } catch (e) {
          errors.add('${loc.locale} 앱 정보: ${_friendlyError(e)}');
        }
      }
    } else if (parsedDocx != null && _appInfoLocs.isNotEmpty) {
      // 수정 불가 상태(LIVE 등)에서는 알려만 주고 카운트는 skip.
      errors.add('앱 정보(이름/부제)는 현재 ${_selectedAppInfo?.state ?? "수정 불가"} 상태라 건너뜀');
    }

    if (!mounted) return;
    setState(() => _applyingAll = false);

    final parts = <String>[];
    if (patched > 0) parts.add('$patched건 저장');
    if (skipped > 0) parts.add('$skipped건 변경 없음');
    if (errors.isNotEmpty) parts.add('${errors.length}건 실패');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parts.isEmpty ? '적용할 변경이 없습니다.' : parts.join(' · '),
        ),
        behavior: SnackBarBehavior.floating,
        duration: errors.isEmpty
            ? const Duration(seconds: 4)
            : const Duration(seconds: 8),
      ),
    );

    // 실패 상세는 별도 dialog로 (스낵바는 길어서 잘림)
    if (errors.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _FailuresDialog(errors: errors),
      );
    }
  }

  /// 사용자에게 보여줄 ASC 에러 한 줄. AscApiException의 detail이 있으면
  /// 그쪽을 우선하고, 흔한 패턴은 좀 더 친화적으로 다시 쓴다.
  String _friendlyError(Object e) {
    String text;
    if (e is AscApiException) {
      final base = e.detail ?? e.message;
      text = e.statusCode == null ? base : '[HTTP ${e.statusCode}] $base';
    } else {
      text = e.toString();
    }
    // 같은 이름의 앱이 다른 곳에서 이미 쓰이는 경우 — ASC 정책이라 클라에서 못 푸니
    // 사용자에게 명확히 액션을 알려줌.
    if (text.contains('already being used for another app')) {
      return '이름 중복 — 같은 팀의 다른 앱이 이미 동일한 이름을 사용 중입니다. '
          'App Store Connect 웹에서 충돌하는 앱의 이름을 바꾸거나, '
          '이번에 적용할 이름을 다르게 지정해 주세요.';
    }
    if (text.contains("cannot be longer than '30' characters")) {
      return '30자 초과 — name/subtitle은 최대 30자입니다.';
    }
    if (text.contains("cannot be longer than '4000' characters")) {
      return '4000자 초과 — description/whatsNew은 최대 4000자입니다.';
    }
    return text;
  }

  ParsedLocaleSection? get _currentParsedSection {
    final locale = _selectedLocale;
    if (locale == null) return null;
    return _parsedDocx?.sections[locale];
  }

  String? get _currentParsedKeywords {
    final locale = _selectedLocale;
    if (locale == null) return null;
    return _parsedKeywords?.keywordsFor(locale);
  }

  String? get _currentParsedWhatsNew {
    final locale = _selectedLocale;
    if (locale == null) return null;
    return _parsedWhatsNew?.whatsNewFor(locale);
  }

  /// 양쪽 로컬라이제이션의 합집합 + 정렬. 탭바와 단축키가 동일한 순서를 공유.
  List<String> get _sortedLocales {
    final set = <String>{
      for (final v in _versionLocs) v.locale,
      for (final a in _appInfoLocs) a.locale,
    };
    final list = set.toList()..sort();
    return list;
  }

  /// Cmd+N 단축키용 — 1-based 인덱스로 [n]번째 로케일 활성화.
  /// 범위 밖이거나 동일 로케일이면 no-op.
  void _selectLocaleByIndex(int n) {
    final list = _sortedLocales;
    final idx = n - 1;
    if (idx < 0 || idx >= list.length) return;
    final loc = list[idx];
    if (loc == _selectedLocale || _switchingLocale || _switchingVersion) return;
    _onSelectLocale(loc);
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.app.name),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  /// 1-based 인덱스 → 키보드 키. 10번째는 Cmd+0.
  static const Map<int, LogicalKeyboardKey> _digitKeys = {
    1: LogicalKeyboardKey.digit1,
    2: LogicalKeyboardKey.digit2,
    3: LogicalKeyboardKey.digit3,
    4: LogicalKeyboardKey.digit4,
    5: LogicalKeyboardKey.digit5,
    6: LogicalKeyboardKey.digit6,
    7: LogicalKeyboardKey.digit7,
    8: LogicalKeyboardKey.digit8,
    9: LogicalKeyboardKey.digit9,
    10: LogicalKeyboardKey.digit0,
  };

  Widget _buildBody(BuildContext context) {
    if (_versions.isEmpty && _error == null) {
      return const Center(child: Text('이 앱의 App Store 버전이 없습니다.'));
    }

    final locales = _sortedLocales;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppMetaCard(app: widget.app),
          const SizedBox(height: 16),
          _AssetAttachCard(
            docxFileName: _docxFileName,
            parsedDocx: _parsedDocx,
            keywordsFileName: _keywordsFileName,
            parsedKeywords: _parsedKeywords,
            parsedWhatsNew: _parsedWhatsNew,
            applyingAll: _applyingAll,
            onPickDocx: _pickDocx,
            onClearDocx: _clearDocx,
            onPickKeywords: _pickKeywords,
            onClearKeywords: _clearKeywords,
            onPickWhatsNew: _pickWhatsNew,
            onClearWhatsNew: _clearWhatsNew,
            onApplyAll: _applyAll,
          ),
          const SizedBox(height: 24),
          const SectionLabel('버전'),
          const SizedBox(height: 8),
          DropdownButtonFormField<AppStoreVersion>(
            initialValue: _selectedVersion,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              for (final v in _versions)
                DropdownMenuItem(
                  value: v,
                  child: Text(
                    '${v.versionString}  ·  ${v.platform}  ·  ${v.appStoreState}'
                    '${v.isLikelyEditable ? '' : '  (편집 제한 가능)'}',
                  ),
                ),
            ],
            onChanged: _switchingVersion ? null : _onSelectVersion,
          ),
          const SizedBox(height: 24),
          const SectionLabel('로케일'),
          const SizedBox(height: 8),
          if (_switchingVersion)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _LocaleTabBar(
              locales: locales,
              selected: _selectedLocale,
              disabled: _switchingLocale,
              parsedDocxLocales: _parsedDocx?.sections.keys.toSet() ?? const {},
              parsedKeywordsLocales:
                  _parsedKeywords?.keywordsByLocale.keys.toSet() ?? const {},
              parsedWhatsNewLocales:
                  _parsedWhatsNew?.whatsNewByLocale.keys.toSet() ?? const {},
              onTap: _onSelectLocale,
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            SectionErrorCard(error: _error!),
          ],
          const SizedBox(height: 32),
          VersionLocalizationSection(
            team: widget.team,
            client: _client,
            localization: _selectedVersionLoc,
            isFirstSubmission: _isFirstSubmission,
            onUpdated: _onVersionLocUpdated,
            parsedSection: _currentParsedSection,
            parsedKeywords: _currentParsedKeywords,
            parsedWhatsNew: _currentParsedWhatsNew,
          ),
          const Divider(height: 64),
          AppInfoSection(
            team: widget.team,
            client: _client,
            appInfo: _selectedAppInfo,
            localization: _selectedAppInfoLoc,
            categories: _categories,
            onLocalizationUpdated: _onAppInfoLocUpdated,
            onCategoriesUpdated: _onCategoriesUpdated,
            parsedSection: _currentParsedSection,
          ),
          const Divider(height: 64),
          ReviewDetailSection(
            team: widget.team,
            client: _client,
            reviewDetail: _reviewDetail,
            onUpdated: _onReviewDetailUpdated,
          ),
          const Divider(height: 64),
          NotificationConfigSection(
            team: widget.team,
            client: _client,
            appId: widget.app.id,
            config: _notificationConfig,
            onUpdated: _onNotificationConfigUpdated,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _AssetAttachCard extends StatefulWidget {
  const _AssetAttachCard({
    required this.docxFileName,
    required this.parsedDocx,
    required this.keywordsFileName,
    required this.parsedKeywords,
    required this.parsedWhatsNew,
    required this.applyingAll,
    required this.onPickDocx,
    required this.onClearDocx,
    required this.onPickKeywords,
    required this.onClearKeywords,
    required this.onPickWhatsNew,
    required this.onClearWhatsNew,
    required this.onApplyAll,
  });

  final String? docxFileName;
  final ParsedDocx? parsedDocx;
  final String? keywordsFileName;
  final ParsedKeywordsFile? parsedKeywords;
  final ParsedWhatsNew? parsedWhatsNew;
  final bool applyingAll;
  final VoidCallback onPickDocx;
  final VoidCallback onClearDocx;
  final VoidCallback onPickKeywords;
  final VoidCallback onClearKeywords;
  final VoidCallback onPickWhatsNew;
  final VoidCallback onClearWhatsNew;
  final VoidCallback onApplyAll;

  @override
  State<_AssetAttachCard> createState() => _AssetAttachCardState();
}

class _AssetAttachCardState extends State<_AssetAttachCard> {
  bool _expanded = true;

  bool get _hasAnyParsed =>
      (widget.parsedDocx != null && !widget.parsedDocx!.isEmpty) ||
      (widget.parsedKeywords != null && !widget.parsedKeywords!.isEmpty) ||
      (widget.parsedWhatsNew != null && !widget.parsedWhatsNew!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.upload_file_outlined,
                      color: scheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    '파일 자동 입력',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (_hasAnyParsed && !_expanded) ...[
                    const SizedBox(width: 12),
                    const UpdatedBadge(),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) ...[
          const SizedBox(height: 4),
          Text(
            '.docx → 이름·부제·설명 / .txt → 키워드(100자 자동 절단) / 텍스트 → What\'s New.\n'
            '변경된 필드에는 "수정" 뱃지가 붙고, "전체 변경 적용"으로 모든 로케일을 한 번에 PATCH합니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _AttachRow(
            icon: Icons.description_outlined,
            label: '.docx 첨부',
            fileName: widget.docxFileName,
            disabled: widget.applyingAll,
            onPick: widget.onPickDocx,
            onClear: widget.onClearDocx,
          ),
          if (widget.parsedDocx != null) ...[
            const SizedBox(height: 8),
            _ParsedSummary(
              prefix: '워드 로케일:',
              chips: widget.parsedDocx!.sections.keys.toList(),
              errors: widget.parsedDocx!.unknownHeaders,
            ),
          ],
          const SizedBox(height: 12),
          _AttachRow(
            icon: Icons.tag,
            label: '.txt 키워드 첨부',
            fileName: widget.keywordsFileName,
            disabled: widget.applyingAll,
            onPick: widget.onPickKeywords,
            onClear: widget.onClearKeywords,
          ),
          if (widget.parsedKeywords != null) ...[
            const SizedBox(height: 8),
            _ParsedSummary(
              prefix: '키워드 로케일:',
              chips: widget.parsedKeywords!.keywordsByLocale.keys.toList(),
              errors: widget.parsedKeywords!.unknownHeaders,
            ),
          ],
          const SizedBox(height: 12),
          _AttachRow(
            icon: Icons.edit_note,
            label: "What's New 붙여넣기",
            fileName: widget.parsedWhatsNew == null
                ? null
                : '${widget.parsedWhatsNew!.whatsNewByLocale.length}개 로케일 인식됨',
            disabled: widget.applyingAll,
            onPick: widget.onPickWhatsNew,
            onClear: widget.onClearWhatsNew,
          ),
          if (widget.parsedWhatsNew != null) ...[
            const SizedBox(height: 8),
            _ParsedSummary(
              prefix: "What's New 로케일:",
              chips: widget.parsedWhatsNew!.whatsNewByLocale.keys.toList(),
              errors: widget.parsedWhatsNew!.unknownPrefixes,
            ),
          ],
          if (_hasAnyParsed) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: widget.applyingAll ? null : widget.onApplyAll,
                icon: widget.applyingAll
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: Text(widget.applyingAll ? '적용 중…' : '전체 변경 적용'),
              ),
            ),
          ],
          ],
        ],
      ),
    );
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.icon,
    required this.label,
    required this.fileName,
    required this.disabled,
    required this.onPick,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final String? fileName;
  final bool disabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilledButton.tonalIcon(
          onPressed: disabled ? null : onPick,
          icon: Icon(icon),
          label: Text(label),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            fileName ?? '아직 첨부된 파일이 없습니다.',
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (fileName != null)
          IconButton(
            tooltip: '초기화',
            onPressed: disabled ? null : onClear,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}

class _ParsedSummary extends StatelessWidget {
  const _ParsedSummary({
    required this.prefix,
    required this.chips,
    required this.errors,
  });

  final String prefix;
  final List<String> chips;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prefix, style: Theme.of(context).textTheme.bodySmall),
        for (final l in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        if (errors.isNotEmpty) ...[
          Text(
            '· 매핑 실패:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          for (final h in errors)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                h,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
              ),
            ),
        ],
      ],
    );
  }
}

/// "전체 변경 적용" 결과 중 실패만 모아 한 줄씩 가독성 있게 보여주는 다이얼로그.
/// 각 줄은 `로케일 + 필드: 사유` 형식이라 SelectableText로 복사 가능하게 한다.
class _FailuresDialog extends StatelessWidget {
  const _FailuresDialog({required this.errors});
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: scheme.error),
          const SizedBox(width: 8),
          Text('일부 적용 실패 (${errors.length}건)'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final err in errors) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    err,
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

/// What's New 텍스트를 붙여넣기 받는 다이얼로그.
/// 헤더 prefix(국/영/일/기타 등) + 콜론 + 본문 라인을 자유롭게 받는다.
class _WhatsNewPasteDialog extends StatefulWidget {
  const _WhatsNewPasteDialog({required this.initial});
  final String initial;

  @override
  State<_WhatsNewPasteDialog> createState() => _WhatsNewPasteDialogState();
}

class _WhatsNewPasteDialogState extends State<_WhatsNewPasteDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("What's New 텍스트 붙여넣기"),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '한 줄에 `prefix: 본문` 형식. prefix는 `국 / 영 / 일 / 중 / 베 / 인` 등 '
              '한 글자 또는 `한국어 / 영어`처럼 풀네임 모두 인식합니다. '
              '`기타`는 명시되지 않은 모든 로케일에 적용되는 wildcard 입니다. '
              '머리말(`메타데이터` 등)은 무시됩니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 12,
              minLines: 8,
              autofocus: true,
              decoration: const InputDecoration(
                hintText:
                    '메타데이터\n국: 앱 안정성이 개선되었습니다.\n영: App stability has been improved.\n'
                    '일: アプリの安定性が改善されました\n기타: App stability has been improved.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('파싱'),
        ),
      ],
    );
  }
}

/// 로케일 탭바 — 가로 스크롤 칩.
/// 각 칩에 파싱된 데이터 유무를 작은 점으로 표시.
class _LocaleTabBar extends StatelessWidget {
  const _LocaleTabBar({
    required this.locales,
    required this.selected,
    required this.disabled,
    required this.parsedDocxLocales,
    required this.parsedKeywordsLocales,
    required this.parsedWhatsNewLocales,
    required this.onTap,
  });

  final List<String> locales;
  final String? selected;
  final bool disabled;
  final Set<String> parsedDocxLocales;
  final Set<String> parsedKeywordsLocales;
  final Set<String> parsedWhatsNewLocales;
  final ValueChanged<String?> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: locales.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final loc = locales[i];
          final isSelected = loc == selected;
          final hasDocx = parsedDocxLocales.contains(loc);
          final hasKw = parsedKeywordsLocales.contains(loc);
          final hasWn = parsedWhatsNewLocales.contains(loc);
          // Cmd+1 ~ Cmd+9 (i=0..8), Cmd+0 (i=9). 10번째 초과는 힌트 생략.
          final shortcutHint = i < 9
              ? '⌘${i + 1}'
              : i == 9
                  ? '⌘0'
                  : null;
          final chip = ChoiceChip(
            selected: isSelected,
            onSelected: disabled ? null : (_) => onTap(loc),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shortcutHint != null) ...[
                  Text(
                    shortcutHint,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isSelected
                              ? scheme.onSecondaryContainer
                                  .withValues(alpha: 0.7)
                              : scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(loc),
                if (hasWn) ...[
                  const SizedBox(width: 6),
                  _ParsedDot(color: scheme.secondary, tooltip: "What's New 파싱됨"),
                ],
                if (hasDocx) ...[
                  const SizedBox(width: 4),
                  _ParsedDot(color: scheme.primary, tooltip: '워드 파싱됨'),
                ],
                if (hasKw) ...[
                  const SizedBox(width: 4),
                  _ParsedDot(color: scheme.tertiary, tooltip: '키워드 파싱됨'),
                ],
              ],
            ),
          );
          return shortcutHint == null
              ? chip
              : Tooltip(message: '$shortcutHint 로 이동', child: chip);
        },
      ),
    );
  }
}

class _ParsedDot extends StatelessWidget {
  const _ParsedDot({required this.color, required this.tooltip});
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _AppMetaCard extends StatelessWidget {
  const _AppMetaCard({required this.app});
  final AppSummary app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            app.bundleId,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'SKU: ${app.sku} · primary locale: ${app.primaryLocale} · id: ${app.id}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
