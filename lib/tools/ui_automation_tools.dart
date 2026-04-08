/// UI Automation tools — let the agent simulate user interaction on the device.
///
/// Android: full cross-app automation via AccessibilityService.
/// iOS: screenshot only (cross-app control is not available on iOS).
library;

import 'dart:convert';

import 'package:flutterclaw/services/overlay_service.dart';
import 'package:flutterclaw/services/ui_automation_service.dart';
import 'package:flutterclaw/tools/registry.dart';

// ─── Permission ───────────────────────────────────────────────────────────────

class UiCheckPermissionTool extends Tool {
  final UiAutomationService _svc;
  UiCheckPermissionTool(this._svc);

  @override
  String get name => 'ui_check_permission';

  @override
  String get description =>
      'Check whether UI automation is available on this device.\n\n'
      'Android: returns true if the Accessibility Service is enabled.\n'
      'iOS: always returns false — cross-app UI automation is not supported on iOS.\n\n'
      'If not granted on Android, call ui_request_permission to open '
      'Settings > Accessibility so the user can enable it.';

  @override
  Map<String, dynamic> get parameters => {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final r = await _svc.checkPermission();
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Request permission ───────────────────────────────────────────────────────

class UiRequestPermissionTool extends Tool {
  final UiAutomationService _svc;
  UiRequestPermissionTool(this._svc);

  @override
  String get name => 'ui_request_permission';

  @override
  String get description =>
      'Open the system Accessibility Settings page so the user can enable '
      'UI automation for this app.\n\n'
      'Android only. Tell the user to find "FlutterClaw UI Automation" in the '
      'list and toggle it on. After they return, call ui_check_permission to '
      'confirm it is active.\n\n'
      'iOS: not applicable — returns an informational note.';

  @override
  Map<String, dynamic> get parameters => {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final r = await _svc.requestPermission();
    if (r['error'] == true)
      return ToolResult.error(r['message'] as String? ?? 'Failed');
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Tap ──────────────────────────────────────────────────────────────────────

class UiTapTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;
  UiTapTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_tap';

  @override
  String get description =>
      'Tap at screen coordinates (x, y) in pixels.\n\n'
      'Use ui_find_elements first to discover element positions, then pass '
      'the element\'s centerX/centerY directly here.\n\n'
      'Requires Accessibility Service (check with ui_check_permission).\n'
      'Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'x': {'type': 'number', 'description': 'X coordinate in screen pixels.'},
      'y': {'type': 'number', 'description': 'Y coordinate in screen pixels.'},
    },
    'required': ['x', 'y'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final x = (args['x'] as num?)?.toDouble();
    final y = (args['y'] as num?)?.toDouble();
    if (x == null) return ToolResult.error('x is required');
    if (y == null) return ToolResult.error('y is required');

    _overlay?.showTapFeedback(x, y);
    final r = await _svc.tap(x, y);
    if (r['error'] == true)
      return ToolResult.error(
        r['message'] as String? ?? r['code'] as String? ?? 'Failed',
      );
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Swipe ────────────────────────────────────────────────────────────────────

class UiSwipeTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;
  UiSwipeTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_swipe';

  @override
  String get description =>
      'Swipe from (x1, y1) to (x2, y2) in screen pixels.\n\n'
      'Common patterns:\n'
      '- Scroll down: swipe from bottom-center to top-center\n'
      '- Scroll up: swipe from top-center to bottom-center\n'
      '- Dismiss notification: swipe right from element position\n\n'
      'duration_ms controls swipe speed (default 300ms). '
      'Shorter = faster flick, longer = slow drag.\n\n'
      'Requires Accessibility Service. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'x1': {'type': 'number', 'description': 'Start X in pixels.'},
      'y1': {'type': 'number', 'description': 'Start Y in pixels.'},
      'x2': {'type': 'number', 'description': 'End X in pixels.'},
      'y2': {'type': 'number', 'description': 'End Y in pixels.'},
      'duration_ms': {
        'type': 'integer',
        'description': 'Swipe duration in milliseconds (50–5000, default 300).',
        'minimum': 50,
        'maximum': 5000,
      },
    },
    'required': ['x1', 'y1', 'x2', 'y2'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final x1 = (args['x1'] as num?)?.toDouble();
    final y1 = (args['y1'] as num?)?.toDouble();
    final x2 = (args['x2'] as num?)?.toDouble();
    final y2 = (args['y2'] as num?)?.toDouble();
    if (x1 == null) return ToolResult.error('x1 is required');
    if (y1 == null) return ToolResult.error('y1 is required');
    if (x2 == null) return ToolResult.error('x2 is required');
    if (y2 == null) return ToolResult.error('y2 is required');
    final durationMs = (args['duration_ms'] as num?)?.toInt() ?? 300;

    _overlay?.showSwipeFeedback(x1, y1, x2, y2);
    final r = await _svc.swipe(x1, y1, x2, y2, durationMs: durationMs);
    if (r['error'] == true)
      return ToolResult.error(
        r['message'] as String? ?? r['code'] as String? ?? 'Failed',
      );
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Type text ────────────────────────────────────────────────────────────────

class UiTypeTextTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;
  UiTypeTextTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_type_text';

  @override
  String get description =>
      'Type text into the currently focused input field on screen.\n\n'
      'The field must already be focused (tapped). If no field is focused, '
      'use ui_tap on the input field first, then call ui_type_text.\n\n'
      'Replaces the current field content entirely.\n\n'
      'Requires Accessibility Service. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'text': {
        'type': 'string',
        'description': 'The text to type into the focused input field.',
      },
    },
    'required': ['text'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final text = args['text'] as String?;
    if (text == null || text.isEmpty)
      return ToolResult.error('text is required');

    _overlay?.showTypeFeedback(text);
    final r = await _svc.typeText(text);
    if (r['error'] == true)
      return ToolResult.error(
        r['message'] as String? ?? r['code'] as String? ?? 'Failed',
      );
    if (r['success'] == false) {
      return ToolResult.error(r['message'] as String? ?? 'Type text failed');
    }
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Find elements ────────────────────────────────────────────────────────────

class UiFindElementsTool extends Tool {
  final UiAutomationService _svc;
  UiFindElementsTool(this._svc);

  @override
  String get name => 'ui_find_elements';

  @override
  String get description =>
      'List interactive elements currently visible on screen.\n\n'
      'Each element includes: text, contentDescription, resourceId, className, '
      'bounds (left/top/right/bottom), centerX, centerY, isClickable, isEnabled.\n\n'
      'Use centerX/centerY directly as x/y in ui_tap.\n\n'
      'Parameters:\n'
      '- query: optional filter string\n'
      '- by: how to match — "all" (default), "text", "id", "description", "class"\n\n'
      'Examples:\n'
      '- Find all elements: {}\n'
      '- Find button by text: {"query": "Submit", "by": "text"}\n'
      '- Find by resource ID: {"query": "btn_login", "by": "id"}\n\n'
      'Results capped at 200 nodes. Requires Accessibility Service. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'Optional search string to filter elements.',
      },
      'by': {
        'type': 'string',
        'enum': ['all', 'text', 'id', 'description', 'class'],
        'description': 'How to match the query (default: "all").',
      },
    },
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query'] as String?;
    final by = (args['by'] as String?) ?? 'all';

    final r = await _svc.findElements(query: query, by: by);
    if (r['error'] == true)
      return ToolResult.error(
        r['message'] as String? ?? r['code'] as String? ?? 'Failed',
      );
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Click element ────────────────────────────────────────────────────────────

class UiClickElementTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;
  UiClickElementTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_click_element';

  @override
  String get description =>
      'Find an element by text, ID, or description and click it in one step.\n\n'
      'Prefer this over ui_find_elements + ui_tap when you know what to click.\n\n'
      'Parameters:\n'
      '- query: the string to search for (required)\n'
      '- by: "text" (default), "id", "description", "class"\n\n'
      'Returns the matched element\'s details on success.\n\n'
      'Requires Accessibility Service. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'Text, resource ID, or content description to search for.',
      },
      'by': {
        'type': 'string',
        'enum': ['text', 'id', 'description', 'class'],
        'description': 'How to identify the element (default: "text").',
      },
    },
    'required': ['query'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query'] as String?;
    if (query == null || query.isEmpty)
      return ToolResult.error('query is required');
    final by = (args['by'] as String?) ?? 'text';

    final r = await _svc.clickElement(query, by);
    if (r['error'] == true)
      return ToolResult.error(
        r['message'] as String? ?? r['code'] as String? ?? 'Failed',
      );
    if (r['success'] == false) {
      return ToolResult.error(
        r['message'] as String? ?? 'Element not found or click failed',
      );
    }
    // Show tap feedback at the clicked element's center
    final cx = (r['centerX'] as num?)?.toDouble();
    final cy = (r['centerY'] as num?)?.toDouble();
    if (cx != null && cy != null) _overlay?.showTapFeedback(cx, cy);
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Screenshot ───────────────────────────────────────────────────────────────

class UiScreenshotTool extends Tool {
  final UiAutomationService _svc;
  UiScreenshotTool(this._svc);

  @override
  String get name => 'ui_screenshot';

  @override
  String get description =>
      'Capture the current screen and return a description of visible elements.\n\n'
      'Returns a screenshot image (for vision models) plus a text summary of all '
      'interactive elements on screen with their positions, so you can decide '
      'what to tap or click next.\n\n'
      'Android: full-screen capture when Accessibility Service is enabled.\n'
      'iOS: captures the FlutterClaw app surface only.';

  @override
  Map<String, dynamic> get parameters => {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    // Take screenshot and find elements in parallel
    final results = await Future.wait([
      _svc.screenshot(),
      _svc.findElements(by: 'all'),
    ]);
    final r = results[0];
    final elements = results[1];

    // Build text summary of visible elements
    final elemList = elements['elements'] as List<dynamic>? ?? [];
    final summary = StringBuffer();
    summary.writeln('=== Screen Elements (${elemList.length}) ===');
    for (final e in elemList) {
      if (e is! Map<String, dynamic>) continue;
      final text = e['text'] as String?;
      final desc = e['contentDescription'] as String?;
      final cls = (e['className'] as String? ?? '').split('.').last;
      final clickable = e['isClickable'] == true;
      final cx = e['centerX'];
      final cy = e['centerY'];
      final label = text ?? desc ?? e['resourceId'] as String? ?? cls;
      if (label.isEmpty) continue;
      final tag = clickable ? '[clickable]' : '';
      summary.writeln('- "$label" $tag at ($cx, $cy) [$cls]');
    }

    if (r['error'] == true || r['data'] == null) {
      // Screenshot failed but we still have elements - check for fallback
      final fallback = r['fallback'] == true;
      final note = r['note'] as String? ?? 'Screenshot unavailable';
      final elementsData = r['elements'];

      if (elementsData != null) {
        // Build summary from fallback elements
        final elemList = elementsData as List<dynamic>? ?? [];
        final summary = StringBuffer();
        if (fallback) {
          summary.writeln('⚠️ Screenshot unavailable. Using UI elements:\n');
        }
        for (final e in elemList) {
          if (e is! Map<String, dynamic>) continue;
          final text = e['text'] as String?;
          final desc = e['contentDescription'] as String?;
          final cls = (e['className'] as String? ?? '').split('.').last;
          final clickable = e['isClickable'] == true;
          final cx = e['centerX'];
          final cy = e['centerY'];
          final label = text ?? desc ?? e['resourceId'] as String? ?? cls;
          if (label.isEmpty) continue;
          final tag = clickable ? '[clickable]' : '';
          summary.writeln('- "$label" $tag at ($cx, $cy) [$cls]');
        }
        return ToolResult.success(
          fallback
              ? '⚠️ Screenshot unavailable (app in background).\n\n${summary.toString().trim()}'
              : summary.toString().trim(),
        );
      }
      return ToolResult.error(
        'Screenshot failed: ${r['message'] ?? 'unknown error'}',
      );
    }

    // Return image block (for Anthropic/vision) + text summary (for all providers)
    final output = {
      'type': 'image',
      'data': r['data'],
      'mimeType': r['mimeType'] ?? 'image/jpeg',
      'note': summary.toString().trim(),
      if (r['note'] != null) 'pixelCopyNote': r['note'],
    };
    return ToolResult.success(jsonEncode(output));
  }
}

// ─── Global action ────────────────────────────────────────────────────────────

class UiGlobalActionTool extends Tool {
  final UiAutomationService _svc;
  UiGlobalActionTool(this._svc);

  @override
  String get name => 'ui_global_action';

  @override
  String get description =>
      'Perform a global device action.\n\n'
      'Available actions:\n'
      '- back: press the Back button\n'
      '- home: press the Home button\n'
      '- recents: open the Recents/Overview screen\n'
      '- notifications: pull down the notification shade\n'
      '- quick_settings: pull down Quick Settings\n\n'
      'Requires Accessibility Service. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['back', 'home', 'recents', 'notifications', 'quick_settings'],
        'description': 'The global action to perform.',
      },
    },
    'required': ['action'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final action = args['action'] as String?;
    if (action == null || action.isEmpty)
      return ToolResult.error('action is required');

    final r = await _svc.globalAction(action);
    if (r['error'] == true)
      return ToolResult.error(
        r['message'] as String? ?? r['code'] as String? ?? 'Failed',
      );
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Wait for element ──────────────────────────────────────────────────────────

class UiWaitTool extends Tool {
  final UiAutomationService _svc;
  UiWaitTool(this._svc);

  @override
  String get name => 'ui_wait';

  @override
  String get description =>
      'Wait for a specific element to appear on screen.\n\n'
      'Use this after an action (tap, type, etc.) to wait for the screen to '
      'update before taking the next screenshot.\n\n'
      'Parameters:\n'
      '- query: element text/ID to wait for (required)\n'
      '- by: "text", "id", "description" (default: "text")\n'
      '- timeout_ms: max wait time in milliseconds (default: 5000, max: 30000)\n\n'
      'Returns success with element details when found, or timeout error.\n\n'
      'Example: {"query": "Tìm kiếm", "by": "text", "timeout_ms": 3000}';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'Element text/ID to wait for.',
      },
      'by': {
        'type': 'string',
        'enum': ['text', 'id', 'description'],
        'description': 'How to match (default: "text").',
      },
      'timeout_ms': {
        'type': 'integer',
        'description': 'Max wait time in ms (default: 5000, max: 30000)',
      },
    },
    'required': ['query'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query'] as String?;
    if (query == null || query.isEmpty)
      return ToolResult.error('query is required');

    final by = (args['by'] as String?) ?? 'text';
    final timeoutMs = ((args['timeout_ms'] as int?) ?? 5000).clamp(1000, 30000);

    final start = DateTime.now();
    final maxAttempts = (timeoutMs / 500).floor().clamp(2, 60);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (elapsed >= timeoutMs) break;

      final r = await _svc.findElements(query: query, by: by);
      final elemList = r['elements'] as List<dynamic>? ?? [];

      if (elemList.isNotEmpty) {
        final first = elemList.first as Map<String, dynamic>;
        return ToolResult.success(
          jsonEncode({'found': true, 'element': first, 'waited_ms': elapsed}),
        );
      }

      if (attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return ToolResult.error('Element "$query" not found after ${timeoutMs}ms');
  }
}

