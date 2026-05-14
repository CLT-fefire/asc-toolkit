import 'package:flutter/material.dart';

import '../../models/app_store_version_localization.dart';
import '../../models/parsed_docx.dart';
import '../../models/team.dart';
import '../../services/asc_api_client.dart';
import 'section_widgets.dart';

/// `appStoreVersionLocalizations` PATCH 영역.
/// whatsNew / description / keywords / promotionalText / supportUrl / marketingUrl 편집.
class VersionLocalizationSection extends StatefulWidget {
  const VersionLocalizationSection({
    super.key,
    required this.team,
    required this.client,
    required this.localization,
    required this.isFirstSubmission,
    required this.onUpdated,
    this.parsedSection,
    this.parsedKeywords,
  });

  final Team team;
  final AscApiClient client;
  final AppStoreVersionLocalization? localization;
  final bool isFirstSubmission;
  final ValueChanged<AppStoreVersionLocalization> onUpdated;

  /// 워드 파일에서 파싱한 현재 로케일의 데이터. null이면 자동 적용 없음.
  /// 워드 변경 시 description만 자동 적용 (name·subtitle은 AppInfo 쪽).
  final ParsedLocaleSection? parsedSection;

  /// 키워드 텍스트 파일에서 파싱된 현재 로케일의 키워드. null이면 자동 적용 없음.
  /// 100자 초과 시 잘라서 적용.
  final String? parsedKeywords;

  @override
  State<VersionLocalizationSection> createState() =>
      VersionLocalizationSectionState();
}

