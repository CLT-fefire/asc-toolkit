import 'package:flutter/material.dart';

import '../../models/app_notification_config.dart';
import '../../models/team.dart';
import '../../services/asc_api_client.dart';
import 'section_widgets.dart';

/// 앱의 App Store Server Notifications V2 URL 설정.
/// 프로덕션 / 샌드박스 두 URL + 각각의 버전(V1/V2)을 한 화면에서 편집.
class NotificationConfigSection extends StatefulWidget {
  const NotificationConfigSection({
    super.key,
    required this.team,
    required this.client,
    required this.appId,
    required this.config,
    required this.onUpdated,
  });

  final Team team;
  final AscApiClient client;
  final String appId;
  final AppNotificationConfig? config;
  final ValueChanged<AppNotificationConfig> onUpdated;

  @override
  State<NotificationConfigSection> createState() =>
      _NotificationConfigSectionState();
}

class _NotificationConfigSectionState extends State<NotificationConfigSection> {
  static const _versionOptions = ['V1', 'V2'];

  final TextEditingController _prodUrlCtrl = TextEditingController();
  final TextEditingController _sandboxUrlCtrl = TextEditingController();

  String? _prodVersion;
  String? _sandboxVersion;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant NotificationConfigSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config?.subscriptionStatusUrl !=
            widget.config?.subscriptionStatusUrl ||
        oldWidget.config?.subscriptionStatusUrlVersion !=
            widget.config?.subscriptionStatusUrlVersion ||
        oldWidget.config?.subscriptionStatusUrlForSandbox !=
            widget.config?.subscriptionStatusUrlForSandbox ||
        oldWidget.config?.subscriptionStatusUrlVersionForSandbox !=
            widget.config?.subscriptionStatusUrlVersionForSandbox) {
      _sync();
      _error = null;
    }
  }

  @override
  void dispose() {
    _prodUrlCtrl.dispose();
    _sandboxUrlCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    final c = widget.config;
    _prodUrlCtrl.text = c?.subscriptionStatusUrl ?? '';
    _sandboxUrlCtrl.text = c?.subscriptionStatusUrlForSandbox ?? '';
    _prodVersion = c?.subscriptionStatusUrlVersion;
    _sandboxVersion = c?.subscriptionStatusUrlVersionForSandbox;
  }

  Map<String, String?> _diff() {
    final c = widget.config;
    if (c == null) return const {};
    final result = <String, String?>{};

    String? norm(String s) => s.trim().isEmpty ? null : s;

    final prodUrl = norm(_prodUrlCtrl.text);
    if (prodUrl != c.subscriptionStatusUrl) {
      result['subscriptionStatusUrl'] = prodUrl;
    }
    if (_prodVersion != c.subscriptionStatusUrlVersion) {
      result['subscriptionStatusUrlVersion'] = _prodVersion;
    }
    final sandboxUrl = norm(_sandboxUrlCtrl.text);
    if (sandboxUrl != c.subscriptionStatusUrlForSandbox) {
      result['subscriptionStatusUrlForSandbox'] = sandboxUrl;
    }
    if (_sandboxVersion != c.subscriptionStatusUrlVersionForSandbox) {
      result['subscriptionStatusUrlVersionForSandbox'] = _sandboxVersion;
    }
    return result;
  }

  Future<void> _save() async {
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
      final updated = await widget.client.updateAppNotificationConfig(
        widget.team,
        widget.appId,
        diff,
      );
      if (!mounted) return;
      widget.onUpdated(updated);
      _toast('서버 알림 URL 저장 완료 — ${diff.keys.join(', ')}');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('App Store 서버 알림 (Server Notifications)'),
        const SizedBox(height: 4),
        Text(
          'IAP 구독·결제 이벤트를 받을 서버 endpoint. V2 권장. 프로덕션과 샌드박스는 분리.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          '프로덕션',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: TextField(
                controller: _prodUrlCtrl,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://api.example.com/asn',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<String>(
                initialValue: _prodVersion,
                decoration: const InputDecoration(
                  labelText: '버전',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('(없음)'),
                  ),
                  for (final v in _versionOptions)
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _prodVersion = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '샌드박스',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: TextField(
                controller: _sandboxUrlCtrl,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://sandbox-api.example.com/asn',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<String>(
                initialValue: _sandboxVersion,
                decoration: const InputDecoration(
                  labelText: '버전',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('(없음)'),
                  ),
                  for (final v in _versionOptions)
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _sandboxVersion = v),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          SectionErrorCard(error: _error!),
        ],
        const SizedBox(height: 16),
        SaveButton(
          saving: _saving,
          onPressed: widget.config == null ? null : _save,
          label: '서버 알림 URL 저장',
        ),
      ],
    );
  }
}