// ─── Launch app ──────────────────────────────────────────────────────────────

class UiLaunchAppTool extends Tool {
  final UiAutomationService _svc;
  UiLaunchAppTool(this._svc);

  @override
  String get name => 'ui_launch_app';

  @override
  String get description =>
      'Open an installed app on the device.\n\n'
      'Two modes:\n'
      '- By package name: {"package": "com.android.settings"}\n'
      '- By search (app label): {"search": "Chrome"} — finds the first match\n\n'
      'Common packages:\n'
      '- Settings: com.android.settings\n'
      '- Chrome: com.android.chrome\n'
      '- Camera: varies by device (use search: "Camera")\n'
      '- Phone: com.android.dialer or com.samsung.android.dialer\n'
      '- Messages: com.google.android.apps.messaging\n'
      '- Gmail: com.google.android.gm\n'
      '- YouTube: com.google.android.youtube\n'
      '- Maps: com.google.android.apps.maps\n'
      '- Play Store: com.android.vending\n\n'
      'Use ui_list_apps to discover installed apps if unsure.\n\n'
      'Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'package': {
        'type': 'string',
        'description': 'Exact package name (e.g. "com.android.settings").',
      },
      'search': {
        'type': 'string',
        'description':
            'Search by app name/label (e.g. "Chrome"). Opens the first match.',
      },
    },
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final pkg = args['package'] as String?;
    final search = args['search'] as String?;
    if (pkg == null && search == null) {
      return ToolResult.error('Either "package" or "search" is required');
    }
    final r = await _svc.launchApp(package_: pkg, search: search);
    if (r['error'] == true)
      return ToolResult.error(r['message'] as String? ?? 'Failed');
    if (r['success'] == false)
      return ToolResult.error(r['message'] as String? ?? 'App not found');
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Launch intent ───────────────────────────────────────────────────────────

