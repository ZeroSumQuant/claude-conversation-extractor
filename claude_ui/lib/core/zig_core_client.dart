import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Protocol types
class ProtocolMessage {
  final String? id;
  final String type;
  final dynamic data;

  ProtocolMessage({this.id, required this.type, this.data});

  factory ProtocolMessage.fromJson(Map<String, dynamic> json) {
    return ProtocolMessage(
      id: json['id'],
      type: json['type'],
      data: json['data'] ?? json,
    );
  }
}

class CoreEvent {
  final String stage;
  final double progress;
  final String? message;

  CoreEvent({required this.stage, required this.progress, this.message});

  factory CoreEvent.fromJson(Map<String, dynamic> json) {
    return CoreEvent(
      stage: json['stage'] ?? '',
      progress: (json['progress'] ?? 0).toDouble(),
      message: json['message'],
    );
  }
}

class CoreError {
  final String code;
  final String message;

  CoreError({required this.code, required this.message});

  factory CoreError.fromJson(Map<String, dynamic> json) {
    return CoreError(
      code: json['code'] ?? 'UNKNOWN',
      message: json['message'] ?? 'Unknown error',
    );
  }
}

// Client state
enum CoreStatus { connecting, ready, indexing, searching, error, disconnected }

class CoreState {
  final CoreStatus status;
  final String? version;
  final String? error;
  final double progress;
  final String? progressStage;

  CoreState({
    required this.status,
    this.version,
    this.error,
    this.progress = 0,
    this.progressStage,
  });

  CoreState copyWith({
    CoreStatus? status,
    String? version,
    String? error,
    double? progress,
    String? progressStage,
  }) {
    return CoreState(
      status: status ?? this.status,
      version: version ?? this.version,
      error: error ?? this.error,
      progress: progress ?? this.progress,
      progressStage: progressStage ?? this.progressStage,
    );
  }
}

// Main client
class ZigCoreClient extends StateNotifier<CoreState> {
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  
  final _requestCompleters = <String, Completer<Map<String, dynamic>>>{};
  final _eventControllers = <String, StreamController<CoreEvent>>{};
  final _logController = StreamController<String>.broadcast();
  
  int _requestId = 0;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  Stream<String> get logs => _logController.stream;

  ZigCoreClient() : super(CoreState(status: CoreStatus.disconnected)) {
    _startCore();
  }

