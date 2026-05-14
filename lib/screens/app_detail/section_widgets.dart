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

/// 섹션 헤더 옆에 붙는 큰 뱃지 (변경 있음 요약).
class UpdatedBadge extends StatelessWidget {
  const UpdatedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 14, color: scheme.onPrimary),
          const SizedBox(width: 4),
          Text(
            '변경 있음',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// 개별 필드 옆에 붙는 작은 핀포인트 뱃지.
class FieldChangeBadge extends StatelessWidget {
  const FieldChangeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '수정',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiary,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1.1,
            ),
      ),
    );
  }
}

/// TextField 위에 두는 "필드 라벨 + (옵션) 변경 뱃지" 한 줄.
///
/// InputDecoration.labelText를 쓰면 floating label과 함께 뱃지를 넣기 어려워서,
/// 별도 라벨 줄로 끌어올린 뒤 TextField는 hint만 노출하는 패턴.
class FieldLabel extends StatelessWidget {
  const FieldLabel(
    this.text, {
    super.key,
    this.changed = false,
    this.hint,
  });

  final String text;
  final bool changed;

  /// 라벨 아래에 작게 표시할 보조 안내 (예: "100자 제한, 콤마 구분").
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (changed) ...[
              const SizedBox(width: 8),
              const FieldChangeBadge(),
            ],
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
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
