import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/tokens.dart';

class ProgressCard extends StatelessWidget {
  final String stage;
  final double progress;
  final String? message;
  final VoidCallback? onCancel;

  const ProgressCard({
    super.key,
    required this.stage,
    required this.progress,
    this.message,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (progress * 100).clamp(0, 100).toInt();
    
    // Estimate time remaining (mock for now)
    final estimatedSeconds = ((1 - progress) * 30).round();
    final etaText = estimatedSeconds > 0 ? '${estimatedSeconds}s remaining' : 'Almost done...';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Animated spinner
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: null, // Indeterminate
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: Tokens.space3),
                
                // Stage text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatStage(stage),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (message != null) ...[
                        const SizedBox(height: Tokens.space1),
                        Text(
                          message!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Cancel button
                if (onCancel != null)
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: onCancel,
                    tooltip: 'Cancel',
                  ),
              ],
            ),
            
            const SizedBox(height: Tokens.space4),
            
            // Progress bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$percentage%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      etaText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.space2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            // Stage indicators
            const SizedBox(height: Tokens.space4),
            Row(
              children: [
                Expanded(
                  child: _StageIndicator(
                    label: 'Scan',
                    isActive: stage.contains('scan'),
                    isComplete: progress > 0.25,
                  ),
                ),
                Expanded(
                  child: _StageIndicator(
                    label: 'Parse',
                    isActive: stage.contains('parse'),
                    isComplete: progress > 0.5,
                  ),
                ),
                Expanded(
                  child: _StageIndicator(
                    label: 'Index',
                    isActive: stage.contains('index'),
                    isComplete: progress > 0.75,
                  ),
                ),
                Expanded(
                  child: _StageIndicator(
                    label: 'Complete',
                    isActive: stage.contains('complete'),
                    isComplete: progress >= 0.95,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatStage(String stage) {
    return switch (stage.toLowerCase()) {
      'scan' => 'Scanning files...',
      'parse' => 'Parsing conversations...',
      'index' => 'Building search index...',
      'complete' => 'Finalizing...',
      _ => stage,
    };
  }
}

class _StageIndicator extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isComplete;

  const _StageIndicator({
    required this.label,
    required this.isActive,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final color = isComplete
        ? theme.colorScheme.primary
        : isActive
            ? theme.colorScheme.tertiary
            : theme.colorScheme.surfaceContainerHighest;
    
    final textColor = isComplete || isActive
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          width: isActive || isComplete ? 12 : 8,
          height: isActive || isComplete ? 12 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: isActive ? [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ] : null,
          ),
          child: isComplete
              ? Icon(
                  Icons.check,
                  size: 8,
                  color: theme.colorScheme.onPrimary,
                )
              : null,
        ),
        const SizedBox(height: Tokens.space1),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: theme.textTheme.labelSmall?.copyWith(
            color: textColor,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            fontSize: isActive ? 12 : 11,
          ) ?? const TextStyle(),
          child: Text(label),
        ),
      ],
    );
  }
}