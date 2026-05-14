import 'package:flutter/material.dart';

import '../models/app_category.dart';
import '../models/app_info.dart';
import '../models/app_info_localization.dart';
import '../models/app_notification_config.dart';
import '../models/app_store_review_detail.dart';
import '../models/app_store_version.dart';
import '../models/app_store_version_localization.dart';
import '../models/app_summary.dart';
import '../models/team.dart';
import '../services/asc_api_client.dart';
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
            team: widget.team,
            client: _client,
            localization: _selectedVersionLoc,
            isFirstSubmission: _isFirstSubmission,
            onUpdated: _onVersionLocUpdated,
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