class UiLaunchIntentTool extends Tool {
  final UiAutomationService _svc;
  UiLaunchIntentTool(this._svc);

  @override
  String get name => 'ui_launch_intent';

  @override
  String get description =>
      'Fire an Android Intent to open specific screens, deep links, or system actions.\n\n'
      'Parameters:\n'
      '- action: Intent action (e.g. "android.intent.action.VIEW", "android.settings.WIFI_SETTINGS")\n'
      '- uri: Data URI (e.g. "https://example.com", "tel:+1234567890", "geo:0,0?q=coffee")\n'
      '- type: MIME type (e.g. "image/*")\n'
      '- package: target app package name\n'
      '- extras: key-value map of intent extras\n\n'
      'At least "action" or "uri" is required.\n\n'
      'Common intents:\n'
      '- Open URL: {"uri": "https://example.com"}\n'
      '- Call number: {"action": "android.intent.action.DIAL", "uri": "tel:+1234567890"}\n'
      '- Send email: {"action": "android.intent.action.SENDTO", "uri": "mailto:user@example.com"}\n'
      '- WiFi settings: {"action": "android.settings.WIFI_SETTINGS"}\n'
      '- Bluetooth settings: {"action": "android.settings.BLUETOOTH_SETTINGS"}\n'
      '- Location settings: {"action": "android.settings.LOCATION_SOURCE_SETTINGS"}\n'
      '- App details: {"action": "android.settings.APPLICATION_DETAILS_SETTINGS", "uri": "package:com.example.app"}\n'
      '- Share text: {"action": "android.intent.action.SEND", "type": "text/plain", "extras": {"android.intent.extra.TEXT": "Hello!"}}\n'
      '- Maps search: {"uri": "geo:0,0?q=restaurants+nearby"}\n'
      '- App deep links (examples; many apps document custom schemes): '
      '{"uri": "https://instagram.com/..."} or custom schemes if the app exports them '
      '(discover via ui_app_intents on the package).\n\n'
      '**Workflow with UI automation:** after launching, wait (use ui_batch_actions with '
      '{"action":"wait","ms":800} or a short pause) then call ui_find_elements or '
      'ui_screenshot before tapping — avoids racing the transition animation.\n\n'
      'Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'action': {'type': 'string', 'description': 'Intent action string.'},
      'uri': {'type': 'string', 'description': 'Data URI for the intent.'},
      'type': {
        'type': 'string',
        'description': 'MIME type (e.g. "text/plain", "image/*").',
      },
      'package': {
        'type': 'string',
        'description': 'Target package to restrict the intent to.',
      },
      'extras': {
        'type': 'object',
        'description': 'Key-value map of intent extras.',
      },
    },
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final action = args['action'] as String?;
    final uri = args['uri'] as String?;
    if (action == null && uri == null) {
      return ToolResult.error('At least "action" or "uri" is required');
    }
    final r = await _svc.launchIntent(
      action: action,
      uri: uri,
      type: args['type'] as String?,
      package_: args['package'] as String?,
      extras: (args['extras'] as Map<String, dynamic>?),
    );
    if (r['error'] == true)
      return ToolResult.error(r['message'] as String? ?? 'Failed');
    if (r['success'] == false)
      return ToolResult.error(r['message'] as String? ?? 'Intent failed');
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── List apps ───────────────────────────────────────────────────────────────

