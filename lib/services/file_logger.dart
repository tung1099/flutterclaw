import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

class LlmLogger {
  static String? _customPath;
  static File? _logFile;

  static void setCustomPath(String path) {
    _customPath = path;
  }

  static Future<void> init() async {
    try {
      String logPath;
      if (_customPath != null && _customPath!.isNotEmpty) {
        logPath = _customPath!;
      } else {
        // Fallback to app documents directory
        final dir = await getApplicationDocumentsDirectory();
        logPath = '${dir.path}/llm.log';
      }

      // Ensure directory exists
      final directory = Directory(
        logPath.endsWith('.log')
            ? logPath.substring(0, logPath.lastIndexOf('/'))
            : logPath,
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      _logFile = File(logPath);
      // Ensure file exists
      if (!await _logFile!.exists()) {
        await _logFile!.create();
      }
    } catch (e) {
      // Fallback to console logging if file logging fails
      print('Failed to initialize LlmLogger: $e');
    }
  }

  static Future<Directory> getApplicationDocumentsDirectory() async {
    if (Platform.isIOS) {
      // For iOS, use library directory
      return await getLibraryDirectory();
    } else if (Platform.isAndroid) {
      // For Android, use external storage
      final directory = await getExternalStorageDirectory();
      return directory!;
    } else {
      // For desktop or other platforms
      return Directory.current;
    }
  }

  static Future<void> _writeLog(String message) async {
    if (_logFile == null) return;

    try {
      final timestamp = DateTime.now().toIso8601String();
      final logLine = '[$timestamp] $message\n';
      await _logFile!.writeAsString(logLine, mode: FileMode.append);
    } catch (e) {
      // Fallback to console
      print('LLM LOG: $message');
    }
  }

  static void request(dynamic msg) {
    // Fire and forget - don't await to avoid blocking
    _writeLog(
      'REQUEST: $msg',
    ).catchError((e) => print('LlmLogger.request error: $e'));
  }

  static void response(dynamic msg) {
    // Fire and forget - don't await to avoid blocking
    _writeLog(
      'RESPONSE: $msg',
    ).catchError((e) => print('LlmLogger.response error: $e'));
  }
}
