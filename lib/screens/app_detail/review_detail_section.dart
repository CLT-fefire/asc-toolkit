import 'package:flutter/material.dart';

import '../../models/app_store_review_detail.dart';
import '../../models/team.dart';
import '../../services/asc_api_client.dart';
import 'section_widgets.dart';

/// 버전별 심사 정보 영역 — 연락처, 데모 계정, 메모.
class ReviewDetailSection extends StatefulWidget {
  const ReviewDetailSection({
    super.key,
    required this.team,
    required this.client,
    required this.reviewDetail,
    required this.onUpdated,
  });

  final Team team;
  final AscApiClient client;
  final AppStoreReviewDetail? reviewDetail;
  final ValueChanged<AppStoreReviewDetail> onUpdated;

  @override
  State<ReviewDetailSection> createState() => _ReviewDetailSectionState();
}

class _ReviewDetailSectionState extends State<ReviewDetailSection> {
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _demoAccountCtrl = TextEditingController();
  final TextEditingController _demoPasswordCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  bool _demoRequired = false;

  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ReviewDetailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reviewDetail?.id != widget.reviewDetail?.id) {
      _sync();
      _error = null;
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _demoAccountCtrl.dispose();
    _demoPasswordCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    final rd = widget.reviewDetail;
    _firstNameCtrl.text = rd?.contactFirstName ?? '';
    _lastNameCtrl.text = rd?.contactLastName ?? '';
    _phoneCtrl.text = rd?.contactPhone ?? '';
    _emailCtrl.text = rd?.contactEmail ?? '';
    _demoAccountCtrl.text = rd?.demoAccountName ?? '';
    _demoPasswordCtrl.text = rd?.demoAccountPassword ?? '';
    _notesCtrl.text = rd?.notes ?? '';
    _demoRequired = rd?.demoAccountRequired ?? false;
  }

  Map<String, dynamic> _diff() {
    final rd = widget.reviewDetail;
    if (rd == null) return const {};
    final result = <String, dynamic>{};
    bool sChanged(String? before, String after) => (before ?? '') != after;

    if (sChanged(rd.contactFirstName, _firstNameCtrl.text)) {
      result['contactFirstName'] = _firstNameCtrl.text;
    }
    if (sChanged(rd.contactLastName, _lastNameCtrl.text)) {
      result['contactLastName'] = _lastNameCtrl.text;
    }
    if (sChanged(rd.contactPhone, _phoneCtrl.text)) {
      result['contactPhone'] = _phoneCtrl.text;
    }
    if (sChanged(rd.contactEmail, _emailCtrl.text)) {
      result['contactEmail'] = _emailCtrl.text;
    }
    if (sChanged(rd.demoAccountName, _demoAccountCtrl.text)) {
      result['demoAccountName'] = _demoAccountCtrl.text;
    }
    if (sChanged(rd.demoAccountPassword, _demoPasswordCtrl.text)) {
      result['demoAccountPassword'] = _demoPasswordCtrl.text;
    }
    if (sChanged(rd.notes, _notesCtrl.text)) {
      result['notes'] = _notesCtrl.text;
    }
    if ((rd.demoAccountRequired ?? false) != _demoRequired) {
      result['demoAccountRequired'] = _demoRequired;
    }
    return result;
  }

  bool get _hasChanges => _diff().isNotEmpty;
  Set<String> get _changedFields => _diff().keys.toSet();

  Future<void> _save() async {
    final rd = widget.reviewDetail;
    if (rd == null) return;
    final diff = _diff();
    if (diff.isEmpty) {
      _toast('변경된 내용이 없습니다.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.client.updateReviewDetailFields(
        widget.team,
        rd.id,
        diff,
      );
      if (!mounted) return;
      widget.onUpdated(updated);
      _toast('심사 정보 저장 완료 — ${diff.keys.join(', ')}');
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
    final hasRd = widget.reviewDetail != null;
    final changed = _changedFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: '심사 정보 (App Review)',
          updated: _hasChanges,
        ),
        const SizedBox(height: 4),
        Text(
          'Apple 심사자에게 전달되는 정보. 선택한 버전에 귀속.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        if (!hasRd)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '이 버전의 심사 정보가 아직 생성되지 않았습니다. '
              'App Store Connect 웹에서 버전을 한 번 저장하면 자동 생성됩니다.',
            ),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FieldLabel(
                      '담당자 이름 (First)',
                      changed: changed.contains('contactFirstName'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _firstNameCtrl,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FieldLabel(
                      '담당자 성 (Last)',
                      changed: changed.contains('contactLastName'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lastNameCtrl,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(
            '담당자 전화번호',
            changed: changed.contains('contactPhone'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: '+82-10-1234-5678',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            '담당자 이메일',
            changed: changed.contains('contactEmail'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            enabled: !_saving,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _demoRequired,
            onChanged: _saving
                ? null
                : (v) => setState(() => _demoRequired = v),
            title: Row(
              children: [
                const Text('데모 계정 필요'),
                if (changed.contains('demoAccountRequired')) ...[
                  const SizedBox(width: 8),
                  const FieldChangeBadge(),
                ],
              ],
            ),
            subtitle: const Text('심사자가 로그인해야 앱 기능을 확인할 수 있는 경우 ON'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          FieldLabel(
            '데모 계정 이름',
            changed: changed.contains('demoAccountName'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _demoAccountCtrl,
            enabled: !_saving && _demoRequired,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            '데모 계정 비밀번호',
            changed: changed.contains('demoAccountPassword'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _demoPasswordCtrl,
            enabled: !_saving && _demoRequired,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            '메모 (Notes)',
            changed: changed.contains('notes'),
            hint: '심사자가 알아야 할 추가 정보. 4000자 제한.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            enabled: !_saving,
            maxLines: 6,
            minLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SectionErrorCard(error: _error!),
          ],
          const SizedBox(height: 16),
          SaveButton(
            saving: _saving,
            onPressed: _save,
            label: '심사 정보 저장',
          ),
        ],
      ],
    );
  }
}
