import 'dart:io';
import 'package:logging/logging.dart' as logging;
import 'package:path_provider/path_provider.dart';

class LlmLogger {
  static LlmLogger? _instance;
  static File? _logFile;
  static final _log = logging.Logger('LlmLogger');

  static String? _customPath;

  LlmLogger._();

  static void setCustomPath(String path) {
    _customPath = path;
  }

  static Future<void> init() async {
    if (_instance != null) return;

    _instance = LlmLogger._();

    try {
      if (_customPath != null) {
        final logDir = Directory(_customPath!);
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }
        _logFile = File('${logDir.path}/llm.log');
        _log.info('Using custom log path: ${_logFile!.path}');
      } else {
        throw Exception('No custom path set');
      }
    } catch (e) {
      // Fallback to app documents directory
      try {
        final dir = await getApplicationDocumentsDirectory();
        final logDir = Directory('${dir.path}/flutterclaw/logs');
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }
        _logFile = File('${logDir.path}/llm.log');
        _log.info('Using fallback log path: ${_logFile!.path}');
      } catch (e2) {
        _log.severe('Failed to initialize LlmLogger: $e2');
        return;
      }
    }

    // Clear old log on start
    if (await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }

    _log.info('LlmLogger ready: ${_logFile!.path}');
  }

  static void log(String type, String message) {
    if (_logFile == null) return;

    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] [$type] $message\n';

    try {
      _logFile!.writeAsStringSync(logLine, mode: FileMode.append);
    } catch (e) {
      _log.warning('Failed to write log: $e');
    }
  }

  static void request(String message) => log('REQUEST', message);
  static void response(String message) => log('RESPONSE', message);
  static void error(String message) => log('ERROR', message);
  static void info(String message) => log('INFO', message);

  static String? get logPath => _logFile?.path;
}
