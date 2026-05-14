import 'package:flutter/material.dart';

import '../../data/app_category_display_names.dart';
import '../../models/app_category.dart';
import '../../models/app_info.dart';
import '../../models/app_info_localization.dart';
import '../../models/parsed_docx.dart';
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
    this.parsedSection,
  });

  final Team team;
  final AscApiClient client;
  final AppInfo? appInfo;
  final AppInfoLocalization? localization;
  final List<AppCategory> categories;
  final ValueChanged<AppInfoLocalization> onLocalizationUpdated;
  final VoidCallback onCategoriesUpdated;

  /// 워드 파일에서 파싱한 현재 로케일의 데이터. null이면 자동 적용 없음.
  /// name / subtitle만 자동 적용 (description은 VersionLocalization 쪽).
  final ParsedLocaleSection? parsedSection;

  @override
  State<AppInfoSection> createState() => AppInfoSectionState();
}

class AppInfoSectionState extends State<AppInfoSection> {
  // 이름/부제/개인정보처리방침
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _subtitleCtrl = TextEditingController();
  final TextEditingController _privacyUrlCtrl = TextEditingController();
  final TextEditingController _privacyTextCtrl = TextEditingController();
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
    final locChanged = oldWidget.localization?.id != widget.localization?.id ||
        oldWidget.localization?.name != widget.localization?.name ||
        oldWidget.localization?.subtitle != widget.localization?.subtitle ||
        oldWidget.localization?.privacyPolicyUrl !=
            widget.localization?.privacyPolicyUrl ||
        oldWidget.localization?.privacyPolicyText !=
            widget.localization?.privacyPolicyText;

    if (locChanged) {
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

    // 워드 파일 자동 적용
    final parsedChanged =
        oldWidget.parsedSection?.locale != widget.parsedSection?.locale ||
            oldWidget.parsedSection?.name != widget.parsedSection?.name ||
            oldWidget.parsedSection?.subtitle != widget.parsedSection?.subtitle;
    if (locChanged || parsedChanged) {
      _applyParsedSection();
    }
  }

