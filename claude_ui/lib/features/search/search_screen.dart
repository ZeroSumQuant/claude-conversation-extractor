import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/tokens.dart';
import '../../core/zig_core_client.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounceTimer;
  
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  String _lastQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }

    // Start debounce timer
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query == _lastQuery) return;
    
    setState(() {
      _isSearching = true;
      _error = null;
      _lastQuery = query;
    });

    try {
      final coreClient = ref.read(zigCoreProvider.notifier);
      final result = await coreClient.request('search', {'q': query});
      
      if (mounted) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(result['results'] ?? []);
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coreState = ref.watch(zigCoreProvider);

    return Scaffold(
      body: Column(
        children: [
          // Search header
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
                  'Search Conversations',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: Tokens.space4),
                
                // Search bar
                TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search for topics, code, or phrases...',
                    prefixIcon: const Icon(LucideIcons.search, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSearching)
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              _focusNode.requestFocus();
                            },
                          ),
                      ],
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  onChanged: _onSearchChanged,
                ),
                
                if (coreState.status != CoreStatus.ready) ...[
                  const SizedBox(height: Tokens.space2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space3,
                      vertical: Tokens.space2,
                    ),
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
                        Text(
                          'Build index first to enable search',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Results area
          Expanded(
            child: _buildResultsArea(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsArea(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: Tokens.space3),
            Text(
              'Search Error',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Tokens.space2),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.search,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: Tokens.space4),
            Text(
              'Start typing to search',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.space2),
            Text(
              'Search across all your Claude conversations',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (_isSearching && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_results.isEmpty && !_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.searchX,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: Tokens.space3),
            Text(
              'No results found',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.space2),
            Text(
              'Try different keywords or phrases',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    // Show results
    return ListView.builder(
      padding: const EdgeInsets.all(Tokens.space3),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _SearchResultCard(
          result: result,
          query: _searchController.text,
          onTap: () {
            // Navigate to conversation with highlight
            context.go('/conversation/${result['session_id']}?highlight=${Uri.encodeComponent(_searchController.text)}');
          },
        );
      },
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final String query;
  final VoidCallback onTap;

  const _SearchResultCard({
    required this.result,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionName = result['session_name'] ?? 'Unknown Session';
    final snippet = result['snippet'] ?? '';
    final score = result['score'] ?? 0.0;
    final position = result['position'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: Tokens.space2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    LucideIcons.messageSquare,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Text(
                      sessionName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Relevance score
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(Tokens.radiusSmall),
                    ),
                    child: Text(
                      '${(score * 100).toInt()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: Tokens.space3),
              
              // Snippet with highlighting
              Container(
                padding: const EdgeInsets.all(Tokens.space3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(Tokens.radiusMedium),
                ),
                child: _buildHighlightedText(snippet, query, theme),
              ),
              
              const SizedBox(height: Tokens.space2),
              
              // Position indicator
              Row(
                children: [
                  Icon(
                    LucideIcons.mapPin,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Tokens.space1),
                  Text(
                    'Position $position in conversation',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query, ThemeData theme) {
    if (query.isEmpty) {
      return Text(
        text,
        style: theme.textTheme.bodyMedium,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matches = <TextSpan>[];
    
    int lastEnd = 0;
    int index = lowerText.indexOf(lowerQuery);
    
    while (index != -1) {
      // Add text before match
      if (index > lastEnd) {
        matches.add(TextSpan(
          text: text.substring(lastEnd, index),
          style: theme.textTheme.bodyMedium,
        ));
      }
      
      // Add highlighted match
      matches.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: theme.textTheme.bodyMedium?.copyWith(
          backgroundColor: theme.colorScheme.tertiary.withValues(alpha: 0.3),
          fontWeight: FontWeight.w600,
        ),
      ));
      
      lastEnd = index + query.length;
      index = lowerText.indexOf(lowerQuery, lastEnd);
    }
    
    // Add remaining text
    if (lastEnd < text.length) {
      matches.add(TextSpan(
        text: text.substring(lastEnd),
        style: theme.textTheme.bodyMedium,
      ));
    }

    return RichText(
      text: TextSpan(children: matches),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}