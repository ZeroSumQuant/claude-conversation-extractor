import 'dart:async';
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

class _SessionsScreenState extends ConsumerState<SessionsScreen> 
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String _filterText = '';
  Map<String, Map<String, dynamic>> _searchResults = {};
  Timer? _searchDebounce;
  bool _isSearching = false;
  
  // Animation controller for smooth transitions
  late AnimationController _animationController;
  
  // Track the order of sessions for animated reordering
  List<String> _sessionOrder = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadSessions();
  }
  
  @override
  void dispose() {
    _searchDebounce?.cancel();
    _animationController.dispose();
    super.dispose();
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
            // Initialize session order
            _sessionOrder = _sessions.map((s) => s['id'] as String).toList();
          } else {
            _sessions = [];
            _sessionOrder = [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sessions = [];
          _sessionOrder = [];
          _isLoading = false;
        });
      }
    }
  }
  
  // Get all sessions with search metadata, sorted by relevance
  List<Map<String, dynamic>> get _sortedSessions {
    if (_sessions.isEmpty) return [];
    
    // Create a list with all sessions and their search metadata
    final allSessions = <Map<String, dynamic>>[];
    
    // If we have search results, sort sessions by relevance
    if (_searchResults.isNotEmpty) {
      // First, add sessions with search results (sorted by score)
      final matchingSessions = <Map<String, dynamic>>[];
      final nonMatchingSessions = <Map<String, dynamic>>[];
      
      for (final session in _sessions) {
        final sessionId = session['id'] as String;
        if (_searchResults.containsKey(sessionId)) {
          // Merge search metadata
          matchingSessions.add({
            ...session,
            '_snippet': _searchResults[sessionId]!['snippet'],
            '_score': _searchResults[sessionId]!['score'],
            '_matchCount': _searchResults[sessionId]!['match_count'],
            '_hasMatch': true,
          });
        } else {
          // Session doesn't match search
          nonMatchingSessions.add({
            ...session,
            '_hasMatch': false,
          });
        }
      }
      
      // Sort matching sessions by score
      matchingSessions.sort((a, b) {
        final scoreA = (a['_score'] ?? 0.0) as num;
        final scoreB = (b['_score'] ?? 0.0) as num;
        return scoreB.compareTo(scoreA);
      });
      
      // Combine: matching sessions first, then non-matching
      allSessions.addAll(matchingSessions);
      allSessions.addAll(nonMatchingSessions);
    } else if (_filterText.isNotEmpty) {
      // Simple name filtering if no search results
      final filter = _filterText.toLowerCase();
      final matchingSessions = <Map<String, dynamic>>[];
      final nonMatchingSessions = <Map<String, dynamic>>[];
      
      for (final session in _sessions) {
        final name = (session['name'] ?? '').toString().toLowerCase();
        if (name.contains(filter)) {
          matchingSessions.add({
            ...session,
            '_hasMatch': true,
          });
        } else {
          nonMatchingSessions.add({
            ...session,
            '_hasMatch': false,
          });
        }
      }
      
      allSessions.addAll(matchingSessions);
      allSessions.addAll(nonMatchingSessions);
    } else {
      // No filtering - return sessions in original order
      for (final session in _sessions) {
        allSessions.add({
          ...session,
          '_hasMatch': true,
        });
      }
    }
    
    return allSessions;
  }
  
  Future<void> _performSearch(String query) async {
    _searchDebounce?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _searchResults = {};
        _isSearching = false;
        // Trigger animation for reordering
        _animationController.forward(from: 0);
      });
      return;
    }
    
    setState(() => _isSearching = true);
    
    // Debounce search
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final coreClient = ref.read(zigCoreProvider.notifier);
        final result = await coreClient.request('search', {'q': query});
        
        final data = result['data'] ?? result;
        final results = data['results'] ?? [];
        
        if (mounted) {
          setState(() {
            _searchResults = {};
            for (final r in results) {
              final sessionId = r['session_id'] as String?;
              if (sessionId != null) {
                _searchResults[sessionId] = r as Map<String, dynamic>;
              }
            }
            _isSearching = false;
            // Trigger animation for reordering
            _animationController.forward(from: 0);
          });
        }
      } catch (e) {
        // If search fails (e.g., index not built), fall back to name filtering
        if (mounted) {
          setState(() {
            _searchResults = {};
            _isSearching = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedSessions = _sortedSessions;
    
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sessions',
                        style: theme.textTheme.displaySmall,
                      ),
                    ),
                    // Show search status
                    if (_filterText.isNotEmpty && _searchResults.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Tokens.space3,
                          vertical: Tokens.space1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(Tokens.radiusSmall),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.checkCircle,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: Tokens.space1),
                            Text(
                              '${_searchResults.length} matches found',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Tokens.space4),
                Row(
                  children: [
                    // Search/Filter field
                    SizedBox(
                      width: 400,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search sessions and content...',
                          prefixIcon: const Icon(LucideIcons.search, size: 20),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isSearching)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              if (_filterText.isNotEmpty)
                                IconButton(
                                  icon: const Icon(LucideIcons.x, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _filterText = '';
                                      _searchResults = {};
                                      _animationController.forward(from: 0);
                                    });
                                  },
                                ),
                            ],
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Tokens.space3,
                            vertical: Tokens.space2,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() => _filterText = value);
                          _performSearch(value);
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
                    if (_filterText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: Tokens.space2),
                        child: Text(
                          _isSearching ? 'Searching...' : 'Showing all sessions',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Sessions list with animations
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : sortedSessions.isEmpty
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
                              'No sessions found',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return ListView.builder(
                            padding: const EdgeInsets.all(Tokens.space3),
                            itemCount: sortedSessions.length,
                            itemBuilder: (context, index) {
                              final session = sortedSessions[index];
                              final hasMatch = session['_hasMatch'] ?? true;
                              
                              // Calculate opacity and scale based on match status
                              final opacity = hasMatch 
                                  ? 1.0 
                                  : (_filterText.isEmpty ? 1.0 : 0.4);
                              final scale = hasMatch 
                                  ? 1.0 
                                  : (_filterText.isEmpty ? 1.0 : 0.95);
                              
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                transform: Matrix4.identity()
                                  ..scale(scale),
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: opacity,
                                  child: _SessionCard(
                                    key: ValueKey(session['id']),
                                    session: session,
                                    isSearchResult: _searchResults.isNotEmpty,
                                    searchQuery: _filterText,
                                    hasMatch: hasMatch,
                                    onTap: () {
                                      // Navigate with search highlight if searching
                                      if (_filterText.isNotEmpty && hasMatch && _searchResults.isNotEmpty) {
                                        context.push('/sessions/conversation/${session['id']}?highlight=${Uri.encodeComponent(_filterText)}');
                                      } else {
                                        context.push('/sessions/conversation/${session['id']}');
                                      }
                                    },
                                  ),
                                ),
                              );
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

class _SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final bool isSearchResult;
  final String searchQuery;
  final bool hasMatch;
  final VoidCallback onTap;

  const _SessionCard({
    super.key,
    required this.session,
    this.isSearchResult = false,
    this.searchQuery = '',
    this.hasMatch = true,
    required this.onTap,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  void didUpdateWidget(_SessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasMatch != widget.hasMatch) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.session['name'] ?? 'Unnamed';
    final size = widget.session['size'] ?? 0;
    final mtime = widget.session['mtime'];
    
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

    return FadeTransition(
      opacity: _animation,
      child: ScaleTransition(
        scale: _animation,
        child: Card(
          margin: const EdgeInsets.only(bottom: Tokens.space2),
          elevation: widget.hasMatch ? 2 : 0,
          color: widget.hasMatch 
              ? null 
              : theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space4),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.fileText,
                    size: 32,
                    color: widget.hasMatch 
                        ? theme.colorScheme.primary.withValues(alpha: 0.7)
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: Tokens.space4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: widget.hasMatch 
                                      ? null 
                                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Show match count if searching
                            if (widget.isSearchResult && widget.session['_matchCount'] != null && widget.session['_matchCount'] > 0)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(left: Tokens.space2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Tokens.space2,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(Tokens.radiusSmall),
                                ),
                                child: Text(
                                  '${widget.session['_matchCount']} ${widget.session['_matchCount'] == 1 ? 'match' : 'matches'}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // Show snippet if searching
                        if (widget.isSearchResult && widget.session['_snippet'] != null && widget.session['_snippet'].toString().isNotEmpty) ...[
                          const SizedBox(height: Tokens.space2),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(Tokens.space2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(Tokens.radiusSmall),
                              border: Border.all(
                                color: theme.colorScheme.tertiary.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: _buildHighlightedSnippet(
                              widget.session['_snippet'] as String,
                              widget.searchQuery,
                              theme,
                            ),
                          ),
                        ],
                        const SizedBox(height: Tokens.space1),
                        Row(
                          children: [
                            if (dateStr != null) ...[
                              Icon(
                                LucideIcons.calendar,
                                size: 14,
                                color: widget.hasMatch 
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: Tokens.space1),
                              Text(
                                dateStr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: widget.hasMatch 
                                      ? theme.colorScheme.onSurfaceVariant
                                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              const SizedBox(width: Tokens.space3),
                            ],
                            Icon(
                              LucideIcons.hardDrive,
                              size: 14,
                              color: widget.hasMatch 
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: Tokens.space1),
                            Text(
                              '$sizeInMB MB',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: widget.hasMatch 
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
                    color: widget.hasMatch 
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedSnippet(String text, String query, ThemeData theme) {
    if (query.isEmpty) {
      return Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matches = <TextSpan>[];
    
    int lastEnd = 0;
    int index = lowerText.indexOf(lowerQuery);
    
    while (index != -1 && matches.length < 50) { // Limit to prevent too many spans
      // Add text before match
      if (index > lastEnd) {
        matches.add(TextSpan(
          text: text.substring(lastEnd, index),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ));
      }
      
      // Add highlighted match with animation
      matches.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: theme.textTheme.bodySmall?.copyWith(
          backgroundColor: theme.colorScheme.tertiary.withValues(alpha: 0.3),
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onTertiaryContainer,
          fontStyle: FontStyle.normal,
        ),
      ));
      
      lastEnd = index + query.length;
      index = lowerText.indexOf(lowerQuery, lastEnd);
    }
    
    // Add remaining text
    if (lastEnd < text.length) {
      matches.add(TextSpan(
        text: text.substring(lastEnd),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: matches),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}