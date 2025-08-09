import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/tokens.dart';
import '../../app.dart';
import '../../core/zig_core_client.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _showLogs = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final coreState = ref.watch(zigCoreProvider);
    final coreClient = ref.read(zigCoreProvider.notifier);

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(Tokens.space5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: Tokens.space2),
                Text(
                  'Configure appearance and diagnostics',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Settings content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Tokens.space5),
              children: [
                // Theme section
                _SectionHeader(
                  icon: LucideIcons.palette,
                  title: 'Appearance',
                ),
                const SizedBox(height: Tokens.space3),
                Card(
                  child: Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        title: const Text('System'),
                        subtitle: const Text('Follow system theme'),
                        value: ThemeMode.system,
                        groupValue: themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(themeModeProvider.notifier).state = value;
                          }
                        },
                      ),
                      const Divider(height: 1),
                      RadioListTile<ThemeMode>(
                        title: const Text('Light'),
                        subtitle: const Text('Always use light theme'),
                        value: ThemeMode.light,
                        groupValue: themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(themeModeProvider.notifier).state = value;
                          }
                        },
                      ),
                      const Divider(height: 1),
                      RadioListTile<ThemeMode>(
                        title: const Text('Dark'),
                        subtitle: const Text('Always use dark theme'),
                        value: ThemeMode.dark,
                        groupValue: themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(themeModeProvider.notifier).state = value;
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: Tokens.space6),

                // Core status section
                _SectionHeader(
                  icon: LucideIcons.cpu,
                  title: 'Core Status',
                ),
                const SizedBox(height: Tokens.space3),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.space4),
                    child: Column(
                      children: [
                        _StatusRow(
                          label: 'Status',
                          value: _getStatusText(coreState.status),
                          valueColor: _getStatusColor(coreState.status, theme),
                        ),
                        const SizedBox(height: Tokens.space3),
                        _StatusRow(
                          label: 'Version',
                          value: coreState.version ?? 'Unknown',
                        ),
                        const SizedBox(height: Tokens.space3),
                        _StatusRow(
                          label: 'Connection',
                          value: coreState.status == CoreStatus.ready 
                              ? 'Connected' 
                              : 'Disconnected',
                        ),
                        if (coreState.error != null) ...[
                          const SizedBox(height: Tokens.space3),
                          Container(
                            padding: const EdgeInsets.all(Tokens.space3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(Tokens.radiusMedium),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.alertCircle,
                                  size: 16,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: Tokens.space2),
                                Expanded(
                                  child: Text(
                                    coreState.error!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: Tokens.space6),

                // Diagnostics section
                _SectionHeader(
                  icon: LucideIcons.terminal,
                  title: 'Diagnostics',
                ),
                const SizedBox(height: Tokens.space3),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Show Logs'),
                        subtitle: const Text('Display core communication logs'),
                        value: _showLogs,
                        onChanged: (value) {
                          setState(() {
                            _showLogs = value;
                          });
                        },
                      ),
                      if (_showLogs) ...[
                        const Divider(height: 1),
                        Container(
                          height: 300,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          ),
                          child: StreamBuilder<String>(
                            stream: coreClient.logs,
                            builder: (context, snapshot) {
                              final logs = snapshot.data ?? '';
                              
                              // Auto-scroll to bottom when new logs arrive
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (_scrollController.hasClients) {
                                  _scrollController.jumpTo(
                                    _scrollController.position.maxScrollExtent,
                                  );
                                }
                              });

                              return Scrollbar(
                                controller: _scrollController,
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(Tokens.space3),
                                  child: SelectableText(
                                    logs,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: Tokens.space6),

                // About section
                _SectionHeader(
                  icon: LucideIcons.info,
                  title: 'About',
                ),
                const SizedBox(height: Tokens.space3),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Claude Conversation Extractor',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: Tokens.space2),
                        Text(
                          'Extract and search your Claude Code conversations',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Tokens.space3),
                        const Divider(),
                        const SizedBox(height: Tokens.space3),
                        _StatusRow(
                          label: 'UI Version',
                          value: '1.0.0',
                        ),
                        const SizedBox(height: Tokens.space2),
                        _StatusRow(
                          label: 'Core Version',
                          value: coreState.version ?? 'Unknown',
                        ),
                        const SizedBox(height: Tokens.space2),
                        _StatusRow(
                          label: 'Platform',
                          value: Theme.of(context).platform.name,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(CoreStatus status) {
    return switch (status) {
      CoreStatus.connecting => 'Connecting...',
      CoreStatus.ready => 'Ready',
      CoreStatus.indexing => 'Indexing',
      CoreStatus.searching => 'Searching',
      CoreStatus.error => 'Error',
      CoreStatus.disconnected => 'Disconnected',
    };
  }

  Color _getStatusColor(CoreStatus status, ThemeData theme) {
    return switch (status) {
      CoreStatus.ready => theme.colorScheme.primary,
      CoreStatus.indexing || CoreStatus.searching => theme.colorScheme.tertiary,
      CoreStatus.error || CoreStatus.disconnected => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: Tokens.space2),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatusRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}