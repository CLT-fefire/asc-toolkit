import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/app_store_version.dart';
import '../models/app_store_version_localization.dart';
import '../models/app_summary.dart';
import '../models/parsed_screenshot_bundle.dart';
import '../models/team.dart';
import '../services/asc_api_client.dart';
import '../services/screenshot_folder_scanner.dart';
import '../services/screenshot_uploader.dart';

/// 옵션 D — 스크린샷 일괄 업로드 전용 화면.
///
/// AppDetail 의 locale chip 흐름과 분리되어 있다. 이 화면은 폴더 단위 일괄 업로드만 다루며
/// locale 은 폴더명에서 자동 추출된다 (`01_KR` → `ko`).
class ScreenshotUploadScreen extends StatefulWidget {
  const ScreenshotUploadScreen({
    super.key,
    required this.team,
    required this.client,
    required this.app,
    required this.version,
    required this.versionLocalizations,
  });

  final Team team;
  final AscApiClient client;
  final AppSummary app;
  final AppStoreVersion version;
  final List<AppStoreVersionLocalization> versionLocalizations;

  @override
  State<ScreenshotUploadScreen> createState() => _ScreenshotUploadScreenState();
}

class _ScreenshotUploadScreenState extends State<ScreenshotUploadScreen> {
  ParsedScreenshotBundle? _bundle;
  bool _uploading = false;
  ScreenshotUploadProgress? _progress;
  ScreenshotUploadResult? _lastResult;

  bool get _isEditableVersion => widget.version.isLikelyEditable;

