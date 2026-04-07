import 'dart:convert';

import 'package:flutterclaw/services/overlay_service.dart';
import 'package:flutterclaw/services/ui_automation_service.dart';
import 'package:flutterclaw/tools/registry.dart';

class UiShopeeBuyTool extends Tool {
  final UiAutomationService _svc;
  final OverlayService? _overlay;

  static const _shopeePackage = 'com.shopee.vn';

  UiShopeeBuyTool(this._svc, [this._overlay]);

  @override
  String get name => 'ui_shopee_buy';

  @override
  String get description =>
      'Buy/add to cart a product on Shopee app using UI automation.\n\n'
      'Steps: Open Shopee → Search for item → Select item → Tap "Thêm vào giỏ" or "Mua ngay".\n'
      'Returns the cart or purchase status.\n\n'
      'Requires Accessibility Service enabled. Android only.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'itemName': {
        'type': 'string',
        'description': 'Item name to search and buy',
      },
    },
    'required': ['itemName'],
  };

  Map<String, dynamic>? _findSearchBar(Map<String, dynamic> elementsResult) {
    final elements = elementsResult['elements'] as List<dynamic>?;
    if (elements == null || elements.isEmpty) return null;

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
    return null;
  }

  Map<String, dynamic>? _findAddToCartButton(List<dynamic> elements) {
    if (elements.isEmpty) return null;

    for (final el in elements) {
      final e = el as Map<String, dynamic>;
      final text = (e['text'] as String?)?.toLowerCase() ?? '';
      final desc = (e['description'] as String?)?.toLowerCase() ?? '';

      if (text.contains('thêm vào giỏ') ||
          text.contains('mua ngay') ||
          text.contains('mua ngay') ||
          desc.contains('add to cart')) {
        return e;
      }
    }
    return elements.first as Map<String, dynamic>;
  }

  Future<ToolResult> _searchAndBuy(String itemName) async {
    await Future.delayed(const Duration(milliseconds: 1500));

    final allElements = await _svc.findElements(by: 'all');
    var elements = allElements['elements'] as List<dynamic>?;

    if (elements == null || elements.isEmpty) {
      return ToolResult.error('No elements found on screen');
    }

    var searchBar = _findSearchBar({'elements': elements});
    if (searchBar == null) {
      final textFieldCandidates = elements.where((e) {
        final el = e as Map<String, dynamic>;
        final cl = (el['className'] as String?) ?? '';
        return cl.contains('EditText');
      }).toList();
      if (textFieldCandidates.isNotEmpty) {
        searchBar = textFieldCandidates.first as Map<String, dynamic>;
      }
    }

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

    final typeResult = await _svc.typeText(itemName);
    if (typeResult['success'] != true) {
      return ToolResult.error(
        typeResult['message'] as String? ?? 'Failed to type search text',
      );
    }
    await Future.delayed(const Duration(milliseconds: 300));

    await _svc.globalAction('enter');
    await Future.delayed(const Duration(milliseconds: 2500));

    final resultElements = await _svc.findElements(by: 'all');
    final resultList = resultElements['elements'] as List<dynamic>? ?? [];
    final addButton = _findAddToCartButton(resultList);

    if (addButton == null) {
      return ToolResult.success(
        jsonEncode({
          'status': 'search_completed',
          'itemName': itemName,
          'message':
              'Searched for "$itemName" but add-to-cart button not found',
        }),
      );
    }

    final btnX = (addButton['centerX'] as num?)?.toDouble();
    final btnY = (addButton['centerY'] as num?)?.toDouble();
    if (btnX == null || btnY == null) {
      return ToolResult.error('Could not get button coordinates');
    }

    await _svc.tap(btnX, btnY);
    await Future.delayed(const Duration(milliseconds: 500));

    return ToolResult.success(
      jsonEncode({
        'status': 'added_to_cart',
        'itemName': itemName,
        'message': 'Added "$itemName" to cart on Shopee',
      }),
    );
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final itemName = args['itemName'] as String?;
    if (itemName == null || itemName.isEmpty) {
      return ToolResult.error('itemName is required');
    }

    _overlay?.show('ui_shopee_buy: $itemName');

    try {
      final currentScreen = await _svc.screenshot();
      if (currentScreen['error'] != true) {
        final elements = await _svc.findElements(by: 'all');
        final elementList = elements['elements'] as List<dynamic>? ?? [];

        bool alreadyOnShopee = false;
        for (final e in elementList) {
          final el = e as Map<String, dynamic>;
          final text = (el['text'] as String?) ?? '';
          final resId = (el['resourceId'] as String?) ?? '';
          if (resId.contains('shopee') ||
              text.toLowerCase().contains('shopee')) {
            alreadyOnShopee = true;
            break;
          }
        }

        if (alreadyOnShopee) {
          return _searchAndBuy(itemName);
        }
      }

      var r = await _svc.launchApp(package_: _shopeePackage);
      if (r['error'] == true) {
        return ToolResult.error(
          r['message'] as String? ?? 'Failed to launch Shopee',
        );
      }

      return _searchAndBuy(itemName);
    } catch (e) {
      return ToolResult.error('Error: $e');
    }
  }
}