class UiListAppsTool extends Tool {
  final UiAutomationService _svc;
  UiListAppsTool(this._svc);

  @override
  String get name => 'ui_list_apps';

  @override
  String get description =>
      'List installed apps on the device.\n\n'
      'Parameters:\n'
      '- search: filter by app name or package name (optional)\n'
      '- launchable_only: if true (default), only show apps with a launcher icon\n\n'
      'Returns each app\'s package name, label, and whether it\'s a system app.\n\n'
      'Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'search': {
        'type': 'string',
        'description': 'Filter apps by name or package (case-insensitive).',
      },
      'launchable_only': {
        'type': 'boolean',
        'description': 'Only show apps with a launcher icon (default true).',
      },
    },
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final search = args['search'] as String?;
    final launchableOnly = args['launchable_only'] as bool? ?? true;
    final r = await _svc.listApps(
      launchableOnly: launchableOnly,
      search: search,
    );
    if (r['error'] == true)
      return ToolResult.error(r['message'] as String? ?? 'Failed');
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── App intents ─────────────────────────────────────────────────────────────

class UiAppIntentsTool extends Tool {
  final UiAutomationService _svc;
  UiAppIntentsTool(this._svc);

  @override
  String get name => 'ui_app_intents';

  @override
  String get description =>
      'Discover the exported activities and intent filters of a specific app.\n\n'
      'Use this to find out what intents an app accepts before calling ui_launch_intent.\n\n'
      'Workflow:\n'
      '1. ui_list_apps → find the app and its package name\n'
      '2. ui_app_intents → see what activities/intents it exports\n'
      '3. ui_launch_intent → open it with a crafted intent\n\n'
      'Returns exported activities with their intent filter actions, categories, '
      'URI schemes, and MIME types.\n\n'
      'Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'package': {
        'type': 'string',
        'description':
            'The package name of the app (e.g. "com.android.chrome").',
      },
    },
    'required': ['package'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final pkg = args['package'] as String?;
    if (pkg == null || pkg.isEmpty)
      return ToolResult.error('package is required');
    final r = await _svc.appIntents(pkg);
    if (r['error'] == true)
      return ToolResult.error(r['message'] as String? ?? 'Failed');
    return ToolResult.success(jsonEncode(r));
  }
}

