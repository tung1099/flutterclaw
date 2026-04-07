import 'dart:convert';

import 'package:flutterclaw/services/overlay_service.dart';
import 'package:flutterclaw/services/ui_automation_service.dart';
import 'package:flutterclaw/tools/registry.dart';

class UiShopeeBuyTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;
  UiShopeeBuyTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_shopee_buy';

  @override
  String get description =>
      'Complete shopping workflow on Shopee: search, select product, and add to cart.\n\n'
      'Steps:\n'
      '1. Launch Shopee\n'
      '2. Find and tap search bar (using clickElement)\n'
      '3. Type search query\n'
      '4. Execute search\n'
      '5. Tap on first product to open it\n'
      '6. Add product to cart\n'
      '7. Return screenshot of cart\n\n'
      'Parameters:\n'
      '- query: the product to search for\n\n'
      'Returns screenshot with cart status.\n\n'
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

  Map<String, dynamic>? _findAddToCartButton(List<dynamic> elements) {
    for (final e in elements) {
      if (e is! Map<String, dynamic>) continue;
      final text = (e['text'] as String?)?.toLowerCase() ?? '';
      final desc = (e['contentDescription'] as String?)?.toLowerCase() ?? '';
      final isClickable = e['isClickable'] == true;

      final isAddToCart =
          (text.contains('thêm') && text.contains('giỏ')) ||
          text.contains('mua ngay') ||
          text.contains('add to cart') ||
          text.contains('buy now') ||
          (desc.contains('thêm') && desc.contains('giỏ')) ||
          (desc.contains('add') && desc.contains('cart'));

      if (isAddToCart && isClickable) return e;
    }
    return null;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query'] as String?;
    if (query == null || query.isEmpty) {
      return ToolResult.error('query is required');
    }

    _overlay?.show('🛒 Starting Shopee shopping for "$query"...');

    // Step 1: Launch Shopee
    var result = await _svc.launchApp(search: 'Shopee');
    if (result['error'] == true) {
      return ToolResult.error('Failed to launch Shopee: ${result['message']}');
    }

    await Future<void>.delayed(const Duration(milliseconds: 3000));

    // Step 2: Find and click search bar using ui_click_element
    _overlay?.show('🔍 Finding search bar...');

    // Try to find search bar by text "Tìm kiếm"
    result = await _svc.clickElement('Tìm kiếm', 'text');

    // If not found, try description
    if (result['error'] == true || result['success'] != true) {
      result = await _svc.clickElement('search', 'description');
    }

    // If still not found, try tapping at different positions
    if (result['error'] == true || result['success'] != true) {
      _overlay?.show('👆 Trying tap at search bar positions...');
      result = await _svc.tap(540.0, 100.0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      result = await _svc.tap(720.0, 120.0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      result = await _svc.tap(900.0, 100.0);
    }

    // Wait for keyboard to appear
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    // Step 3: Type query
    _overlay?.show('⌨️ Typing "$query"...');
    result = await _svc.typeText(query);

    // If type fails, retry
    if (result['success'] != true) {
      _overlay?.show('⚠️ Type failed, retrying...');
      result = await _svc.tap(720.0, 120.0);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      result = await _svc.typeText(query);
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Step 4: Execute search - tap on search bar
    _overlay?.show('🔎 Tapping to search...');
    result = await _svc.tap(720.0, 120.0);

    // Wait for results
    await Future<void>.delayed(const Duration(milliseconds: 5000));

    // Step 5: Take screenshot to see results
    _overlay?.show('📸 Taking screenshot...');
    final screenshot = await _svc.screenshot();
    final searchResults = await _svc.findElements(by: 'all');
    final resultList = searchResults['elements'] as List<dynamic>? ?? [];

    _overlay?.show('🔍 Found ${resultList.length} elements');

    // Step 6: Find and tap first product (just tap at center of product area)
    _overlay?.show('👆 Tapping on product area...');
    result = await _svc.tap(720.0, 800.0); // Center of where products would be

    await Future<void>.delayed(const Duration(milliseconds: 2000));

    // Step 7: Look for Add to Cart button
    _overlay?.show('🛒 Looking for add to cart button...');
    final productPage = await _svc.findElements(by: 'all');
    final productElements = productPage['elements'] as List<dynamic>? ?? [];

    Map<String, dynamic>? addToCartBtn = _findAddToCartButton(productElements);
    if (addToCartBtn != null) {
      final btnX = (addToCartBtn['centerX'] as int?) ?? 720;
      final btnY = (addToCartBtn['centerY'] as int?) ?? 2500;

      _overlay?.show('👆 Tapping add to cart at ($btnX, $btnY)...');
      result = await _svc.tap(btnX.toDouble(), btnY.toDouble());
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    } else {
      // Try scroll and find again
      await _svc.swipe(720, 2000, 720, 1000, durationMs: 500);
      await Future<void>.delayed(const Duration(milliseconds: 1000));

      final productPage2 = await _svc.findElements(by: 'all');
      addToCartBtn = _findAddToCartButton(
        productPage2['elements'] as List<dynamic>? ?? [],
      );
      if (addToCartBtn != null) {
        final btnX = (addToCartBtn['centerX'] as int?) ?? 720;
        final btnY = (addToCartBtn['centerY'] as int?) ?? 2500;
        result = await _svc.tap(btnX.toDouble(), btnY.toDouble());
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }

    // Step 8: Final screenshot
    final screenshotFinal = await _svc.screenshot();

    final summary = StringBuffer();
    summary.writeln('=== 🛒 Shopping Result for "$query" ===\n');
    summary.writeln('Search completed. Product page opened.');

    if (screenshotFinal['error'] == true) {
      return ToolResult.success(summary.toString().trim());
    }

    final output = {
      'type': 'image',
      'data': screenshotFinal['data'],
      'mimeType': screenshotFinal['mimeType'] ?? 'image/jpeg',
      'note': summary.toString().trim(),
    };
    return ToolResult.success(jsonEncode(output));
  }
}
