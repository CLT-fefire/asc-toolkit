import 'package:flutter/material.dart';

import '../../models/app_store_version_localization.dart';
import '../../models/team.dart';
import '../../services/asc_api_client.dart';
import 'section_widgets.dart';

/// `appStoreVersionLocalizations` PATCH 영역.
/// whatsNew / description / keywords / promotionalText 4개 필드 편집.
class VersionLocalizationSection extends StatefulWidget {
  const VersionLocalizationSection({
    super.key,
    required this.team,
    required this.client,
    required this.localization,
    required this.isFirstSubmission,
    required this.onUpdated,
  });

  final Team team;
  final AscApiClient client;
  final AppStoreVersionLocalization? localization;
  final bool isFirstSubmission;
  final ValueChanged<AppStoreVersionLocalization> onUpdated;

  @override
  State<VersionLocalizationSection> createState() =>
      _VersionLocalizationSectionState();
}

class _VersionLocalizationSectionState
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
    if (oldWidget.localization?.id != widget.localization?.id ||
        oldWidget.localization?.whatsNew != widget.localization?.whatsNew ||
        oldWidget.localization?.description !=
            widget.localization?.description ||
        oldWidget.localization?.keywords != widget.localization?.keywords ||
        oldWidget.localization?.promotionalText !=
            widget.localization?.promotionalText ||
        oldWidget.localization?.supportUrl !=
            widget.localization?.supportUrl ||
        oldWidget.localization?.marketingUrl !=
            widget.localization?.marketingUrl) {
      _syncControllers();
      _error = null;
    }
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
    final loc = widget.localization;
    if (loc == null) return;
    final diff = _diff();
    if (diff.isEmpty) {
      _toast('변경된 내용이 없습니다.');
      return;
    }
    if (diff.containsKey('whatsNew') &&
        (diff['whatsNew']?.length ?? 0) < 4) {
      _toast("ASC 정책상 'What's New'는 최소 4자 이상 입력해야 합니다.");
      return;
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
      if (!mounted) return;
      widget.onUpdated(updated);
      _toast("'${loc.locale}' 버전 정보 저장 완료 — ${diff.keys.join(', ')}");
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
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
    final enabled = widget.localization != null && !_saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel("이 버전의 새로운 기능 (What's New)"),
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
            helperText: 'ASC 정책: 최소 4자 이상 입력 필요',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel('설명 (Description)'),
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
        const SectionLabel('키워드 (Keywords)'),
        const SizedBox(height: 4),
        _Hint('콤마(,)로 구분. 100자 제한.'),
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
        const SectionLabel('프로모션 텍스트 (Promotional Text)'),
        const SizedBox(height: 4),
        _Hint('170자 제한. 앱 업데이트 없이 수시 변경 가능.'),
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
        const SectionLabel('지원 URL (Support URL)'),
        const SizedBox(height: 4),
        _Hint('App Store 상세 페이지의 "앱 지원" 링크. 필수 항목.'),
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
        const SectionLabel('마케팅 URL (Marketing URL)'),
        const SizedBox(height: 4),
        _Hint('App Store 상세 페이지의 "앱 웹사이트" 링크. 선택 항목.'),
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

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
