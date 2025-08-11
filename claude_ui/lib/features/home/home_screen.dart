import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/tokens.dart';
import '../../core/zig_core_client.dart';
import '../../widgets/progress_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isIndexing = false;
  Stream<CoreEvent>? _indexStream;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coreState = ref.watch(zigCoreProvider);
    final coreClient = ref.read(zigCoreProvider.notifier);

    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(Tokens.space6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Title
              Icon(
                LucideIcons.database,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(height: Tokens.space5),
              Text(
                'Claude Conversation Extractor',
                style: theme.textTheme.displayMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Tokens.space3),
              Text(
                'Extract and search your Claude Code conversations',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: Tokens.space7),

              // Status or progress
              if (coreState.status == CoreStatus.indexing && _indexStream != null) ...[
                StreamBuilder<CoreEvent>(
                  stream: _indexStream,
                  builder: (context, snapshot) {
                    final event = snapshot.data;
                    return ProgressCard(
                      stage: event?.stage ?? 'Preparing...',
                      progress: event?.progress ?? 0,
                      message: event?.message,
                      onCancel: _cancelIndexing,
                    );
                  },
                ),
              ] else if (coreState.status == CoreStatus.ready) ...[
                // Main actions
                // Index is now built automatically on startup
                _ActionCard(
                  icon: LucideIcons.folderOpen,
                  title: 'Browse & Search Sessions',
                  description: 'View all conversations and search across your chats',
                  buttonLabel: 'Open Sessions',
                  isPrimary: true,
                  onPressed: () {
                    context.go('/sessions');
                  },
                ),
              ] else if (coreState.status == CoreStatus.connecting) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: Tokens.space4),
                Text(
                  'Connecting to core...',
                  style: theme.textTheme.bodyMedium,
                ),
              ] else if (coreState.status == CoreStatus.error) ...[
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.space4),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.alertCircle,
                          color: theme.colorScheme.error,
                          size: 32,
                        ),
                        const SizedBox(height: Tokens.space3),
                        Text(
                          'Connection Error',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: Tokens.space2),
                        Text(
                          coreState.error ?? 'Unknown error',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: Tokens.space7),

              // Recent sessions
              if (coreState.status == CoreStatus.ready) ...[
                Text(
                  'Quick Actions',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Tokens.space3),
                Wrap(
                  spacing: Tokens.space2,
                  children: [
                    ActionChip(
                      avatar: const Icon(LucideIcons.clock, size: 16),
                      label: const Text('Recent Sessions'),
                      onPressed: () {
                        context.go('/sessions');
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(LucideIcons.terminal, size: 16),
                      label: const Text('View Logs'),
                      onPressed: () {
                        context.go('/settings');
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Rebuild Index'),
                      onPressed: _isIndexing ? null : _buildIndex,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _buildIndex() async {
    setState(() {
      _isIndexing = true;
    });

    final coreClient = ref.read(zigCoreProvider.notifier);
    
    try {
      _indexStream = coreClient.requestWithEvents('build_index', null);
      
      // Wait for completion
      await for (final event in _indexStream!) {
        // Events are handled by the StreamBuilder
      }
      
      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Index built successfully!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to build index: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStream = null;
        });
      }
    }
  }

  Future<void> _cancelIndexing() async {
    final coreClient = ref.read(zigCoreProvider.notifier);
    await coreClient.cancel();
    
    setState(() {
      _isIndexing = false;
      _indexStream = null;
    });
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool isPrimary;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    this.onPressed,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space5),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Tokens.space3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(Tokens.radiusMedium),
              ),
              child: Icon(
                icon,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: Tokens.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Tokens.space1),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Tokens.space4),
            if (isPrimary)
              ElevatedButton(
                onPressed: onPressed,
                child: Text(buttonLabel),
              )
            else
              OutlinedButton(
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
          ],
        ),
      ),
    );
  }
}