  Future<void> _startCore() async {
    state = state.copyWith(status: CoreStatus.connecting);
    
    try {
      // Find the Zig executable
      final zigPath = await _findZigExecutable();
      if (zigPath == null) {
        throw Exception('Zig core executable not found');
      }

      _log('Starting Zig core: $zigPath');
      
      _process = await Process.start(
        zigPath,
        [],
        mode: ProcessStartMode.normal,
      );

      // Listen to stdout for NDJSON messages
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleMessage, onError: _handleError);

      // Listen to stderr for logs
      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .listen((line) => _log('[CORE] $line'));

      // Handle process exit
      _process!.exitCode.then((code) {
        _log('Core process exited with code: $code');
        _handleDisconnect();
      });

      _reconnectAttempts = 0;
    } catch (e) {
      _log('Failed to start core: $e');
      state = state.copyWith(
        status: CoreStatus.error,
        error: e.toString(),
      );
      _scheduleReconnect();
    }
  }

  Future<String?> _findZigExecutable() async {
    // In development, use the extractor from parent directory
    if (kDebugMode) {
      final devPath = '../extractor';
      if (await File(devPath).exists()) {
        return devPath;
      }
    }

    // In production on macOS, the extractor is in the app bundle
    if (Platform.isMacOS && !kDebugMode) {
      // Get the bundle path
      final bundlePath = Platform.resolvedExecutable;
      final bundleDir = File(bundlePath).parent.path;
      final extractorPath = '$bundleDir/extractor';
      
      if (await File(extractorPath).exists()) {
        // Ensure it's executable
        await Process.run('chmod', ['+x', extractorPath]);
        return extractorPath;
      }
    }

    // For other platforms, check bundled assets
    final platforms = {
      'windows': 'assets/zig-core/windows/extractor.exe',
      'linux': 'assets/zig-core/linux/extractor',
    };

    String? platform;
    if (Platform.isWindows) platform = 'windows';
    else if (Platform.isLinux) platform = 'linux';

    if (platform != null) {
      final path = platforms[platform]!;
      if (await File(path).exists()) {
        // Make executable on Unix platforms
        if (Platform.isLinux) {
          await Process.run('chmod', ['+x', path]);
        }
        return path;
      }
    }

    return null;
  }

  void _handleMessage(String line) {
    if (line.trim().isEmpty) return;

    try {
      // Debug: log line length for all results
      if (line.contains('"type":"result"')) {
        _log('Result line length: ${line.length} chars');
        // Check if it's a search result by looking for session_id
        if (line.contains('"session_id"')) {
          final resultCount = '"session_id"'.allMatches(line).length;
          _log('Number of session_id occurrences: $resultCount');
        }
      }
      
      final json = jsonDecode(line) as Map<String, dynamic>;
      final message = ProtocolMessage.fromJson(json);

      _log('← ${message.type}: ${message.id ?? 'broadcast'}');

      switch (message.type) {
        case 'hello':
          _handleHello(json);
          break;
        case 'result':
          _handleResult(message.id!, json);
          break;
        case 'error':
          _handleErrorMessage(message.id!, json);
          break;
        case 'event':
          _handleEvent(message.id!, json);
          break;
        default:
          _log('Unknown message type: ${message.type}');
      }
    } catch (e) {
      _log('Failed to parse message: $e\n$line');
    }
  }

  void _handleHello(Map<String, dynamic> data) {
    final version = data['core_version'] ?? 'unknown';
    _log('Connected to core v$version');
    
    state = state.copyWith(
      status: CoreStatus.ready,
      version: version,
      error: null,
    );
    
    // Automatically build index on startup
    _autoBuildIndex();
  }
  
  Future<void> _autoBuildIndex() async {
    try {
      _log('Auto-building index on startup...');
      
      // Create an animated indexing experience
      state = state.copyWith(
        status: CoreStatus.indexing,
        progress: 0,
        progressStage: 'scan',
      );
      
      // Start the actual indexing
      final indexFuture = buildIndex();
      
      // Animate through stages over 2.5 seconds minimum
      final animationFuture = _animateIndexProgress();
      
      // Wait for both to complete
      await Future.wait([indexFuture, animationFuture]);
      
      // Ensure we show 100% completion briefly
      state = state.copyWith(
        status: CoreStatus.indexing,
        progress: 1.0,
        progressStage: 'complete',
      );
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Reset to ready state
      state = state.copyWith(
        status: CoreStatus.ready,
        progress: 0,
        progressStage: null,
      );
      
    } catch (e) {
      _log('Auto-index failed (non-critical): $e');
      // Reset to ready state even on error
      state = state.copyWith(
        status: CoreStatus.ready,
        progress: 0,
        progressStage: null,
      );
    }
  }
  
  Future<void> _animateIndexProgress() async {
    const totalDuration = Duration(milliseconds: 2500);
    const steps = 50;
    final stepDuration = Duration(milliseconds: totalDuration.inMilliseconds ~/ steps);
    
    final stages = [
      (start: 0.0, end: 0.25, name: 'scan'),
      (start: 0.25, end: 0.5, name: 'parse'),
      (start: 0.5, end: 0.75, name: 'index'),
      (start: 0.75, end: 0.95, name: 'complete'),
    ];
    
    for (int i = 0; i <= steps; i++) {
      if (state.status != CoreStatus.indexing) break;
      
      final progress = i / steps;
      
      // Determine current stage
      String stageName = 'scan';
      for (final stage in stages) {
        if (progress >= stage.start && progress < stage.end) {
          stageName = stage.name;
          break;
        }
      }
      
      // Apply easing curve for smoother animation
      final easedProgress = _easeInOutCubic(progress);
      
      // Only update if still indexing (in case real operation completed)
      if (state.status == CoreStatus.indexing) {
        state = state.copyWith(
          progress: easedProgress * 0.95, // Cap at 95% until real completion
          progressStage: stageName,
        );
      }
      
      await Future.delayed(stepDuration);
    }
  }
  
  double _easeInOutCubic(double t) {
    return t < 0.5
        ? 4 * t * t * t
        : 1 - ((-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2)) / 2;
  }

  void _handleResult(String id, Map<String, dynamic> data) {
    final completer = _requestCompleters.remove(id);
    if (completer != null && !completer.isCompleted) {
      // Return the whole data object with 'data' field
      completer.complete(data);
    }

    // Clean up event stream
    _eventControllers[id]?.close();
    _eventControllers.remove(id);

    // Update state based on completed operation
    if (state.status == CoreStatus.indexing || state.status == CoreStatus.searching) {
      state = state.copyWith(
        status: CoreStatus.ready,
        progress: 0,
        progressStage: null,
      );
    }
  }

  void _handleErrorMessage(String id, Map<String, dynamic> data) {
    final error = CoreError.fromJson(data);
    final errorMessage = '${error.code}: ${error.message}';
    
    _log('Error for request $id: $errorMessage');
    
    final completer = _requestCompleters.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(errorMessage);
    }

    // Clean up event stream
    _eventControllers[id]?.close();
    _eventControllers.remove(id);

    // Only set global error state for critical errors, not request-specific ones
    if (error.code != 'INDEX_REQUIRED' && error.code != 'INVALID_PARAMS') {
      state = state.copyWith(
        status: CoreStatus.error,
        error: errorMessage,
        progress: 0,
        progressStage: null,
      );
    } else {
      // For non-critical errors, just reset to ready
      state = state.copyWith(
        status: CoreStatus.ready,
        progress: 0,
        progressStage: null,
      );
    }
  }

  void _handleEvent(String id, Map<String, dynamic> data) {
    final event = CoreEvent.fromJson(data);
    
    // Update global progress if this is an index operation
    if (state.status == CoreStatus.indexing) {
      state = state.copyWith(
        progress: event.progress,
        progressStage: event.stage,
      );
    }

    // Send to event stream
    final controller = _eventControllers[id];
    if (controller != null && !controller.isClosed) {
      controller.add(event);
    }
  }

  void _handleError(dynamic error) {
    _log('Stream error: $error');
    state = state.copyWith(
      status: CoreStatus.error,
      error: error.toString(),
    );
  }

  void _handleDisconnect() {
    state = state.copyWith(status: CoreStatus.disconnected);
    
    // Cancel pending requests
    for (final completer in _requestCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError('Core disconnected');
      }
    }
    _requestCompleters.clear();

    // Close event streams
    for (final controller in _eventControllers.values) {
      controller.close();
    }
    _eventControllers.clear();

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= 5) {
      _log('Max reconnect attempts reached');
      return;
    }

    final delay = Duration(seconds: 2 * (_reconnectAttempts + 1));
    _log('Reconnecting in ${delay.inSeconds}s...');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _startCore();
    });
  }

  // Public API
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic>? params,
  ) async {
    if (state.status != CoreStatus.ready && 
        state.status != CoreStatus.indexing &&
        state.status != CoreStatus.searching) {
      throw Exception('Core not ready');
    }

    final id = (++_requestId).toString();
    final completer = Completer<Map<String, dynamic>>();
    _requestCompleters[id] = completer;

    final request = {
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    _log('→ $method ($id)');
    _sendMessage(request);

    // Update status for long operations
    if (method == 'build_index') {
      state = state.copyWith(status: CoreStatus.indexing, progress: 0);
    } else if (method == 'search') {
      state = state.copyWith(status: CoreStatus.searching);
    }

    return completer.future;
  }

  Stream<CoreEvent> requestWithEvents(
    String method,
    Map<String, dynamic>? params,
  ) {
    final id = (++_requestId).toString();
    final eventController = StreamController<CoreEvent>.broadcast();
    _eventControllers[id] = eventController;

    final completer = Completer<Map<String, dynamic>>();
    _requestCompleters[id] = completer;

    final request = {
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    _log('→ $method ($id) [with events]');
    _sendMessage(request);

    // Update status
    if (method == 'build_index') {
      state = state.copyWith(status: CoreStatus.indexing, progress: 0);
    }

    // Complete stream when request finishes
    completer.future.then((_) {
      if (!eventController.isClosed) {
        eventController.close();
      }
    }).catchError((e) {
      if (!eventController.isClosed) {
        eventController.addError(e);
        eventController.close();
      }
    });

    return eventController.stream;
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_process == null) {
      throw Exception('Core not connected');
    }

    final line = jsonEncode(message);
    _process!.stdin.writeln(line);
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] $message';
    debugPrint(logLine);
    _logController.add(logLine);
  }

  Future<void> cancel() async {
    await request('cancel', null);
  }

  Future<Map<String, dynamic>> buildIndex() async {
    return await request('build_index', null);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process?.kill();
    _logController.close();
    
    for (final controller in _eventControllers.values) {
      controller.close();
    }
    
    super.dispose();
  }
}

// Riverpod provider
final zigCoreProvider = StateNotifierProvider<ZigCoreClient, CoreState>((ref) {
  return ZigCoreClient();
});