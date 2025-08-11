import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/tokens.dart';
import '../core/zig_core_client.dart';

class NavigationItem {
  final String path;
  final String label;
  final IconData icon;
  final String? shortcut;

  const NavigationItem({
    required this.path,
    required this.label,
    required this.icon,
    this.shortcut,
  });
}

class AppScaffold extends ConsumerStatefulWidget {
  final Widget child;
  final bool showFooter;

  const AppScaffold({
    super.key,
    required this.child,
    this.showFooter = true,
  });

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  static const _navItems = [
    NavigationItem(
      path: '/',
      label: 'Home',
      icon: LucideIcons.home,
    ),
    NavigationItem(
      path: '/sessions',
      label: 'Sessions',
      icon: LucideIcons.folderOpen,
      shortcut: '⌘F',
    ),
    NavigationItem(
      path: '/settings',
      label: 'Settings',
      icon: LucideIcons.settings,
      shortcut: '⌘,',
    ),
  ];

  int get _selectedIndex {
    final location = GoRouterState.of(context).uri.toString();
    return _navItems.indexWhere((item) => item.path == location);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coreState = ref.watch(zigCoreProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          context.go('/sessions');
        },
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () {
          context.go('/settings');
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          _showCommandPalette(context);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              // Sidebar
              Container(
                width: 240,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border(
                    right: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // App title
                    Container(
                      height: 80,
                      padding: const EdgeInsets.all(Tokens.space4),
                      child: Center(
                        child: Text(
                          'Claude Extractor',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    
                    const Divider(height: 1),
                    
                    // Navigation items
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
                        itemCount: _navItems.length,
                        itemBuilder: (context, index) {
                          final item = _navItems[index];
                          final isSelected = index == _selectedIndex;
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Tokens.space2,
                              vertical: 2,
                            ),
                            child: _NavItem(
                              item: item,
                              isSelected: isSelected,
                              onTap: () => context.go(item.path),
                            ),
                          );
                        },
                      ),
                    ),
                    
                    if (widget.showFooter) ...[
                      const Divider(height: 1),
                      _FooterBar(coreState: coreState),
                    ],
                  ],
                ),
              ),
              
              // Main content
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCommandPalette(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const CommandPalette(),
    );
  }
}

class _NavItem extends StatefulWidget {
  final NavigationItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = widget.isSelected;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: Tokens.durationFast,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : _isHovered
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(Tokens.radiusMedium),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.space3,
              vertical: Tokens.space2,
            ),
            child: Row(
              children: [
                Icon(
                  widget.item.icon,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w500 : null,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.item.shortcut != null)
                  Text(
                    widget.item.shortcut!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  final CoreState coreState;

  const _FooterBar({required this.coreState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    String statusText = switch (coreState.status) {
      CoreStatus.connecting => 'Connecting...',
      CoreStatus.ready => 'Ready',
      CoreStatus.indexing => 'Indexing... ${(coreState.progress * 100).toInt()}%',
      CoreStatus.searching => 'Searching...',
      CoreStatus.error => 'Error',
      CoreStatus.disconnected => 'Disconnected',
    };

    final statusColor = switch (coreState.status) {
      CoreStatus.ready => theme.colorScheme.primary,
      CoreStatus.indexing || CoreStatus.searching => theme.colorScheme.tertiary,
      CoreStatus.error || CoreStatus.disconnected => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: Tokens.space2),
          Text(
            statusText,
            style: theme.textTheme.bodySmall,
          ),
          if (coreState.version != null) ...[
            const Spacer(),
            Text(
              'Core v${coreState.version}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Command Palette widget
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.all(Tokens.space4),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a command or search...',
                  prefixIcon: const Icon(LucideIcons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusMedium),
                  ),
                ),
                onChanged: (value) {
                  setState(() {});
                },
              ),
            ),
            
            // Commands list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.space2),
                children: [
                  _CommandItem(
                    icon: LucideIcons.home,
                    label: 'Go to Home',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/');
                    },
                  ),
                  _CommandItem(
                    icon: LucideIcons.folderOpen,
                    label: 'Browse & Search Sessions',
                    shortcut: '⌘F',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/sessions');
                    },
                  ),
                  _CommandItem(
                    icon: LucideIcons.settings,
                    label: 'Settings',
                    shortcut: '⌘,',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/settings');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;

  const _CommandItem({
    required this.icon,
    required this.label,
    this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space3,
          vertical: Tokens.space2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: Tokens.space3),
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            if (shortcut != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.space2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  shortcut!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}