// ─── Batch actions ────────────────────────────────────────────────────────────

class UiBatchActionsTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;
  UiBatchActionsTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_batch_actions';

  @override
  String get description =>
      'Execute multiple UI actions rapidly in sequence WITHOUT screenshots in between.\n\n'
      'Use this when you need to perform several quick actions back-to-back, such as:\n'
      '- Opening an app or deep link, then waiting, then tapping (e.g. launch_intent → wait → click)\n'
      '- Tapping the same spot repeatedly (e.g., Android Easter egg)\n'
      '- A quick sequence like: tap → type → tap submit\n'
      '- Multiple swipes in rapid succession\n'
      '- Any combo of tap/swipe/click/type/global/launch_*/wait\n\n'
      'Each action in the array is an object with "action" and its params:\n'
      '- {"action":"launch_intent","uri":"https://example.com/path"} — or use intent_action + package for app deep links\n'
      '- {"action":"launch_app","package":"com.android.chrome"} — or {"action":"launch_app","search":"Maps"}\n'
      '- {"action":"tap","x":540,"y":1200}\n'
      '- {"action":"swipe","x1":540,"y1":1800,"x2":540,"y2":600,"duration_ms":200}\n'
      '- {"action":"click","query":"OK","by":"text"}\n'
      '- {"action":"type","text":"hello"}\n'
      '- {"action":"global","name":"back"}\n'
      '- {"action":"wait","ms":500}\n\n'
      'delay_ms: optional pause between each action (default 100ms). Set to 0 for maximum speed.\n\n'
      'A screenshot is taken automatically AFTER all actions complete and returned in the result.\n\n'
      'Requires Accessibility Service. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'actions': {
        'type': 'array',
        'description': 'Array of action objects to execute in order.',
        'items': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'tap',
                'swipe',
                'click',
                'type',
                'global',
                'wait',
                'launch_intent',
                'launch_app',
              ],
              'description': 'The action type.',
            },
            'intent_action': {
              'type': 'string',
              'description':
                  'For launch_intent: Android intent action (e.g. android.intent.action.VIEW).',
            },
            'uri': {'type': 'string'},
            'type': {'type': 'string'},
            'package': {'type': 'string'},
            'extras': {'type': 'object'},
            'search': {
              'type': 'string',
              'description': 'For launch_app: find app by label.',
            },
            'x': {'type': 'number'},
            'y': {'type': 'number'},
            'x1': {'type': 'number'},
            'y1': {'type': 'number'},
            'x2': {'type': 'number'},
            'y2': {'type': 'number'},
            'duration_ms': {'type': 'integer'},
            'query': {'type': 'string'},
            'by': {'type': 'string'},
            'text': {'type': 'string'},
            'name': {'type': 'string'},
            'ms': {'type': 'integer'},
          },
          'required': ['action'],
        },
      },
      'delay_ms': {
        'type': 'integer',
        'description':
            'Pause between actions in ms (default 100). Set 0 for max speed.',
      },
    },
    'required': ['actions'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final actions = args['actions'] as List<dynamic>?;
    if (actions == null || actions.isEmpty) {
      return ToolResult.error(
        'actions array is required and must not be empty',
      );
    }
    final delayMs = (args['delay_ms'] as num?)?.toInt() ?? 100;
    final delay = Duration(milliseconds: delayMs);
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < actions.length; i++) {
      final a = actions[i] as Map<String, dynamic>;
      final type = a['action'] as String? ?? '';

      Map<String, dynamic> r;
      switch (type) {
        case 'tap':
          final x = (a['x'] as num?)?.toDouble();
          final y = (a['y'] as num?)?.toDouble();
          if (x == null || y == null) {
            results.add({'action': 'tap', 'error': 'x and y required'});
            continue;
          }
          _overlay?.showTapFeedback(x, y);
          r = await _svc.tap(x, y);
        case 'swipe':
          final sx1 = (a['x1'] as num?)?.toDouble();
          final sy1 = (a['y1'] as num?)?.toDouble();
          final sx2 = (a['x2'] as num?)?.toDouble();
          final sy2 = (a['y2'] as num?)?.toDouble();
          if (sx1 == null || sy1 == null || sx2 == null || sy2 == null) {
            results.add({'action': 'swipe', 'error': 'x1,y1,x2,y2 required'});
            continue;
          }
          _overlay?.showSwipeFeedback(sx1, sy1, sx2, sy2);
          final dur = (a['duration_ms'] as num?)?.toInt() ?? 300;
          r = await _svc.swipe(sx1, sy1, sx2, sy2, durationMs: dur);
        case 'click':
          final query = a['query'] as String? ?? '';
          final by = a['by'] as String? ?? 'text';
          r = await _svc.clickElement(query, by);
          final cx = (r['centerX'] as num?)?.toDouble();
          final cy = (r['centerY'] as num?)?.toDouble();
          if (cx != null && cy != null) _overlay?.showTapFeedback(cx, cy);
        case 'type':
          final text = a['text'] as String? ?? '';
          _overlay?.showTypeFeedback(text);
          r = await _svc.typeText(text);
        case 'global':
          final gName = a['name'] as String? ?? '';
          r = await _svc.globalAction(gName);
        case 'launch_intent':
          final iAction = a['intent_action'] as String?;
          final uri = a['uri'] as String?;
          if (iAction == null && uri == null) {
            results.add({
              'action': 'launch_intent',
              'error': 'intent_action or uri required',
            });
            continue;
          }
          r = await _svc.launchIntent(
            action: iAction,
            uri: uri,
            type: a['type'] as String?,
            package_: a['package'] as String?,
            extras: a['extras'] as Map<String, dynamic>?,
          );
        case 'launch_app':
          final pkg = a['package'] as String?;
          final search = a['search'] as String?;
          if (pkg == null && search == null) {
            results.add({
              'action': 'launch_app',
              'error': 'package or search required',
            });
            continue;
          }
          r = await _svc.launchApp(package_: pkg, search: search);
        case 'wait':
          final ms = (a['ms'] as num?)?.toInt() ?? 500;
          await Future<void>.delayed(Duration(milliseconds: ms));
          results.add({'action': 'wait', 'ms': ms, 'success': true});
          continue;
        default:
          results.add({'action': type, 'error': 'unknown action type'});
          continue;
      }

      results.add({'action': type, ...r});

      if (delayMs > 0 && i < actions.length - 1) {
        await Future<void>.delayed(delay);
      }
    }

    // Auto-screenshot after batch completes
    final screenshotAndElements = await Future.wait([
      _svc.screenshot(),
      _svc.findElements(by: 'all'),
    ]);
    final screenshot = screenshotAndElements[0];
    final elemResults = screenshotAndElements[1];
    final elemList = elemResults['elements'] as List<dynamic>? ?? [];

    final summary = StringBuffer();
    summary.writeln('=== Batch: ${results.length} actions executed ===');
    for (final r in results) {
      final err = r['error'];
      summary.writeln('- ${r['action']}: ${err != null ? "ERROR $err" : "ok"}');
    }
    summary.writeln();
    summary.writeln('=== Screen Elements (${elemList.length}) ===');
    for (final e in elemList) {
      if (e is! Map<String, dynamic>) continue;
      final text = e['text'] as String?;
      final desc = e['contentDescription'] as String?;
      final cls = (e['className'] as String? ?? '').split('.').last;
      final clickable = e['isClickable'] == true;
      final cx = e['centerX'];
      final cy = e['centerY'];
      final label = text ?? desc ?? e['resourceId'] as String? ?? cls;
      if (label.isEmpty) continue;
      final tag = clickable ? '[clickable]' : '';
      summary.writeln('- "$label" $tag at ($cx, $cy) [$cls]');
    }

    if (screenshot['error'] == true) {
      return ToolResult.success(summary.toString().trim());
    }

    final output = {
      'type': 'image',
      'data': screenshot['data'],
      'mimeType': screenshot['mimeType'] ?? 'image/jpeg',
      'note': summary.toString().trim(),
    };
    return ToolResult.success(jsonEncode(output));
  }
}

