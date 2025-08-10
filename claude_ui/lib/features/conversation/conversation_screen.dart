import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/tokens.dart';
import '../../core/zig_core_client.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String sessionId;
  
  const ConversationScreen({
    super.key, 
    required this.sessionId,
  });

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  Map<String, dynamic>? _conversation;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final coreClient = ref.read(zigCoreProvider.notifier);
      
      // Extract the conversation using the session ID
      final result = await coreClient.request('extract', {
        'session_id': widget.sessionId,
        'format': 'json',
      });
      
      print('Loaded conversation: $result'); // Debug
      
      if (mounted) {
        setState(() {
          _conversation = result;
          _isLoading = false;
        });
        
        // Scroll to bottom after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
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

  Future<void> _exportConversation(String format) async {
    try {
      final coreClient = ref.read(zigCoreProvider.notifier);
      final result = await coreClient.request('extract', {
        'session_id': widget.sessionId,
        'format': format,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${result['path'] ?? 'downloads'}'),
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
                      onPressed: () => context.go('/sessions'),
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
      return const Center(
        child: CircularProgressIndicator(),
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
                onPressed: _loadConversation,
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

    // ChatGPT-style message display
    return Container(
      color: theme.brightness == Brightness.light 
          ? Colors.grey.shade50 
          : theme.colorScheme.surfaceContainerLowest,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: Tokens.space4),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return _MessageBubble(message: message);
        },
      ),
    );
  }

  List<Map<String, dynamic>> _extractMessages() {
    if (_conversation == null) return [];
    
    // Try to extract messages from the conversation data
    // The exact structure depends on what the Zig backend returns
    if (_conversation!['messages'] is List) {
      return List<Map<String, dynamic>>.from(_conversation!['messages']);
    }
    
    // If no messages field, return empty
    return [];
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  
  const _MessageBubble({required this.message});

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
                  SelectableText(
                    content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
                  ),
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