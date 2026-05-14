import 'package:flutter/material.dart';

import '../../data/app_category_display_names.dart';
import '../../models/app_category.dart';
import '../../models/app_info.dart';
import '../../models/app_info_localization.dart';
import '../../models/team.dart';
import '../../services/asc_api_client.dart';
import 'section_widgets.dart';

/// 앱 정보 영역 — 이름·부제(로케일별) + 카테고리(앱 전체).
/// 두 PATCH는 서로 다른 endpoint이므로 저장 버튼도 분리.
class AppInfoSection extends StatefulWidget {
  const AppInfoSection({
    super.key,
    required this.team,
    required this.client,
    required this.appInfo,
    required this.localization,
    required this.categories,
    required this.onLocalizationUpdated,
    required this.onCategoriesUpdated,
  });

  final Team team;
  final AscApiClient client;
  final AppInfo? appInfo;
  final AppInfoLocalization? localization;
  final List<AppCategory> categories;
  final ValueChanged<AppInfoLocalization> onLocalizationUpdated;
  final VoidCallback onCategoriesUpdated;

  @override
  State<AppInfoSection> createState() => _AppInfoSectionState();
}

class _AppInfoSectionState extends State<AppInfoSection> {
  // 이름/부제
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _subtitleCtrl = TextEditingController();
  bool _savingLoc = false;
  Object? _locError;

  // 카테고리
  String? _selectedPrimary;
  String? _selectedSecondary;
  bool _savingCats = false;
  Object? _catsError;

  @override
  void initState() {
    super.initState();
    _syncLocControllers();
    _syncCategoryState();
  }