// ─── Ask user (interactive overlay) ──────────────────────────────────────────

class UiAskUserTool extends Tool {
  final OverlayService _overlay;
  UiAskUserTool(this._overlay);

  @override
  String get name => 'ui_ask_user';

  @override
  String get description =>
      'Ask the user a question via the floating overlay when you are stuck '
      'during UI automation and cannot proceed without user input.\n\n'
      'Use this ONLY when you genuinely need information you cannot infer:\n'
      '- A password or PIN\n'
      '- A choice between ambiguous options on screen\n'
      '- Confirmation before a destructive action\n'
      '- Information like a specific contact name, address, or message\n\n'
      'Do NOT use this to ask "should I continue?" or report progress. '
      'The user expects you to work autonomously.\n\n'
      'The overlay appears on top of the current app. The user sees your '
      'question and can tap a button or type a response.\n\n'
      'Set input_type to "text" when you need free-form input (passwords, '
      'names, messages). Use "buttons" (default) for multiple-choice.\n\n'
      'Returns the user\'s response, or "timeout" if they did not respond '
      'within 60 seconds, or "dismissed" if they closed the overlay.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'question': {
        'type': 'string',
        'description':
            'The question to show the user. Keep it short and clear.',
      },
      'options': {
        'type': 'array',
        'description':
            'Button options for the user to choose from (1-4 options). '
            'Required when input_type is "buttons". Each option has a '
            '"label" (display text) and "value" (returned to you).',
        'items': {
          'type': 'object',
          'properties': {
            'label': {
              'type': 'string',
              'description': 'Button text shown to user',
            },
            'value': {
              'type': 'string',
              'description': 'Value returned when tapped',
            },
          },
          'required': ['label', 'value'],
        },
        'minItems': 1,
        'maxItems': 4,
      },
      'input_type': {
        'type': 'string',
        'enum': ['buttons', 'text'],
        'description':
            'Type of input: "buttons" for multiple-choice (default), '
            '"text" for free-form text input (passwords, names, etc.).',
      },
    },
    'required': ['question'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final question = args['question'] as String?;
    if (question == null || question.isEmpty) {
      return ToolResult.error('question is required');
    }

    final inputType = args['input_type'] as String? ?? 'buttons';
    final isTextInput = inputType == 'text';

    if (!isTextInput) {
      final options = args['options'] as List<dynamic>?;
      if (options == null || options.isEmpty) {
        return ToolResult.error(
          'options are required when input_type is "buttons"',
        );
      }

      final buttons = options.map((o) {
        final m = o as Map<String, dynamic>;
        return OverlayButton(
          label: m['label'] as String? ?? '',
          value: m['value'] as String? ?? '',
        );
      }).toList();

      final response = await _overlay.showMessage(
        text: question,
        buttons: buttons,
      );

      return ToolResult.success(
        jsonEncode({
          'user_response': response,
          'was_timeout': response == 'timeout',
          'was_dismissed': response == 'dismissed',
        }),
      );
    } else {
      // Text input mode — hint from first option label if provided
      final options = args['options'] as List<dynamic>?;
      List<OverlayButton>? hintButtons;
      if (options != null && options.isNotEmpty) {
        hintButtons = options.map((o) {
          final m = o as Map<String, dynamic>;
          return OverlayButton(
            label: m['label'] as String? ?? '',
            value: m['value'] as String? ?? '',
          );
        }).toList();
      }

      final response = await _overlay.showMessage(
        text: question,
        buttons: hintButtons,
        textInput: true,
      );

      return ToolResult.success(
        jsonEncode({
          'user_response': response,
          'was_timeout': response == 'timeout',
          'was_dismissed': response == 'dismissed',
        }),
      );
    }
  }
}

// ─── Status overlay (lightweight step narration) ────────────────────────────

class UiStatusTool extends Tool {
  final OverlayService _overlay;
  UiStatusTool(this._overlay);

  @override
  String get name => 'ui_status';

  @override
  String get description =>
      'Show a short status message on the user\'s screen overlay. '
      'Use this to narrate each step during UI automation so the user '
      'can follow your progress in real time. Messages should be brief '
      '(under 8 words) and specific to the current action.\n\n'
      'Examples: "Opening Settings", "Looking for Wi-Fi", '
      '"Scrolling down", "Typing the password".\n\n'
      'This tool is instant and does not interrupt your workflow.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'text': {
        'type': 'string',
        'description':
            'Short status message to display (max ~50 chars). '
            'Write in the user\'s language.',
      },
    },
    'required': ['text'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final text = args['text'] as String?;
    if (text == null || text.isEmpty) {
      return ToolResult.error('text is required');
    }
    await _overlay.show(text);
    return ToolResult.success('ok');
  }
}
