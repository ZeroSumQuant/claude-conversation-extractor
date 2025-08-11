import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/tokens.dart';
import '../../core/zig_core_client.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String? highlightQuery;
  final int? jumpToPosition;
  
  const ConversationScreen({
    super.key, 
    required this.sessionId,
    this.highlightQuery,
    this.jumpToPosition,
  });

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  Map<String, dynamic>? _conversation;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _currentOffset = 0;
  static const int _pageSize = 50;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Start loading messages immediately for instant display
    // Use microtask to ensure build completes first for smoother transition
    Future.microtask(() => _loadInitialMessages().then((_) {
      // After messages load, jump to position if specified
      if (widget.jumpToPosition != null && _messages.isNotEmpty) {
        _jumpToMessage(widget.jumpToPosition!);
      }
    }));
  }
  
  void _jumpToMessage(int position) {
    // Find the message at the given position
    if (position < _messages.length) {
      // Calculate scroll position (approximate)
      // Each message is roughly 100-200 pixels
      final scrollPosition = position * 150.0;
      
      // Delay to ensure layout is complete
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            scrollPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final coreClient = ref.read(zigCoreProvider.notifier);
      
      // Load first page of messages (ChatGPT style - instant display)
      final result = await coreClient.request('extract', {
        'session_id': widget.sessionId,
        'format': 'json',
        'limit': _pageSize,
        'offset': 0,
      });
      
      if (mounted) {
        final data = result['data'] ?? result;
        setState(() {
          _conversation = data;
          _messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
          _hasMore = data['has_more'] ?? false;
          _currentOffset = _messages.length;
          _isLoading = false;
        });
        
        // Setup scroll listener for infinite scrolling
        _scrollController.addListener(_onScroll);
        
        // Scroll to bottom after initial load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _messages.isNotEmpty) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }
  
  void _onScroll() {
    // Load more when scrolled to top (older messages)
    if (_scrollController.position.pixels == 0 && 
        !_isLoadingMore && 
        _hasMore) {
      _loadMoreMessages();
    }
  }
  
  Future<void> _loadMoreMessages() async {
    setState(() {
      _isLoadingMore = true;
    });
    
    try {
      final coreClient = ref.read(zigCoreProvider.notifier);
      
      final result = await coreClient.request('extract', {
        'session_id': widget.sessionId,
        'format': 'json',
        'limit': _pageSize,
        'offset': _currentOffset,
      });
      
      if (mounted) {
        final data = result['data'] ?? result;
        final newMessages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
        
        setState(() {
          // Prepend older messages to the beginning
          _messages = [...newMessages, ..._messages];
          _hasMore = data['has_more'] ?? false;
          _currentOffset += newMessages.length;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _exportConversation(String format) async {
    try {
      final coreClient = ref.read(zigCoreProvider.notifier);
      final result = await coreClient.request('extract', {
        'session_id': widget.sessionId,
        'format': format,
        'export': true,  // Tell backend we want to export to file
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ~/Desktop/Claude logs/'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // Minimal header with back button
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
                child: Row(
                  children: [
                    // Back button
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () => context.pop(),
                      tooltip: 'Back to Sessions',
                    ),
                    const SizedBox(width: Tokens.space2),
                    // Title
                    Expanded(
                      child: Text(
                        widget.sessionId.replaceAll('_', ' ').replaceAll('session ', 'Session '),
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Export menu
                    PopupMenuButton<String>(
                      icon: const Icon(LucideIcons.download, size: 20),
                      tooltip: 'Export',
                      enabled: !_isLoading && _conversation != null,
                      onSelected: _exportConversation,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'markdown',
                          child: Text('Export as Markdown'),
                        ),
                        const PopupMenuItem(
                          value: 'json',
                          child: Text('Export as JSON'),
                        ),
                        const PopupMenuItem(
                          value: 'html',
                          child: Text('Export as HTML'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Conversation content
          Expanded(
            child: _buildContent(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      // Show loading skeleton instead of spinner for smoother transition
      return Container(
        color: theme.brightness == Brightness.light 
            ? Colors.grey.shade50 
            : theme.colorScheme.surfaceContainerLowest,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: Tokens.space4),
          itemCount: 5, // Show 5 skeleton messages
          itemBuilder: (context, index) {
            return _buildSkeletonMessage(theme, index % 2 == 0);
          },
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(Tokens.space4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.alertCircle,
                size: 48,
                color: theme.colorScheme.error.withValues(alpha: 0.7),
              ),
              const SizedBox(height: Tokens.space3),
              Text(
                'Failed to load conversation',
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
              const SizedBox(height: Tokens.space4),
              FilledButton.icon(
                onPressed: _loadInitialMessages,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Extract messages from the conversation data
    final messages = _extractMessages();
    
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.messageSquare,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: Tokens.space3),
            Text(
              'No messages in this conversation',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // ChatGPT-style message display with infinite scroll
    return Container(
      color: theme.brightness == Brightness.light 
          ? Colors.grey.shade50 
          : theme.colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          // Show loading indicator at top when loading older messages
          if (_isLoadingMore)
            Container(
              padding: const EdgeInsets.all(Tokens.space3),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: Tokens.space4),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return _MessageBubble(
                  message: message,
                  highlightQuery: widget.highlightQuery,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractMessages() {
    // Use the already loaded messages list
    return _messages;
  }
  
  Widget _buildSkeletonMessage(ThemeData theme, bool isUser) {
    return Container(
      color: isUser 
          ? Colors.transparent
          : (theme.brightness == Brightness.light 
              ? Colors.white 
              : theme.colorScheme.surfaceContainer),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900),
        margin: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width > 900 
              ? (MediaQuery.of(context).size.width - 900) / 2 
              : Tokens.space4,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: Tokens.space4,
          vertical: isUser ? Tokens.space4 : Tokens.space5,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar skeleton
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: Tokens.space4),
            // Content skeleton
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title skeleton
                  Container(
                    width: 60,
                    height: 14,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: Tokens.space2),
                  // Content lines skeleton
                  ...List.generate(isUser ? 2 : 4, (i) => Padding(
                    padding: EdgeInsets.only(bottom: i < (isUser ? 1 : 3) ? 8.0 : 0),
                    child: Container(
                      width: i == (isUser ? 1 : 3) ? 200 : double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final String? highlightQuery;
  
  const _MessageBubble({
    required this.message,
    this.highlightQuery,
  });
  
  Widget _buildHighlightedContent(String content, ThemeData theme) {
    if (highlightQuery == null || highlightQuery!.isEmpty) {
      return SelectableText(
        content,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      );
    }
    
    final lowerContent = content.toLowerCase();
    final lowerQuery = highlightQuery!.toLowerCase();
    final matches = <TextSpan>[];
    
    int lastEnd = 0;
    int index = lowerContent.indexOf(lowerQuery);
    
    while (index != -1 && lastEnd < content.length) {
      // Add text before match
      if (index > lastEnd) {
        matches.add(TextSpan(
          text: content.substring(lastEnd, index),
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ));
      }
      
      // Add highlighted match
      matches.add(TextSpan(
        text: content.substring(index, index + highlightQuery!.length),
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.5,
          backgroundColor: theme.colorScheme.tertiary.withValues(alpha: 0.3),
          fontWeight: FontWeight.w600,
        ),
      ));
      
      lastEnd = index + highlightQuery!.length;
      index = lowerContent.indexOf(lowerQuery, lastEnd);
    }
    
    // Add remaining text
    if (lastEnd < content.length) {
      matches.add(TextSpan(
        text: content.substring(lastEnd),
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      ));
    }
    
    return SelectableText.rich(
      TextSpan(children: matches),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = message['role'] ?? 'unknown';
    final content = message['content'] ?? '';
    final isUser = role == 'user' || role == 'human';
    
    return Container(
      color: isUser 
          ? Colors.transparent
          : (theme.brightness == Brightness.light 
              ? Colors.white 
              : theme.colorScheme.surfaceContainer),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900),
        margin: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width > 900 
              ? (MediaQuery.of(context).size.width - 900) / 2 
              : Tokens.space4,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: Tokens.space4,
          vertical: isUser ? Tokens.space4 : Tokens.space5,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isUser 
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isUser ? LucideIcons.user : LucideIcons.bot,
                size: 18,
                color: isUser 
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: Tokens.space4),
            
            // Message content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? 'You' : 'Claude',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Tokens.space1),
                  _buildHighlightedContent(content, theme),
                ],
              ),
            ),
            
            // Copy button
            IconButton(
              icon: const Icon(LucideIcons.copy, size: 16),
              onPressed: () async {
                // Copy to clipboard
                await Clipboard.setData(ClipboardData(text: content));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              tooltip: 'Copy',
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}