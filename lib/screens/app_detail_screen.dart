import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/app_category.dart';
import '../models/app_info.dart';
import '../models/app_info_localization.dart';
import '../models/app_notification_config.dart';
import '../models/app_store_review_detail.dart';
import '../models/app_store_version.dart';
import '../models/app_store_version_localization.dart';
import '../models/app_summary.dart';
import '../models/parsed_docx.dart';
import '../models/team.dart';
import '../services/asc_api_client.dart';
import '../services/docx_parser.dart';
import '../services/team_repository.dart';
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

  // 워드 파싱 결과 (로케일별 섹션)
  ParsedDocx? _parsedDocx;
  String? _docxFileName;

  // 섹션 state 외부 접근용 (전체 적용 버튼에서 사용)
  final GlobalKey<VersionLocalizationSectionState> _versionLocKey =
      GlobalKey<VersionLocalizationSectionState>();
  final GlobalKey<AppInfoSectionState> _appInfoKey =
      GlobalKey<AppInfoSectionState>();

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
    _loadAll();
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

  /// 현재 선택된 로케일의 모든 변경사항 일괄 PATCH.
  /// 버전 로컬라이제이션 → 앱 정보 로컬라이제이션 → 카테고리 순.
  Future<void> _applyAll() async {
    setState(() => _applyingAll = true);
    int success = 0;
    int skipped = 0;
    final errors = <String>[];

    Future<void> run(String label, Future<bool> Function() task) async {
      try {
        final ok = await task();
        if (ok) {
          success++;
        } else {
          skipped++;
        }
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    await run('버전 로컬라이제이션',
        () => _versionLocKey.currentState?.saveIfChanged() ?? Future.value(false));
    await run(
        '앱 정보 로컬라이제이션',
        () =>
            _appInfoKey.currentState?.saveLocalizationIfChanged() ??
            Future.value(false));
    await run(
        '카테고리',
        () =>
            _appInfoKey.currentState?.saveCategoriesIfChanged() ??
            Future.value(false));

    if (!mounted) return;
    setState(() => _applyingAll = false);

    final parts = <String>[];
    if (success > 0) parts.add('$success건 저장');
    if (skipped > 0) parts.add('$skipped건 변경 없음');
    if (errors.isNotEmpty) parts.add('${errors.length}건 실패');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parts.isEmpty ? '적용할 변경이 없습니다.' : parts.join(' · '),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  ParsedLocaleSection? get _currentParsedSection {
    final locale = _selectedLocale;
    if (locale == null) return null;
    return _parsedDocx?.sections[locale];
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

  Widget _buildBody(BuildContext context) {
    if (_versions.isEmpty && _error == null) {
      return const Center(child: Text('이 앱의 App Store 버전이 없습니다.'));
    }

    final locales = <String>{
      for (final v in _versionLocs) v.locale,
      for (final a in _appInfoLocs) a.locale,
    }.toList()
      ..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppMetaCard(app: widget.app),
          const SizedBox(height: 16),
          _DocxAttachCard(
            fileName: _docxFileName,
            parsed: _parsedDocx,
            applyingAll: _applyingAll,
            onPick: _pickDocx,
            onClear: _clearDocx,
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
            DropdownButtonFormField<String>(
              initialValue: _selectedLocale,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                for (final loc in locales)
                  DropdownMenuItem(value: loc, child: Text(loc)),
              ],
              onChanged: _switchingLocale ? null : _onSelectLocale,
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            SectionErrorCard(error: _error!),
          ],
          const SizedBox(height: 32),
          VersionLocalizationSection(
            key: _versionLocKey,
            team: widget.team,
            client: _client,
            localization: _selectedVersionLoc,
            isFirstSubmission: _isFirstSubmission,
            onUpdated: _onVersionLocUpdated,
            parsedSection: _currentParsedSection,
          ),
          const Divider(height: 64),
          AppInfoSection(
            key: _appInfoKey,
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

class _DocxAttachCard extends StatelessWidget {
  const _DocxAttachCard({
    required this.fileName,
    required this.parsed,
    required this.applyingAll,
    required this.onPick,
    required this.onClear,
    required this.onApplyAll,
  });

  final String? fileName;
  final ParsedDocx? parsed;
  final bool applyingAll;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final VoidCallback onApplyAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasParsed = parsed != null && !parsed!.isEmpty;

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
          Row(
            children: [
              Icon(Icons.description_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Text(
                '워드 파일 자동 입력',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              if (fileName != null)
                IconButton(
                  tooltip: '초기화',
                  onPressed: applyingAll ? null : onClear,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '.docx를 첨부하면 로케일별 이름·부제·설명·프로모션 텍스트가 자동으로 채워집니다. '
            '변경 사항이 있는 섹션에는 "updated" 뱃지가 표시되고, "전체 변경 적용"으로 한 번에 PATCH 가능합니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: applyingAll ? null : onPick,
                icon: const Icon(Icons.upload_file),
                label: const Text('.docx 첨부'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  fileName ?? '아직 첨부된 파일이 없습니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasParsed)
                FilledButton.icon(
                  onPressed: applyingAll ? null : onApplyAll,
                  icon: applyingAll
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish_outlined),
                  label: Text(applyingAll ? '적용 중…' : '전체 변경 적용'),
                ),
            ],
          ),
          if (hasParsed) ...[
            const SizedBox(height: 12),
            _ParsedSummary(parsed: parsed!),
          ],
        ],
      ),
    );
  }
}

class _ParsedSummary extends StatelessWidget {
  const _ParsedSummary({required this.parsed});
  final ParsedDocx parsed;

  @override
  Widget build(BuildContext context) {
    final locales = parsed.sections.keys.toList();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '인식된 로케일:',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final l in locales)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        if (parsed.unknownHeaders.isNotEmpty) ...[
          Text(
            '· 매핑 실패:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          for (final h in parsed.unknownHeaders)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
