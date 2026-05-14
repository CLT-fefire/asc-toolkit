import 'package:flutter/material.dart';

import '../models/app_store_version.dart';
import '../models/app_store_version_localization.dart';
import '../models/app_summary.dart';
import '../models/team.dart';
import '../services/asc_api_client.dart';
import '../services/team_repository.dart';

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

  final TextEditingController _whatsNewCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _keywordsCtrl = TextEditingController();
  final TextEditingController _promotionalCtrl = TextEditingController();

  List<AppStoreVersion> _versions = const [];
  AppStoreVersion? _selectedVersion;

  List<AppStoreVersionLocalization> _localizations = const [];
  AppStoreVersionLocalization? _selectedLocalization;

  bool _loadingVersions = false;
  bool _loadingLocalizations = false;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  @override
  void dispose() {
    _whatsNewCtrl.dispose();
    _descriptionCtrl.dispose();
    _keywordsCtrl.dispose();
    _promotionalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    setState(() {
      _loadingVersions = true;
      _error = null;
      _versions = const [];
      _selectedVersion = null;
      _localizations = const [];
      _selectedLocalization = null;
      _resetControllers(null);
    });
    try {
      final versions = await _client.fetchVersions(widget.team, widget.app.id);
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _selectedVersion = versions.isNotEmpty ? versions.first : null;
      });
      if (_selectedVersion != null) {
        await _loadLocalizations(_selectedVersion!);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingVersions = false);
    }
  }

  Future<void> _loadLocalizations(AppStoreVersion version) async {
    setState(() {
      _loadingLocalizations = true;
      _error = null;
      _localizations = const [];
      _selectedLocalization = null;
      _resetControllers(null);
    });
    try {
      final locs = await _client.fetchLocalizations(widget.team, version.id);
      if (!mounted) return;
      final primary = _pickPrimaryLocalization(locs);
      setState(() {
        _localizations = locs;
        _selectedLocalization = primary;
        _resetControllers(primary);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingLocalizations = false);
    }
  }

  AppStoreVersionLocalization? _pickPrimaryLocalization(
    List<AppStoreVersionLocalization> locs,
  ) {
    if (locs.isEmpty) return null;
    final primary = widget.app.primaryLocale;
    for (final loc in locs) {
      if (loc.locale == primary) return loc;
    }
    return locs.first;
  }

  void _resetControllers(AppStoreVersionLocalization? loc) {
    _whatsNewCtrl.text = loc?.whatsNew ?? '';
    _descriptionCtrl.text = loc?.description ?? '';
    _keywordsCtrl.text = loc?.keywords ?? '';
    _promotionalCtrl.text = loc?.promotionalText ?? '';
  }

  /// 같은 앱의 versions 중 한 번이라도 게시 이력이 있는 상태가 있으면 false.
  /// Apple 정책상 첫 출시 버전에서는 'What's New' 입력 불가.
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

  /// controller 값과 _selectedLocalization의 현재 값을 비교해서
  /// 실제로 바뀐 필드만 PATCH attributes 맵으로 반환.
  Map<String, String> _diffPayload() {
    final loc = _selectedLocalization;
    if (loc == null) return const {};
    final result = <String, String>{};

    bool changed(String? before, String after) => (before ?? '') != after;

    if (!_isFirstSubmission && changed(loc.whatsNew, _whatsNewCtrl.text)) {
      result['whatsNew'] = _whatsNewCtrl.text;
    }
    if (changed(loc.description, _descriptionCtrl.text)) {
      result['description'] = _descriptionCtrl.text;
    }
    if (changed(loc.keywords, _keywordsCtrl.text)) {
      result['keywords'] = _keywordsCtrl.text;
    }
    if (changed(loc.promotionalText, _promotionalCtrl.text)) {
      result['promotionalText'] = _promotionalCtrl.text;
    }
    return result;
  }

  void _onSelectVersion(AppStoreVersion? v) {
    if (v == null || v.id == _selectedVersion?.id) return;
    setState(() => _selectedVersion = v);
    _loadLocalizations(v);
  }

  void _onSelectLocalization(AppStoreVersionLocalization? loc) {
    if (loc == null || loc.id == _selectedLocalization?.id) return;
    setState(() {
      _selectedLocalization = loc;
      _resetControllers(loc);
    });
  }

  Future<void> _save() async {
    final loc = _selectedLocalization;
    if (loc == null) return;
    final diff = _diffPayload();
    if (diff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('변경된 내용이 없습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _client.updateLocalizationFields(
        widget.team,
        loc.id,
        diff,
      );
      if (!mounted) return;
      setState(() {
        _selectedLocalization = updated;
        _localizations = _localizations
            .map((l) => l.id == updated.id ? updated : l)
            .toList(growable: false);
        _resetControllers(updated);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "'${loc.locale}' 저장 완료 — ${diff.keys.join(", ")}",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.app.name),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loadingVersions ? null : _loadVersions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingVersions
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_versions.isEmpty && _error == null) {
      return const Center(child: Text('이 앱의 App Store 버전이 없습니다.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppMetaCard(app: widget.app),
          const SizedBox(height: 24),
          _SectionLabel('버전'),
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
            onChanged: _onSelectVersion,
          ),
          const SizedBox(height: 24),
          _SectionLabel('로케일'),
          const SizedBox(height: 8),
          if (_loadingLocalizations)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            DropdownButtonFormField<AppStoreVersionLocalization>(
              initialValue: _selectedLocalization,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                for (final loc in _localizations)
                  DropdownMenuItem(value: loc, child: Text(loc.locale)),
              ],
              onChanged: _onSelectLocalization,
            ),
          const SizedBox(height: 24),
          _SectionLabel("이 버전의 새로운 기능 (What's New)"),
          const SizedBox(height: 8),
          if (_isFirstSubmission) ...[
            const _FirstSubmissionNotice(),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _whatsNewCtrl,
            enabled: _selectedLocalization != null &&
                !_saving &&
                !_isFirstSubmission,
            maxLines: 8,
            minLines: 4,
            maxLength: 4000,
            decoration: InputDecoration(
              hintText: _isFirstSubmission
                  ? '첫 출시 버전이라 입력이 비활성화되어 있습니다.'
                  : '예: 버그 수정 및 성능 개선.\n   - 새 기능 …\n   - 알려진 이슈 …',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('설명 (Description)'),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionCtrl,
            enabled: _selectedLocalization != null && !_saving,
            maxLines: 12,
            minLines: 6,
            maxLength: 4000,
            decoration: const InputDecoration(
              hintText: '앱 설명. App Store 상세 페이지에 표시되는 본문.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('키워드 (Keywords)'),
          const SizedBox(height: 4),
          Text(
            '콤마(,)로 구분. 100자 제한.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keywordsCtrl,
            enabled: _selectedLocalization != null && !_saving,
            maxLines: 2,
            minLines: 1,
            maxLength: 100,
            decoration: const InputDecoration(
              hintText: '예: 게임,RPG,어드벤처,캐주얼',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('프로모션 텍스트 (Promotional Text)'),
          const SizedBox(height: 4),
          Text(
            '170자 제한. 앱 업데이트 없이 수시 변경 가능.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promotionalCtrl,
            enabled: _selectedLocalization != null && !_saving,
            maxLines: 4,
            minLines: 2,
            maxLength: 170,
            decoration: const InputDecoration(
              hintText: '예: 한정 이벤트 진행 중! 지금 다운로드하고 …',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(error: _error!),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed:
                  (_selectedLocalization == null || _saving) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '저장 중…' : '변경 사항 저장'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
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

class _FirstSubmissionNotice extends StatelessWidget {
  const _FirstSubmissionNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "첫 출시 버전입니다. Apple 정책상 'What's New'(이 버전의 새로운 기능)는 "
              "두 번째 버전부터 입력 가능합니다. 이 앱은 아직 한 번도 게시된 적이 없어 "
              "입력이 비활성화되어 있습니다.",
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        error.toString(),
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}
