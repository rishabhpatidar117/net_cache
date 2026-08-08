import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// File-backed logger for everything [SmartApiClient] does (requests,
/// cache hits, stream ticks, errors). Mirrors the host app's `AppLogger`
/// structure — `[time] [LEVEL] module :: action :: detail` lines, daily
/// files, size-based rotation, age-based cleanup — but is self-contained
/// and configurable instead of reading app-specific constants.
///
/// Call [ApiLogger.init] once (e.g. in `main()`) if you want persisted log
/// files. If you never call [init], [ApiLogger] still prints to the debug
/// console in debug mode, it just won't write to disk.
class ApiLogger {
  ApiLogger._();

  static Directory? _logDirectory;
  static bool _fileLoggingEnabled = false;
  static bool _consoleLoggingEnabled = true;
  static int _retentionDays = 7;
  static int _maxFileSizeBytes = 2 * 1024 * 1024; // 2 MB

  static final DateFormat _fileFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  /// Call once before using [SmartApiClient] if you want logs written to
  /// disk (viewable later with your own log-viewer UI, or reused from your
  /// existing app's `LogViewerPage`).
  ///
  /// - [enableFileLogging]: writes rotated daily files under
  ///   `<app documents>/<folderName>`. Defaults to true.
  /// - [enableConsoleLogging]: `debugPrint`s every line in debug mode.
  /// - [retentionDays]: log files older than this are deleted on [init].
  /// - [maxFileSizeBytes]: a file is rotated to `.1.txt` once it crosses
  ///   this size.
  static Future<void> init({
    String folderName = 'api_logs',
    bool enableFileLogging = true,
    bool enableConsoleLogging = true,
    int retentionDays = 7,
    int maxFileSizeBytes = 2 * 1024 * 1024,
  }) async {
    _consoleLoggingEnabled = enableConsoleLogging;
    _retentionDays = retentionDays;
    _maxFileSizeBytes = maxFileSizeBytes;
    _fileLoggingEnabled = enableFileLogging;

    if (!enableFileLogging) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _logDirectory = Directory('${dir.path}/$folderName');
      if (!await _logDirectory!.exists()) {
        await _logDirectory!.create(recursive: true);
      }
      await _deleteOldLogs();
    } catch (e) {
      // Disk unavailable (e.g. some test environments) — fall back to
      // console-only logging instead of crashing the app.
      _fileLoggingEnabled = false;
      if (kDebugMode) debugPrint('[ApiLogger] init failed, file logging disabled: $e');
    }
  }

  static void log(Object? object) => _emit('LOG', object?.toString() ?? 'null');

  static void info(String module, String action, String detail) =>
      _emit('INFO', '$module :: $action :: $detail');

  static void warn(String module, String action, String detail) =>
      _emit('WARN', '$module :: $action :: $detail');

  static void error(String module, String action, String detail) =>
      _emit('ERROR', '$module :: $action :: $detail');

  /// Error log with a stack trace attached — use inside a `catch (e, st)`.
  static void errorTrace(
    String module,
    String action,
    Object error,
    StackTrace stackTrace,
  ) {
    _emit('ERROR', '$module :: $action :: $error\n$stackTrace');
  }

  static Future<String> getTodayLogs() async {
    final file = await _getLogFile();
    if (file == null || !await file.exists()) return '';
    return file.readAsString();
  }

  static Future<List<File>> getAllLogFiles() async {
    final dir = _logDirectory;
    if (dir == null || !await dir.exists()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.split(Platform.pathSeparator).last.startsWith('log_'))
        .toList();

    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static void _emit(String level, String message) {
    final time = _timeFormat.format(DateTime.now());
    final logLine = '[$time] [$level] $message\n';

    if (_consoleLoggingEnabled && kDebugMode) debugPrint(logLine.trimRight());
    if (_fileLoggingEnabled) _writeToFile(logLine);
  }

  static void _writeToFile(String logLine) {
    _getLogFile().then((file) async {
      if (file == null) return;
      try {
        final stat = await file.stat();
        if (stat.size >= _maxFileSizeBytes) {
          await _rotateFile(file);
        }
        await file.writeAsString(logLine, mode: FileMode.append);
      } catch (e) {
        if (kDebugMode) debugPrint('[ApiLogger] write error: $e');
      }
    }).catchError((e) {
      if (kDebugMode) debugPrint('[ApiLogger] getLogFile error: $e');
    });
  }

  static Future<File?> _getLogFile() async {
    final dir = _logDirectory;
    if (dir == null) return null;
    final today = _fileFormat.format(DateTime.now());
    final file = File('${dir.path}/log_$today.txt');
    if (!await file.exists()) await file.create();
    return file;
  }

  static Future<void> _rotateFile(File file) async {
    final backupPath = file.path.replaceFirst('.txt', '.1.txt');
    final backup = File(backupPath);
    if (await backup.exists()) await backup.delete();
    await file.rename(backupPath);
    await File(file.path).create();
    if (kDebugMode) {
      debugPrint('[ApiLogger] Rotated log file — exceeded ${_maxFileSizeBytes ~/ 1024} KB');
    }
  }

  static Future<void> _deleteOldLogs() async {
    final dir = _logDirectory;
    if (dir == null) return;
    final files = dir.listSync();
    final now = DateTime.now();

    for (final entity in files) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith('log_')) continue;

      final dateStr = name.replaceFirst('log_', '').replaceAll('.1.txt', '').replaceAll('.txt', '');

      try {
        final fileDate = _fileFormat.parse(dateStr);
        if (now.difference(fileDate).inDays > _retentionDays) {
          await entity.delete();
        }
      } catch (e) {
        // A stray/renamed file with an unparseable date — skip it, don't
        // let a single bad filename break cleanup for the rest.
        if (kDebugMode) debugPrint('[ApiLogger] _deleteOldLogs skip "$name": $e');
      }
    }
  }
}