class VersionLocalizationSectionState
    extends State<VersionLocalizationSection> {
  final TextEditingController _whatsNewCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _keywordsCtrl = TextEditingController();
  final TextEditingController _promotionalCtrl = TextEditingController();
  final TextEditingController _supportUrlCtrl = TextEditingController();
  final TextEditingController _marketingUrlCtrl = TextEditingController();

  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant VersionLocalizationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final locChanged = oldWidget.localization?.id != widget.localization?.id ||
        oldWidget.localization?.whatsNew != widget.localization?.whatsNew ||
        oldWidget.localization?.description !=
            widget.localization?.description ||
        oldWidget.localization?.keywords != widget.localization?.keywords ||
        oldWidget.localization?.promotionalText !=
            widget.localization?.promotionalText ||
        oldWidget.localization?.supportUrl !=
            widget.localization?.supportUrl ||
        oldWidget.localization?.marketingUrl !=
            widget.localization?.marketingUrl;

    if (locChanged) {
      _syncControllers();
      _error = null;
    }

    // 워드 파싱 결과가 새로 들어왔거나 로케일이 바뀐 시점에 description만 자동 적용.
    // 부제 다음 ~ 구분선 사이 줄들은 워드 양식상 안내 문구라 ASC에 매핑하지 않음.
    final parsedChanged =
        oldWidget.parsedSection?.locale != widget.parsedSection?.locale ||
            oldWidget.parsedSection?.description !=
                widget.parsedSection?.description;
    final keywordsChanged = oldWidget.parsedKeywords != widget.parsedKeywords;
    if (locChanged || parsedChanged) {
      _applyParsedSection();
    }
    if (locChanged || keywordsChanged) {
      _applyParsedKeywords();
    }
  }

  void _applyParsedSection() {
    final parsed = widget.parsedSection;
    if (parsed == null) return;
    if (parsed.description != null && parsed.description!.isNotEmpty) {
      _descriptionCtrl.text = parsed.description!;
    }
  }

  void _applyParsedKeywords() {
    final raw = widget.parsedKeywords;
    if (raw == null || raw.isEmpty) return;
    // ASC 키워드 100자 제한 — 콤마 단위 토큰을 유지하면서 잘라낸다.
    _keywordsCtrl.text = _truncateKeywords(raw, 100);
  }

  /// 콤마 구분 키워드 문자열을 [max]자 이내로 자른다.
  /// 마지막에 잘리는 토큰이 부분 단어가 되지 않도록, 콤마 경계에서 컷.
  String _truncateKeywords(String input, int max) {
    final compact = input.replaceAll(RegExp(r'\s*,\s*'), ',').trim();
    if (compact.length <= max) return compact;
    final tokens = compact.split(',');
    final buf = StringBuffer();
    for (final t in tokens) {
      final extra = buf.isEmpty ? t.length : t.length + 1; // +1 for comma
      if (buf.length + extra > max) break;
      if (buf.isNotEmpty) buf.write(',');
      buf.write(t);
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _whatsNewCtrl.dispose();
    _descriptionCtrl.dispose();
    _keywordsCtrl.dispose();
    _promotionalCtrl.dispose();
    _supportUrlCtrl.dispose();
    _marketingUrlCtrl.dispose();
    super.dispose();
  }

  void _syncControllers() {
    final loc = widget.localization;
    _whatsNewCtrl.text = loc?.whatsNew ?? '';
    _descriptionCtrl.text = loc?.description ?? '';
    _keywordsCtrl.text = loc?.keywords ?? '';
    _promotionalCtrl.text = loc?.promotionalText ?? '';
    _supportUrlCtrl.text = loc?.supportUrl ?? '';
    _marketingUrlCtrl.text = loc?.marketingUrl ?? '';
  }

  Map<String, String> _diff() {
    final loc = widget.localization;
    if (loc == null) return const {};
    final result = <String, String>{};
    bool changed(String? before, String after) => (before ?? '') != after;

    if (!widget.isFirstSubmission &&
        changed(loc.whatsNew, _whatsNewCtrl.text)) {
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
    if (changed(loc.supportUrl, _supportUrlCtrl.text)) {
      result['supportUrl'] = _supportUrlCtrl.text;
    }
    if (changed(loc.marketingUrl, _marketingUrlCtrl.text)) {
      result['marketingUrl'] = _marketingUrlCtrl.text;
    }
    return result;
  }

  Future<void> _save() async {
    await saveIfChanged(showToastOnNoChange: true);
  }

  /// 외부에서 트리거 가능한 저장 메서드. 변경 없으면 무동작 (조용히 종료).
  /// [showToastOnNoChange]가 true면 변경 없을 때 사용자에게 토스트 안내.
  /// 반환값: 실제 PATCH가 성공했으면 true, skip/실패면 false.
  Future<bool> saveIfChanged({bool showToastOnNoChange = false}) async {
    final loc = widget.localization;
    if (loc == null) return false;
    final diff = _diff();
    if (diff.isEmpty) {
      if (showToastOnNoChange) _toast('변경된 내용이 없습니다.');
      return false;
    }
    if (diff.containsKey('whatsNew') &&
        (diff['whatsNew']?.length ?? 0) < 4) {
      _toast("ASC 정책상 'What's New'는 최소 4자 이상 입력해야 합니다.");
      return false;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.client.updateLocalizationFields(
        widget.team,
        loc.id,
        diff,
      );
      if (!mounted) return false;
      widget.onUpdated(updated);
      _toast("'${loc.locale}' 버전 정보 저장 완료 — ${diff.keys.join(', ')}");
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 현재 controller 값이 ASC 원본과 다른지. UI 뱃지/전체 적용 판단용.
  bool get hasChanges => _diff().isNotEmpty;

  /// 핀포인트 뱃지용 — 변경된 필드 이름 집합.
  Set<String> get _changedFields => _diff().keys.toSet();

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
    final enabled = widget.localization != null && !_saving;
    final changed = _changedFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: '버전 로컬라이제이션',
          updated: hasChanges,
        ),
        const SizedBox(height: 16),
        FieldLabel(
          "이 버전의 새로운 기능 (What's New)",
          changed: changed.contains('whatsNew'),
          hint: 'ASC 정책: 최소 4자 이상 입력 필요',
        ),
        const SizedBox(height: 8),
        if (widget.isFirstSubmission) ...[
          const FirstSubmissionNotice(),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _whatsNewCtrl,
          enabled: enabled && !widget.isFirstSubmission,
          maxLines: 8,
          minLines: 4,
          maxLength: 4000,
          decoration: InputDecoration(
            hintText: widget.isFirstSubmission
                ? '첫 출시 버전이라 입력이 비활성화되어 있습니다.'
                : '예: 버그 수정 및 성능 개선.\n   - 새 기능 …\n   - 알려진 이슈 …',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),
        FieldLabel(
          '설명 (Description)',
          changed: changed.contains('description'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionCtrl,
          enabled: enabled,
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
        FieldLabel(
          '키워드 (Keywords)',
          changed: changed.contains('keywords'),
          hint: '콤마(,)로 구분. 100자 제한.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keywordsCtrl,
          enabled: enabled,
          maxLines: 2,
          minLines: 1,
          maxLength: 100,
          decoration: const InputDecoration(
            hintText: '예: 게임,RPG,어드벤처,캐주얼',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FieldLabel(
          '프로모션 텍스트 (Promotional Text)',
          changed: changed.contains('promotionalText'),
          hint: '170자 제한. 앱 업데이트 없이 수시 변경 가능.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _promotionalCtrl,
          enabled: enabled,
          maxLines: 4,
          minLines: 2,
          maxLength: 170,
          decoration: const InputDecoration(
            hintText: '예: 한정 이벤트 진행 중! 지금 다운로드하고 …',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),
        FieldLabel(
          '지원 URL (Support URL)',
          changed: changed.contains('supportUrl'),
          hint: 'App Store 상세 페이지의 "앱 지원" 링크. 필수 항목.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _supportUrlCtrl,
          enabled: enabled,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/support',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FieldLabel(
          '마케팅 URL (Marketing URL)',
          changed: changed.contains('marketingUrl'),
          hint: 'App Store 상세 페이지의 "앱 웹사이트" 링크. 선택 항목.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _marketingUrlCtrl,
          enabled: enabled,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          SectionErrorCard(error: _error!),
        ],
        const SizedBox(height: 16),
        SaveButton(
          saving: _saving,
          onPressed: widget.localization == null ? null : _save,
        ),
      ],
    );
  }
}