  Map<String, String> get _vlocIdByLocale => {
        for (final l in widget.versionLocalizations) l.locale: l.id,
      };

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath();
    if (path == null) return;
    final bundle = ScreenshotFolderScanner().scan(Directory(path));
    setState(() {
      _bundle = bundle;
      _lastResult = null;
    });
  }

  void _clearBundle() {
    setState(() {
      _bundle = null;
      _lastResult = null;
      _progress = null;
    });
  }

  Future<void> _applyAll() async {
    final bundle = _bundle;
    if (bundle == null || bundle.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('스크린샷 일괄 업로드'),
        content: Text(
          '${bundle.groups.length}개 로케일에 총 ${bundle.totalFileCount}장을 업로드합니다.\n\n'
          '동일 디스플레이 타입의 기존 스크린샷은 모두 삭제된 후 새로 업로드됩니다. 진행하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('업로드'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _uploading = true;
      _lastResult = null;
      _progress = null;
    });

    final uploader = ScreenshotUploader(api: widget.client);
    final result = await uploader.upload(
      team: widget.team,
      bundle: bundle,
      localizationIdByLocale: _vlocIdByLocale,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _lastResult = result;
      _progress = null;
    });

    if (result.hasFailures) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _ScreenshotFailuresDialog(failures: result.failures),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('스크린샷 ${result.successFileCount}장 업로드 완료'),
        ),
      );
    }
  }

  Future<void> _openCleanupDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EmptySetCleanupDialog(
        team: widget.team,
        client: widget.client,
        versionLocalizations: widget.versionLocalizations,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBundle = _bundle != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.app.name} · v${widget.version.versionString} · 스크린샷',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '빈 set 정리',
            onPressed: _uploading ? null : _openCleanupDialog,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isEditableVersion)
                const _NoticeCard(
                  icon: Icons.lock_outline,
                  text: '이 버전은 편집 제한 상태입니다. 스크린샷 업로드가 비활성화됩니다.',
                )
              else ...[
                _FolderPickerRow(
                  rootPath: _bundle?.rootPath,
                  uploading: _uploading,
                  onPick: _pickFolder,
                  onClear: _clearBundle,
                ),
                if (hasBundle) ...[
                  const SizedBox(height: 16),
                  _BundleSummary(bundle: _bundle!),
                ],
                if (_uploading && _progress != null) ...[
                  const SizedBox(height: 16),
                  _ProgressView(progress: _progress!),
                ],
                if (hasBundle && !_uploading) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _bundle!.isEmpty ? null : _applyAll,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        '전체 적용 (${_bundle!.totalFileCount}장 업로드)',
                      ),
                    ),
                  ),
                ],
                if (_lastResult != null && !_lastResult!.hasFailures) ...[
                  const SizedBox(height: 16),
                  _SuccessNotice(count: _lastResult!.successFileCount),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderPickerRow extends StatelessWidget {
  const _FolderPickerRow({
    required this.rootPath,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  final String? rootPath;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: uploading ? null : onPick,
          icon: const Icon(Icons.folder_open),
          label: const Text('디자인팀 폴더 선택'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            rootPath ?? '예: 02_APPSTORE',
            style: TextStyle(
              color: rootPath == null
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (rootPath != null && !uploading)
          IconButton(
            tooltip: '폴더 선택 취소',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}

class _BundleSummary extends StatelessWidget {
  const _BundleSummary({required this.bundle});

  final ParsedScreenshotBundle bundle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '스캔 결과: ${bundle.groups.length}개 로케일 · 총 ${bundle.totalFileCount}장',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          for (final g in bundle.groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '✓  ${g.folderName}  →  ${g.locale}   (${g.fileCount}장, ${friendlyDisplayType(g.displayType)})',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          if (bundle.skippedItems.isNotEmpty) ...[
            const Divider(height: 16),
            Text(
              '스킵된 항목',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            for (final s in bundle.skippedItems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '⚠️  ${s.name}  — ${s.reason}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.progress});

  final ScreenshotUploadProgress progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.totalFiles == 0
        ? 0.0
        : progress.completedFiles / progress.totalFiles;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '진행: ${progress.groupIndex + 1}/${progress.groupCount} 그룹 '
            '— ${progress.folderName} (${progress.locale})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 6),
          Text(progress.stage),
        ],
      ),
    );
  }
}

class _SuccessNotice extends StatelessWidget {
  const _SuccessNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count장 업로드 완료. ASC 웹에서 순서를 확인해 주세요.',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotFailuresDialog extends StatelessWidget {
  const _ScreenshotFailuresDialog({required this.failures});

  final List<ScreenshotUploadFailure> failures;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('업로드 실패 (${failures.length}건)'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final f in failures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${f.folderName} · ${f.locale}'
                            '${f.fileName == null ? '' : ' · ${f.fileName}'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(f.reason),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

/// 비어 있는 ASC `appScreenshotSets` 식별 + 선택 삭제 다이얼로그.
///
/// 옵션 D 디버깅 중 누적된 빈 set (잘못된 displayType 으로 만들어진 것 등) 정리용.
/// 안전: 안 비어있는 set 은 후보에서 제외. 사용자가 체크박스로 선택해야만 삭제.
class _EmptySetCleanupDialog extends StatefulWidget {
  const _EmptySetCleanupDialog({
    required this.team,
    required this.client,
    required this.versionLocalizations,
  });

  final Team team;
  final AscApiClient client;
  final List<AppStoreVersionLocalization> versionLocalizations;

  @override
  State<_EmptySetCleanupDialog> createState() => _EmptySetCleanupDialogState();
}

class _EmptySetCleanupDialogState extends State<_EmptySetCleanupDialog> {
  bool _scanning = true;
  String? _error;
  List<_EmptySetEntry> _entries = const [];
  final Set<String> _selected = <String>{};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _entries = const [];
      _selected.clear();
    });
    final entries = <_EmptySetEntry>[];
    try {
      for (final vloc in widget.versionLocalizations) {
        final sets = await widget.client.fetchScreenshotSets(
          widget.team,
          vloc.id,
        );
        for (final s in sets) {
          final ids = await widget.client.fetchScreenshotIdsInSet(
            widget.team,
            s.id,
          );
          if (ids.isEmpty) {
            entries.add(_EmptySetEntry(
              locale: vloc.locale,
              setId: s.id,
              displayType: s.screenshotDisplayType,
            ));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _scanning = false;
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('빈 set 삭제'),
        content: Text('선택한 ${_selected.length}개 set 을 삭제합니다. 모두 비어 있는 상태입니다. 진행하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    final failures = <String>[];
    for (final id in _selected.toList()) {
      try {
        await widget.client.deleteScreenshotSet(widget.team, id);
      } catch (e) {
        failures.add('$id: $e');
      }
    }
    if (!mounted) return;
    final deleted = _selected.length - failures.length;
    setState(() => _deleting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? '$deleted개 set 삭제 완료'
              : '$deleted개 삭제됨, ${failures.length}건 실패',
        ),
      ),
    );
    if (mounted) await _scan();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('빈 스크린샷 set 정리')),
          IconButton(
            tooltip: '다시 스캔',
            onPressed: (_scanning || _deleting) ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 420,
        child: _scanning
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: SelectableText('스캔 실패: $_error'))
                : _entries.isEmpty
                    ? const Center(child: Text('빈 set 이 없습니다.'))
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (ctx, i) {
                          final e = _entries[i];
                          final checked = _selected.contains(e.setId);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: _deleting
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(e.setId);
                                      } else {
                                        _selected.remove(e.setId);
                                      }
                                    });
                                  },
                            title: Text(
                              '${e.locale} · ${friendlyDisplayType(e.displayType)} (${e.displayType})',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              e.setId,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          );
                        },
                      ),
      ),
      actions: [
        if (!_scanning && _entries.isNotEmpty)
          TextButton(
            onPressed: _deleting
                ? null
                : () => setState(() {
                      if (_selected.length == _entries.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(_entries.map((e) => e.setId));
                      }
                    }),
            child: Text(
              _selected.length == _entries.length ? '전체 해제' : '전체 선택',
            ),
          ),
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton.icon(
          onPressed: (_selected.isEmpty || _deleting) ? null : _deleteSelected,
          icon: _deleting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
          label: Text('선택 삭제 (${_selected.length})'),
        ),
      ],
    );
  }
}

class _EmptySetEntry {
  _EmptySetEntry({
    required this.locale,
    required this.setId,
    required this.displayType,
  });
  final String locale;
  final String setId;
  final String displayType;
}

/// ASC enum 을 사람이 읽기 좋은 라벨로.
String friendlyDisplayType(String ascType) {
  switch (ascType) {
    case 'APP_IPHONE_69':
      return 'iPhone (구 alias)';
    case 'APP_IPHONE_67':
      return 'iPhone 6.7"/6.9"';
    case 'APP_IPHONE_65':
      return 'iPhone 6.5"';
    case 'APP_IPHONE_61':
      return 'iPhone 6.3"';
    case 'APP_IPHONE_58':
      return 'iPhone 6.1"';
    case 'APP_IPHONE_55':
      return 'iPhone 5.5"';
    case 'APP_IPAD_PRO_3GEN_129':
      return 'iPad 13"';
    case 'APP_IPAD_PRO_129':
      return 'iPad 12.9"';
    case 'APP_IPAD_PRO_3GEN_11':
      return 'iPad 11"';
    default:
      return ascType;
  }
}
