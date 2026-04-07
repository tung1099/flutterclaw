---
name: shopping
description: Shop on Shopee, Lazada, TikTok Shop and other e-commerce apps
emoji: 🛒
---

# Shopping Assistant

Help users find and buy products on e-commerce apps like Shopee, Lazada, TikTok Shop.

## When to use
- User says "buy X", "order X", "mua X"
- User says "search for X on Shopee"
- User wants to find a specific product online

## Available Apps

Common shopping apps (use with `ui_launch_app`):
- **Shopee**: search="Shopee" or package="com.shopee.vn" (Vietnam) / "com.shopee.id" (Indonesia) / "com.shopee.my" (Malaysia)
- **Lazada**: search="Lazada"
- **TikTok Shop**: search="TikTok Shop" or package="com.shopline.android"
- **Amazon**: search="Amazon"
- **Taobao/Tmall**: search="Taobao"

## Workflow: Buy a Product

### Step 1: Launch the app
```json
ui_launch_app {"search": "Shopee"}
```

### Step 2: Wait for app to load
After launching, wait 1-2 seconds. Use ui_screenshot or ui_batch_actions:
```json
ui_batch_actions {"actions": [{"action": "wait", "ms": 1500}]}
```

### Step 3: Find the search bar
Use ui_screenshot to see screen elements:
```json
ui_screenshot {}
```

Look for elements like:
- "Tìm kiếm" (Vietnamese: Search)
- "Search"
- A magnifying glass icon

Tap the search bar using ui_click_element or ui_tap with coordinates.

### Step 4: Enter search query
```json
ui_type_text {"text": "tương ớt"}
```

### Step 5: Execute search
Tap the search button or press Enter. Use ui_tap on the search button coordinates, or:
```json
ui_global_action {"action": "enter"}
```

### Step 6: Browse results
```json
ui_screenshot {}
```

Scroll down to see more products:
```json
ui_swipe {"x1": 540, "y1": 1800, "x2": 540, "y2": 600}
```

### Step 7: Select a product
Tap on the product image or name:
```json
ui_click_element {"query": "tương ớt", "by": "text"}
```

Or use ui_tap with coordinates from screenshot.

### Step 8: Product details
```json
ui_screenshot {}
```

Look for:
- Price
- "Thêm vào giỏ" (Add to Cart)
- "Mua ngay" (Buy Now)
- Shipping info
- Seller rating

### Step 9: Add to cart or buy now
```json
ui_click_element {"query": "Thêm vào giỏ", "by": "text"}
```

Or for immediate purchase:
```json
ui_click_element {"query": "Mua ngay", "by": "text"}
```

### Step 10: Checkout
Follow on-screen prompts:
- Select address
- Select payment method
- Confirm order

## Tips for Shopee

1. **Search bar**: Usually at top of screen with "Tìm kiếm trên Shopee" placeholder
2. **Vouchers**: Look for "Mã giảm giá" or voucher badges on products
3. **Shipping**: Check "Miễn phí vận chuyển" for free shipping
4. **Ratings**: Look for products with 4.5+ stars
5. **Shopee Live**: Check for "Shopee Live" for live shopping deals

## Common Vietnamese UI Elements

| Vietnamese | English |
|------------|---------|
| Tìm kiếm | Search |
| Thêm vào giỏ | Add to Cart |
| Mua ngay | Buy Now |
| Giỏ hàng | Cart |
| Thanh toán | Checkout/Pay |
| Địa chỉ | Address |
| Vận chuyển | Shipping |
| Miễn phí vận chuyển | Free shipping |
| Đánh giá | Rating/Review |
| Yêu thích | Wishlist/Favorite |

## Troubleshooting

- **App won't open**: Check if app is installed with `ui_list_apps`
- **Can't find search bar**: Use ui_screenshot and look for text fields
- **Typing doesn't work**: Make sure you tapped the text field first
- **Element not found**: Try scrolling or use ui_find_elements with different query
- **App in background**: FlutterClaw loses screen access when backgrounded. Ask user to bring app to foreground or use overlay to ask for help.

## Safety Reminders

1. **Confirm price** before checkout
2. **Check seller rating** before buying
3. **Verify shipping costs** are included
4. **Ask user for confirmation** before completing purchase
5. Use `ui_ask_user` for critical decisions
