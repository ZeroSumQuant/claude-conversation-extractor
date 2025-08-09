import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

class ConversationScreen extends StatelessWidget {
  final String sessionId;
  
  const ConversationScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: Tokens.space4),
            Text(
              'Conversation View',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: Tokens.space2),
            Text(
              'Session ID: $sessionId',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}