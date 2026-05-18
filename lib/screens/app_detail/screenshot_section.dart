import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/app_store_version.dart';
import '../../models/app_store_version_localization.dart';
import '../../models/parsed_screenshot_bundle.dart';
import '../../models/team.dart';
import '../../services/asc_api_client.dart';
import '../../services/screenshot_folder_scanner.dart';
import '../../services/screenshot_uploader.dart';
import 'section_widgets.dart';

/// 옵션 D — 스크린샷 일괄 업로드 섹션.
///
/// - 디자인팀이 전달한 부모 폴더(`02_APPSTORE/`) 한 번 선택
/// - 폴더 안 `{NN}_{LOCALE}` 하위 폴더를 자동 인식
/// - 각 (locale, displayType) 그룹의 기존 스크린샷 전체 삭제 후 새로 업로드
/// - 파일명 끝 `_NN` 순서로 등록
class ScreenshotSection extends StatefulWidget {
  const ScreenshotSection({
    super.key,
    required this.team,
    required this.client,
    required this.version,
    required this.versionLocalizations,
  });

  final Team team;
  final AscApiClient client;
  final AppStoreVersion? version;
  final List<AppStoreVersionLocalization> versionLocalizations;

  @override
  State<ScreenshotSection> createState() => _ScreenshotSectionState();
}

class _ScreenshotSectionState extends State<ScreenshotSection> {
  ParsedScreenshotBundle? _bundle;
  bool _uploading = false;
  bool _expanded = true;
  ScreenshotUploadProgress? _progress;
  ScreenshotUploadResult? _lastResult;

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

  bool get _isEditableVersion =>
      widget.version != null && widget.version!.isLikelyEditable;

  Map<String, String> get _vlocIdByLocale => {
        for (final l in widget.versionLocalizations) l.locale: l.id,
      };

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

  @override
  Widget build(BuildContext context) {
    final hasBundle = _bundle != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: '스크린샷',
          updated: hasBundle && !_uploading,
          expanded: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              _SuccessNotice(count: _lastResult!.successFileCount),
            ],
          ],
        ],
      ],
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
                '✓  ${g.folderName}  →  ${g.locale}   (${g.fileCount}장, ${_friendlyDisplayType(g.displayType)})',
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

String _friendlyDisplayType(String ascType) {
  switch (ascType) {
    case 'APP_IPHONE_69':
      return '6.9"';
    case 'APP_IPHONE_67':
      return '6.7"';
    case 'APP_IPHONE_65':
      return '6.5"';
    case 'APP_IPHONE_61':
      return '6.1"';
    case 'APP_IPHONE_55':
      return '5.5"';
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
