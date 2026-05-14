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
      _whatsNewCtrl.text = '';
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
      _whatsNewCtrl.text = '';
    });
    try {
      final locs = await _client.fetchLocalizations(widget.team, version.id);
      if (!mounted) return;
      final primary = _pickPrimaryLocalization(locs);
      setState(() {
        _localizations = locs;
        _selectedLocalization = primary;
        _whatsNewCtrl.text = primary?.whatsNew ?? '';
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

  /// 이 앱이 한 번도 App Store에 출시(승인·게시)된 적이 없으면 true.
  /// 첫 출시 버전에서는 ASC가 'What's New' 입력을 허용하지 않으므로 미리 잠금.
  bool get _isFirstSubmission {
    if (_versions.isEmpty) return false; // 판단 불가 — 정상 흐름으로 둠
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

  void _onSelectVersion(AppStoreVersion? v) {
    if (v == null || v.id == _selectedVersion?.id) return;
    setState(() => _selectedVersion = v);
    _loadLocalizations(v);
  }

  void _onSelectLocalization(AppStoreVersionLocalization? loc) {
    if (loc == null || loc.id == _selectedLocalization?.id) return;
    setState(() {
      _selectedLocalization = loc;
      _whatsNewCtrl.text = loc.whatsNew ?? '';
    });
  }

  Future<void> _save() async {
    final loc = _selectedLocalization;
    if (loc == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _client.updateWhatsNew(
        widget.team,
        loc.id,
        _whatsNewCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _selectedLocalization = updated;
        _localizations = _localizations
            .map((l) => l.id == updated.id ? updated : l)
            .toList(growable: false);
        _whatsNewCtrl.text = updated.whatsNew ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("'${loc.locale}' 로케일의 'What's New' 저장 완료"),
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
            maxLines: 10,
            minLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(
              hintText: _isFirstSubmission
                  ? '첫 출시 버전이라 입력이 비활성화되어 있습니다.'
                  : '예: 버그 수정 및 성능 개선.\n   - 새 기능 …\n   - 알려진 이슈 …',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ErrorCard(error: _error!),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: (_selectedLocalization == null ||
                      _saving ||
                      _isFirstSubmission)
                  ? null
                  : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '저장 중…' : '저장'),
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