  @override
  void didUpdateWidget(covariant AppInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localization?.id != widget.localization?.id ||
        oldWidget.localization?.name != widget.localization?.name ||
        oldWidget.localization?.subtitle != widget.localization?.subtitle) {
      _syncLocControllers();
      _locError = null;
    }
    if (oldWidget.appInfo?.id != widget.appInfo?.id ||
        oldWidget.appInfo?.primaryCategoryId !=
            widget.appInfo?.primaryCategoryId ||
        oldWidget.appInfo?.secondaryCategoryId !=
            widget.appInfo?.secondaryCategoryId) {
      _syncCategoryState();
      _catsError = null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  void _syncLocControllers() {
    _nameCtrl.text = widget.localization?.name ?? '';
    _subtitleCtrl.text = widget.localization?.subtitle ?? '';
  }

  void _syncCategoryState() {
    _selectedPrimary = widget.appInfo?.primaryCategoryId;
    _selectedSecondary = widget.appInfo?.secondaryCategoryId;
  }

  // ---- 이름/부제 저장 ----

  Map<String, String> _locDiff() {
    final loc = widget.localization;
    if (loc == null) return const {};
    final result = <String, String>{};
    bool changed(String? before, String after) => (before ?? '') != after;
    if (changed(loc.name, _nameCtrl.text)) result['name'] = _nameCtrl.text;
    if (changed(loc.subtitle, _subtitleCtrl.text)) {
      result['subtitle'] = _subtitleCtrl.text;
    }
    return result;
  }

  Future<void> _saveLocalization() async {
    final loc = widget.localization;
    if (loc == null) return;
    final diff = _locDiff();
    if (diff.isEmpty) {
      _toast('변경된 내용이 없습니다.');
      return;
    }
    setState(() {
      _savingLoc = true;
      _locError = null;
    });
    try {
      final updated = await widget.client.updateAppInfoLocalizationFields(
        widget.team,
        loc.id,
        diff,
      );
      if (!mounted) return;
      widget.onLocalizationUpdated(updated);
      _toast("'${loc.locale}' 앱 정보 저장 완료 — ${diff.keys.join(', ')}");
    } catch (e) {
      if (mounted) setState(() => _locError = e);
    } finally {
      if (mounted) setState(() => _savingLoc = false);
    }
  }

  // ---- 카테고리 저장 ----

  bool get _categoriesChanged =>
      _selectedPrimary != widget.appInfo?.primaryCategoryId ||
      _selectedSecondary != widget.appInfo?.secondaryCategoryId;

  Future<void> _saveCategories() async {
    final info = widget.appInfo;
    if (info == null) return;
    if (!_categoriesChanged) {
      _toast('변경된 내용이 없습니다.');
      return;
    }
    if (_selectedPrimary == null) {
      _toast('Primary 카테고리는 필수입니다.');
      return;
    }
    setState(() {
      _savingCats = true;
      _catsError = null;
    });
    try {
      await widget.client.updateAppInfoCategories(
        widget.team,
        info.id,
        primaryCategoryId: _selectedPrimary!,
        secondaryCategoryId: _selectedSecondary,
      );
      if (!mounted) return;
      widget.onCategoriesUpdated();
      _toast('카테고리 저장 완료');
    } catch (e) {
      if (mounted) setState(() => _catsError = e);
    } finally {
      if (mounted) setState(() => _savingCats = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.appInfo?.isEditable ?? false;
    final stateLabel = widget.appInfo?.state ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('이름 / 부제 (App Info)'),
        const SizedBox(height: 4),
        Text(
          '로케일별. 이름·부제 각각 30자 제한.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (widget.appInfo != null && !editable) ...[
          const SizedBox(height: 8),
          _ReadOnlyAppInfoNotice(stateLabel: stateLabel),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          enabled: widget.localization != null && !_savingLoc && editable,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: '이름 (Name)',
            hintText: '앱의 공식 명칭',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _subtitleCtrl,
          enabled: widget.localization != null && !_savingLoc && editable,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: '부제 (Subtitle)',
            hintText: '아이콘 아래 표시되는 짧은 설명',
            border: OutlineInputBorder(),
          ),
        ),
        if (_locError != null) ...[
          const SizedBox(height: 8),
          SectionErrorCard(error: _locError!),
        ],
        const SizedBox(height: 12),
        SaveButton(
          saving: _savingLoc,
          onPressed: (widget.localization == null || !editable)
              ? null
              : _saveLocalization,
          label: '이름/부제 저장',
        ),
        const SizedBox(height: 32),
        const SectionLabel('카테고리 (Categories)'),
        const SizedBox(height: 4),
        Text(
          '앱 전체에 1개씩만. Primary는 필수, Secondary는 선택.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedPrimary,
          decoration: const InputDecoration(
            labelText: 'Primary 카테고리',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in widget.categories)
              DropdownMenuItem(value: c.id, child: Text(categoryDisplayName(c.id))),
          ],
          onChanged: (widget.appInfo == null || _savingCats || !editable)
              ? null
              : (v) => setState(() => _selectedPrimary = v),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _selectedSecondary,
          decoration: const InputDecoration(
            labelText: 'Secondary 카테고리 (선택)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('(없음)'),
            ),
            for (final c in widget.categories)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text(categoryDisplayName(c.id)),
              ),
          ],
          onChanged: (widget.appInfo == null || _savingCats || !editable)
              ? null
              : (v) => setState(() => _selectedSecondary = v),
        ),
        if (_catsError != null) ...[
          const SizedBox(height: 8),
          SectionErrorCard(error: _catsError!),
        ],
        const SizedBox(height: 12),
        SaveButton(
          saving: _savingCats,
          onPressed: (widget.appInfo == null || !editable)
              ? null
              : _saveCategories,
          label: '카테고리 저장',
        ),
      ],
    );
  }
}

/// LIVE/심사 중 등 read-only 상태의 AppInfo에서 편집 시도를 차단하는 안내.
class _ReadOnlyAppInfoNotice extends StatelessWidget {
  const _ReadOnlyAppInfoNotice({required this.stateLabel});
  final String stateLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '이 App Info는 현재 $stateLabel 상태라 이름·부제·카테고리를 수정할 수 없습니다.\n'
              "이미 출시된 정보(read-only)이거나 심사 중인 경우, App Store Connect 웹에서 '새 버전 추가'를 통해 "
              '편집 가능한 App Info(PREPARE_FOR_SUBMISSION)를 먼저 만들어야 합니다.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
