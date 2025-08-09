import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/tokens.dart';
import '../../core/zig_core_client.dart';

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String _filterText = '';

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    
    try {
      final coreClient = ref.read(zigCoreProvider.notifier);
      final result = await coreClient.request('list_sessions', null);
      
      if (mounted) {
        setState(() {
          // Handle both array and object responses
          if (result['data'] is List) {
            _sessions = List<Map<String, dynamic>>.from(result['data']);
          } else {
            _sessions = [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load sessions: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredSessions {
    if (_filterText.isEmpty) return _sessions;
    
    final filter = _filterText.toLowerCase();
    return _sessions.where((session) {
      final name = (session['name'] ?? '').toString().toLowerCase();
      return name.contains(filter);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  'Sessions',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: Tokens.space3),
                Row(
                  children: [
                    // Search field
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Filter sessions...',
                          prefixIcon: const Icon(LucideIcons.search, size: 20),
                          suffixIcon: _filterText.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(LucideIcons.x, size: 18),
                                  onPressed: () {
                                    setState(() => _filterText = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Tokens.space3,
                            vertical: Tokens.space2,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() => _filterText = value);
                        },
                      ),
                    ),
                    const SizedBox(width: Tokens.space3),
                    // Refresh button
                    IconButton(
                      icon: const Icon(LucideIcons.refreshCw, size: 20),
                      onPressed: _loadSessions,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Sessions list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.folderX,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: Tokens.space3),
                            Text(
                              _filterText.isEmpty
                                  ? 'No sessions found'
                                  : 'No matching sessions',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(Tokens.space3),
                        itemCount: _filteredSessions.length,
                        itemBuilder: (context, index) {
                          final session = _filteredSessions[index];
                          return _SessionCard(
                            session: session,
                            onTap: () {
                              context.go('/conversation/${session['id']}');
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTap;

  const _SessionCard({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = session['name'] ?? 'Unnamed';
    final size = session['size'] ?? 0;
    final mtime = session['mtime'];
    
    // Format size
    final sizeInMB = (size / (1024 * 1024)).toStringAsFixed(1);
    
    // Format date (if available)
    String? dateStr;
    if (mtime != null) {
      try {
        final date = DateTime.fromMicrosecondsSinceEpoch(mtime ~/ 1000);
        dateStr = '${date.month}/${date.day}/${date.year}';
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: Tokens.space2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space4),
          child: Row(
            children: [
              Icon(
                LucideIcons.fileText,
                size: 32,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: Tokens.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Tokens.space1),
                    Row(
                      children: [
                        if (dateStr != null) ...[
                          Icon(
                            LucideIcons.calendar,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: Tokens.space1),
                          Text(
                            dateStr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: Tokens.space3),
                        ],
                        Icon(
                          LucideIcons.hardDrive,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: Tokens.space1),
                        Text(
                          '$sizeInMB MB',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}