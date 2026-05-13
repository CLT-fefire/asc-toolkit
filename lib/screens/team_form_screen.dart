import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/team.dart';
import '../services/team_repository.dart';

class TeamFormScreen extends StatefulWidget {
  const TeamFormScreen({
    super.key,
    required this.repository,
    this.initial,
  });

  final TeamRepository repository;
  final Team? initial;

  @override
  State<TeamFormScreen> createState() => _TeamFormScreenState();
}

class _TeamFormScreenState extends State<TeamFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _issuerCtrl;
  late final TextEditingController _keyIdCtrl;

  String? _p8Pem;
  String? _p8FileName;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _nameCtrl = TextEditingController(text: t?.name ?? '');
    _issuerCtrl = TextEditingController(text: t?.issuerId ?? '');
    _keyIdCtrl = TextEditingController(text: t?.keyId ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _issuerCtrl.dispose();
    _keyIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickP8() async {
    // .p8은 macOS LaunchServices에 등록된 확장자가 아니어서
    // 단일 TypeGroup만 지정하면 NSOpenPanel에서 회색으로 비활성화됨.
    // "모든 파일" 그룹을 함께 제공해 사용자가 드롭다운에서 선택할 수 있도록 함.
    const p8Group = XTypeGroup(
      label: 'App Store Connect Key (.p8)',
      extensions: <String>['p8'],
    );
    const anyGroup = XTypeGroup(label: '모든 파일');

    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[p8Group, anyGroup],
    );
    if (file == null) return;

    final content = await file.readAsString();
    if (!content.contains('BEGIN PRIVATE KEY')) {
      setState(() {
        _error = '선택한 파일이 PKCS#8 PEM 형식이 아닙니다 (.p8 키 본문이 필요).';
        _p8Pem = null;
        _p8FileName = null;
      });
      return;
    }
    setState(() {
      _p8Pem = content;
      _p8FileName = file.name;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final isNew = widget.initial == null;
    if (isNew && (_p8Pem == null || _p8Pem!.isEmpty)) {
      setState(() => _error = '.p8 키 파일을 첨부해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? p8 = _p8Pem;
      if (p8 == null && widget.initial != null) {
        p8 = await widget.repository.readP8(widget.initial!.id);
      }
      if (p8 == null || p8.isEmpty) {
        throw StateError('.p8 키 데이터가 비어 있습니다.');
      }
      final team = await widget.repository.upsert(
        id: widget.initial?.id,
        name: _nameCtrl.text.trim(),
        issuerId: _issuerCtrl.text.trim(),
        keyId: _keyIdCtrl.text.trim(),
        p8Pem: p8,
      );
      if (!mounted) return;
      Navigator.of(context).pop(team);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? '팀 추가' : '팀 편집')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '팀 이름 (표시용)',
                  hintText: '예: DearU 메인',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '팀 이름을 입력해주세요' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _issuerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Issuer ID',
                  hintText: '57246542-96fe-1a63-e053-0824d011072a',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Issuer ID를 입력해주세요' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _keyIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Key ID',
                  hintText: '예: 2X9R4HXF34',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Key ID를 입력해주세요' : null,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _saving ? null : _pickP8,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('.p8 키 첨부'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _p8FileName ??
                          (isNew ? '아직 선택된 파일 없음' : '기존 키 유지 (변경하려면 첨부)'),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
