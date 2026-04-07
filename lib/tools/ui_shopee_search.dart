import 'dart:convert';

import 'package:flutterclaw/services/overlay_service.dart';
import 'package:flutterclaw/services/ui_automation_service.dart';
import 'package:flutterclaw/tools/registry.dart';

class UiShopeeSearchTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;

  static const _shopeePackage = 'com.shopee.vn';

  UiShopeeSearchTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_shopee_search';

  @override
  String get description =>
      'Search for products on Shopee app using UI automation.\n\n'
      'Steps: Launch Shopee app → Tap search bar → Type keyword → Submit search.\n'
      'Returns the search results page status.\n\n'
      'Requires Accessibility Service enabled. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'keyword': {
        'type': 'string',
        'description': 'Search keyword for products',
      },
    },
    'required': ['keyword'],
  };

  Map<String, dynamic>? _findSearchBarElement(List<dynamic> elements) {
    for (final el in elements) {
      final e = el as Map<String, dynamic>;
      final text = (e['text'] as String?)?.toLowerCase() ?? '';
      final desc = (e['description'] as String?)?.toLowerCase() ?? '';
      final resId = (e['resourceId'] as String?) ?? '';

      if (text.contains('tìm') ||
          text.contains('search') ||
          text.contains('tim') ||
          desc.contains('search') ||
          resId.contains('search_bar')) {
        return e;
      }
    }

    final textFields = elements.where((e) {
      final el = e as Map<String, dynamic>;
      final cl = (el['className'] as String?) ?? '';
      return cl.contains('EditText');
    }).toList();
    if (textFields.isNotEmpty) {
      return textFields.first as Map<String, dynamic>;
    }
    return null;
  }

  Future<ToolResult> _doSearch(String keyword) async {
    await Future.delayed(const Duration(milliseconds: 1500));

    final allElements = await _svc.findElements(by: 'all');
    final elements = allElements['elements'] as List<dynamic>? ?? [];

    if (elements.isEmpty) {
      return ToolResult.error('No elements found on screen');
    }

    final searchBar = _findSearchBarElement(elements);
    if (searchBar == null) {
      return ToolResult.error('Search bar not found on Shopee');
    }

    final x = (searchBar['centerX'] as num?)?.toDouble();
    final y = (searchBar['centerY'] as num?)?.toDouble();
    if (x == null || y == null) {
      return ToolResult.error('Could not get search bar coordinates');
    }

    await _svc.tap(x, y);
    await Future.delayed(const Duration(milliseconds: 500));

    final typeResult = await _svc.typeText(keyword);
    if (typeResult['success'] != true) {
      return ToolResult.error(
        typeResult['message'] as String? ?? 'Failed to type search text',
      );
    }
    await Future.delayed(const Duration(milliseconds: 300));

    await _svc.globalAction('enter');
    await Future.delayed(const Duration(milliseconds: 1500));

    final screenshot = await _svc.screenshot();
    final hasScreenshot = screenshot['error'] != true;

    return ToolResult.success(
      jsonEncode({
        'status': 'search_completed',
        'keyword': keyword,
        'message': 'Searched for "$keyword" on Shopee',
        'screenshot': hasScreenshot ? 'available' : 'unavailable',
      }),
    );
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final keyword = args['keyword'] as String?;
    if (keyword == null || keyword.isEmpty) {
      return ToolResult.error('keyword is required');
    }

    _overlay?.show('ui_shopee_search: $keyword');

    try {
      final elements = await _svc.findElements(by: 'all');
      final elementList = elements['elements'] as List<dynamic>? ?? [];

      bool alreadyOnShopee = false;
      for (final e in elementList) {
        final el = e as Map<String, dynamic>;
        final text = (el['text'] as String?) ?? '';
        final resId = (el['resourceId'] as String?) ?? '';
        if (resId.contains('shopee') || text.toLowerCase().contains('shopee')) {
          alreadyOnShopee = true;
          break;
        }
      }

      if (alreadyOnShopee) {
        return _doSearch(keyword);
      }

      var r = await _svc.launchApp(package_: _shopeePackage);
      if (r['error'] == true) {
        return ToolResult.error(
          r['message'] as String? ?? 'Failed to launch Shopee',
        );
      }

      return _doSearch(keyword);
    } catch (e) {
      return ToolResult.error('Error: $e');
    }
  }
}
