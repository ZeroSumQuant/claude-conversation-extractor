import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Setup desktop window
  await setupWindow();
  
  runApp(
    const ProviderScope(
      child: ClaudeExtractorApp(),
    ),
  );
}
