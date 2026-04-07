---
name: weather
description: Get current weather and forecast for any location
emoji: 🌤️
---

# Weather Skill

Use web search to get weather information when user asks about weather.

## When to use
- User asks about current weather (e.g., "thời tiết hôm nay", "trời hôm nay")
- User asks for weather forecast (e.g., "dự báo thời tiết", "trời ngày mai")
- User asks about temperature, rain, humidity in a specific location

## How to use
1. Use `web_search` to find current weather for the requested location
2. Extract key info: temperature, conditions (sunny/rainy/cloudy), humidity, wind
3. Present in user's language with location name

## Example queries
- "Thời tiết Hà Nội hôm nay" → Search "weather Hanoi today"
- "Trời TP HCM có mưa không" → Search "weather Ho Chi Minh City rain"
- "Dự báo thờ tiết tuần này" → Search "weather forecast this week [location]"

## Tips
- Always include location in search query
- For Vietnamese users, search in English but respond in Vietnamese
- Include source URL in response