  void _applyParsedSection() {
    final parsed = widget.parsedSection;
    if (parsed == null) return;
    if (parsed.name != null && parsed.name!.isNotEmpty) {
      // 30자 제한
      final n = parsed.name!;
      _nameCtrl.text = n.length <= 30 ? n : n.substring(0, 30);
    }
    if (parsed.subtitle != null && parsed.subtitle!.isNotEmpty) {
      final s = parsed.subtitle!;
      _subtitleCtrl.text = s.length <= 30 ? s : s.substring(0, 30);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _subtitleCtrl.dispose();
    _privacyUrlCtrl.dispose();
    _privacyTextCtrl.dispose();
    super.dispose();
  }

  void _syncLocControllers() {
    _nameCtrl.text = widget.localization?.name ?? '';
    _subtitleCtrl.text = widget.localization?.subtitle ?? '';
    _privacyUrlCtrl.text = widget.localization?.privacyPolicyUrl ?? '';
    _privacyTextCtrl.text = widget.localization?.privacyPolicyText ?? '';
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
    if (changed(loc.privacyPolicyUrl, _privacyUrlCtrl.text)) {
      result['privacyPolicyUrl'] = _privacyUrlCtrl.text;
    }
    if (changed(loc.privacyPolicyText, _privacyTextCtrl.text)) {
      result['privacyPolicyText'] = _privacyTextCtrl.text;
    }
    return result;
  }

  Future<void> _saveLocalization() async {
    await saveLocalizationIfChanged(showToastOnNoChange: true);
  }

  /// 외부 트리거용. 변경 있으면 PATCH, 없으면 무동작.
  /// 반환: 실제 저장 성공 시 true.
  Future<bool> saveLocalizationIfChanged(
      {bool showToastOnNoChange = false}) async {
    final loc = widget.localization;
    if (loc == null) return false;
    if (!(widget.appInfo?.isEditable ?? false)) {
      return false; // read-only AppInfo는 trigger 무시
    }
    final diff = _locDiff();
    if (diff.isEmpty) {
      if (showToastOnNoChange) _toast('변경된 내용이 없습니다.');
      return false;
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
      if (!mounted) return false;
      widget.onLocalizationUpdated(updated);
      _toast("'${loc.locale}' 앱 정보 저장 완료 — ${diff.keys.join(', ')}");
      return true;
    } catch (e) {
      if (mounted) setState(() => _locError = e);
      return false;
    } finally {
      if (mounted) setState(() => _savingLoc = false);
    }
  }

  bool get hasLocChanges => _locDiff().isNotEmpty;

  // ---- 카테고리 저장 ----

  bool get _categoriesChanged =>
      _selectedPrimary != widget.appInfo?.primaryCategoryId ||
      _selectedSecondary != widget.appInfo?.secondaryCategoryId;

  Future<void> _saveCategories() async {
    await saveCategoriesIfChanged(showToastOnNoChange: true);
  }

  Future<bool> saveCategoriesIfChanged(
      {bool showToastOnNoChange = false}) async {
    final info = widget.appInfo;
    if (info == null) return false;
    if (!info.isEditable) return false;
    if (!_categoriesChanged) {
      if (showToastOnNoChange) _toast('변경된 내용이 없습니다.');
      return false;
    }
    if (_selectedPrimary == null) {
      _toast('Primary 카테고리는 필수입니다.');
      return false;
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
      if (!mounted) return false;
      widget.onCategoriesUpdated();
      _toast('카테고리 저장 완료');
      return true;
    } catch (e) {
      if (mounted) setState(() => _catsError = e);
      return false;
    } finally {
      if (mounted) setState(() => _savingCats = false);
    }
  }

  bool get hasCatsChanges =>
      (widget.appInfo?.isEditable ?? false) && _categoriesChanged;

  /// 핀포인트 뱃지용 — 변경된 localization 필드 이름 집합.
  Set<String> get _changedLocFields => _locDiff().keys.toSet();

  /// 핀포인트 뱃지용 — 카테고리 변경 (primary/secondary).
  bool get _primaryChanged =>
      _selectedPrimary != widget.appInfo?.primaryCategoryId;
  bool get _secondaryChanged =>
      _selectedSecondary != widget.appInfo?.secondaryCategoryId;

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
    final changedLoc = _changedLocFields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: '앱 정보',
          updated: hasLocChanges || hasCatsChanges,
        ),
        const SizedBox(height: 16),
        if (widget.appInfo != null && !editable) ...[
          _ReadOnlyAppInfoNotice(stateLabel: stateLabel),
          const SizedBox(height: 12),
        ],
        FieldLabel(
          '이름 (Name)',
          changed: changedLoc.contains('name'),
          hint: '30자 제한. 앱의 공식 명칭.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          enabled: widget.localization != null && !_savingLoc && editable,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '앱의 공식 명칭',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FieldLabel(
          '부제 (Subtitle)',
          changed: changedLoc.contains('subtitle'),
          hint: '30자 제한. 아이콘 아래 표시되는 짧은 설명.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _subtitleCtrl,
          enabled: widget.localization != null && !_savingLoc && editable,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '예: 최애와 나만의 프라이빗 메시지',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FieldLabel(
          '개인정보처리방침 URL',
          changed: changedLoc.contains('privacyPolicyUrl'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _privacyUrlCtrl,
          enabled: widget.localization != null && !_savingLoc && editable,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/privacy',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FieldLabel(
          '개인정보처리방침 본문 (선택)',
          changed: changedLoc.contains('privacyPolicyText'),
          hint: '1000자 제한. 카테고리에 따라 URL 대신/함께 본문 요구 시 사용.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _privacyTextCtrl,
          enabled: widget.localization != null && !_savingLoc && editable,
          maxLines: 6,
          minLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: '본문이 필요한 경우만 입력',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
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
          label: '이름/부제/개인정보처리방침 저장',
        ),
        const SizedBox(height: 32),
        FieldLabel(
          'Primary 카테고리',
          changed: _primaryChanged,
          hint: '앱 전체에 1개. 필수.',
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedPrimary,
          decoration: const InputDecoration(
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
        const SizedBox(height: 16),
        FieldLabel(
          'Secondary 카테고리',
          changed: _secondaryChanged,
          hint: '선택. (없음)으로 두면 빈 값.',
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _selectedSecondary,
          decoration: const InputDecoration(
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
