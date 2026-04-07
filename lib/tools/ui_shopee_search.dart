import 'dart:convert';

import 'package:flutterclaw/services/overlay_service.dart';
import 'package:flutterclaw/services/ui_automation_service.dart';
import 'package:flutterclaw/tools/registry.dart';

class UiShopeeSearchTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;
  UiShopeeSearchTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_shopee_search';

  @override
  String get description =>
      'Open Shopee, search for a product, and show results.\n\n'
      'Steps:\n'
      '1. Launch Shopee app\n'
      '2. Wait for app to load\n'
      '3. Tap on search bar to focus it\n'
      '4. Type the search query\n'
      '5. Press Enter to search\n'
      '6. Return screenshot with results\n\n'
      'Parameters:\n'
      '- query: the product to search for (e.g., "tương ớt", "iPhone 15")\n\n'
      'Returns screenshot with search results.\n\n'
      'Android only. Requires Accessibility Service.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'Product to search for (e.g., "tương ớt", "iPhone 15")',
      },
    },
    'required': ['query'],
  };

  Map<String, dynamic>? _findSearchBar(List<dynamic> elements) {
    for (final e in elements) {
      if (e is! Map<String, dynamic>) continue;
      final text = (e['text'] as String?)?.toLowerCase() ?? '';
      final desc = (e['contentDescription'] as String?)?.toLowerCase() ?? '';
      final resourceId = (e['resourceId'] as String?)?.toLowerCase() ?? '';
      final cls = (e['className'] as String? ?? '').toLowerCase();
      final isClickable = e['isClickable'] == true;

      final isSearchBar =
          text.contains('tìm kiếm') ||
          text.contains('search') ||
          desc.contains('tìm kiếm') ||
          desc.contains('search') ||
          resourceId.contains('search') ||
          resourceId.contains('edit_text') ||
          (cls.contains('edittext') && isClickable);

      if (isSearchBar) return e;
    }
    return null;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query'] as String?;
    if (query == null || query.isEmpty) {
      return ToolResult.error('query is required');
    }

    _overlay?.show('🔍 Opening Shopee & searching for "$query"...');

    var r = await _svc.launchApp(search: 'Shopee');
    if (r['error'] == true) {
      return ToolResult.error('Failed to launch Shopee: ${r['message']}');
    }

    await Future<void>.delayed(const Duration(milliseconds: 2500));

    // Get all elements
    final allElements = await _svc.findElements(by: 'all');
    final elemList = allElements['elements'] as List<dynamic>? ?? [];

    // Find search bar
    Map<String, dynamic>? searchBar = _findSearchBar(elemList);

    int searchBarX = 720;
    int searchBarY = 120;

    if (searchBar != null) {
      searchBarX = (searchBar['centerX'] as int?) ?? 720;
      searchBarY = (searchBar['centerY'] as int?) ?? 120;
      _overlay?.show('✅ Found search bar at ($searchBarX, $searchBarY)');
    }

    // Tap search bar to focus input field
    _overlay?.show('👆 Tapping search bar...');
    r = await _svc.tap(searchBarX.toDouble(), searchBarY.toDouble());
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    // Type the query
    _overlay?.show('⌨️ Typing "$query"...');
    r = await _svc.typeText(query);

    // If type fails, retry
    if (r['success'] != true) {
      _overlay?.show('⚠️ Retry tapping and typing...');
      r = await _svc.tap(searchBarX.toDouble(), searchBarY.toDouble());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      r = await _svc.typeText(query);
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Execute search - tap on search bar again to trigger search
    // This is more reliable than pressing enter
    _overlay?.show('🔎 Tapping search bar to execute search...');

    // Tap on the search bar to trigger search
    await _svc.tap(searchBarX.toDouble(), searchBarY.toDouble());

    // Wait for results
    await Future<void>.delayed(const Duration(milliseconds: 2000));

    // Take screenshot
    final screenshot = await _svc.screenshot();
    final elemResult = await _svc.findElements(by: 'all');
    final elemListFinal = elemResult['elements'] as List<dynamic>? ?? [];

    final summary = StringBuffer();
    summary.writeln('=== 🔍 Search Results for "$query" ===\n');

    int productCount = 0;
    for (final e in elemListFinal) {
      if (e is! Map<String, dynamic>) continue;
      final text = e['text'] as String?;
      final desc = e['contentDescription'] as String?;
      final clickable = e['isClickable'] == true;
      final cx = e['centerX'];
      final cy = e['centerY'];
      final label = text ?? desc ?? '';
      if (label.isEmpty || !clickable) continue;

      if (productCount < 8) {
        summary.writeln('• "$label" at ($cx, $cy)');
        productCount++;
      }
    }

    if (productCount == 0) {
      summary.writeln('(No products found - try scrolling down)');
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
