import 'package:flutter/material.dart';

/// 섹션 헤더 라벨.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
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

/// 섹션 전체 헤더 (큰 라벨 + 옵션 "updated" 뱃지).
/// 워드 파일 자동 적용 or 사용자 직접 편집으로 변경 사항이 있으면 뱃지 표시.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    this.updated = false,
  });
  final String label;
  final bool updated;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        if (updated) ...[
          const SizedBox(width: 12),
          const UpdatedBadge(),
        ],
      ],
    );
  }
}

/// 변경 사항이 있음을 표시하는 작은 뱃지.
class UpdatedBadge extends StatelessWidget {
  const UpdatedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'updated',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 첫 출시 버전에서 What's New 입력 금지를 알리는 배너.
class FirstSubmissionNotice extends StatelessWidget {
  const FirstSubmissionNotice({super.key});

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

/// 섹션 오류 표시 카드.
class SectionErrorCard extends StatelessWidget {
  const SectionErrorCard({super.key, required this.error});
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

/// 저장 버튼 — saving 상태에서 progress 표시.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.saving,
    required this.onPressed,
    this.label = '변경 사항 저장',
  });

  final bool saving;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: saving ? null : onPressed,
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text(saving ? '저장 중…' : label),
      ),
    );
  }
}
