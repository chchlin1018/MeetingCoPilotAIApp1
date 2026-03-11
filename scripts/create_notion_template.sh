#!/bin/bash
# ════════════════════════════════════════════════════════
# create_notion_template.sh
# 建立 MeetingCopilot PreMeeting 範例頁面到 Notion
# ════════════════════════════════════════════════════════
#
# 用法: 
#   export NOTION_API_KEY="ntn_..."
#   bash scripts/create_notion_template.sh
#
# 或者直接:
#   NOTION_API_KEY="ntn_..." bash scripts/create_notion_template.sh
#
# ════════════════════════════════════════════════════════

set -e

if [ -z "$NOTION_API_KEY" ]; then
    echo "❌ 請設定 NOTION_API_KEY"
    echo "  export NOTION_API_KEY=\"ntn_...\""
    exit 1
fi

echo "🔍 搜尋 MeetingCopilot parent page..."

# Step 1: 搜尋 parent page
PARENT_RESULT=$(curl -s -X POST 'https://api.notion.com/v1/search' \
    -H "Authorization: Bearer $NOTION_API_KEY" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{
        "query": "MeetingCopilot",
        "filter": {"property": "object", "value": "page"},
        "page_size": 1
    }')

PARENT_ID=$(echo "$PARENT_RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('results', [])
if results:
    print(results[0]['id'])
else:
    print('')
" 2>/dev/null || echo "")

if [ -z "$PARENT_ID" ]; then
    echo "⚠️  找不到 MeetingCopilot page，將建立為頂層 page"
    echo "❌ 請先在 Notion 建立一個「MeetingCopilot」page，並在 Connections 加入你的 Integration"
    exit 1
fi

echo "✅ 找到 parent page: $PARENT_ID"
echo "📝 建立 PreMeeting 範例頁面..."

# Step 2: 建立範例頁面
RESULT=$(curl -s -X POST 'https://api.notion.com/v1/pages' \
    -H "Authorization: Bearer $NOTION_API_KEY" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d "$(cat <<'JSONEOF'
{
    "parent": {"page_id": "PARENT_PLACEHOLDER"},
    "properties": {
        "title": [
            {"type": "text", "text": {"content": "PreMeeting: Michael's QBR 11 Mar 2026"}}
        ]
    },
    "children": [
        {
            "object": "block", "type": "callout",
            "callout": {
                "rich_text": [{"type": "text", "text": {"content": "MeetingCopilot PreMeeting Template \u2014 \u6703\u524d\u6e96\u5099\u8cc7\u6599\u7bc4\u672c"}}],
                "icon": {"type": "emoji", "emoji": "\ud83d\udcdd"}
            }
        },
        {
            "object": "block", "type": "heading_2",
            "heading_2": {"rich_text": [{"type": "text", "text": {"content": "\ud83c\udfaf Goals"}}]}
        },
        {
            "object": "block", "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "\u53d6\u5f97 UMC Digital Twin PoC \u9810\u7b97\u6838\u51c6"}}]}
        },
        {
            "object": "block", "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "\u78ba\u8a8d\u6280\u8853\u67b6\u69cb\u65b9\u5411\uff08OpenUSD + Omniverse\uff09"}}]}
        },
        {
            "object": "block", "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "\u5efa\u7acb Q2 \u5c0e\u5165\u6642\u7a0b\u5171\u8b58"}}]}
        },
        {
            "object": "block", "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "\u5f37\u5316\u8207 AVEVA \u7684\u5dee\u7570\u5316\u5b9a\u4f4d"}}]}
        },
        {
            "object": "block", "type": "heading_2",
            "heading_2": {"rich_text": [{"type": "text", "text": {"content": "\ud83d\udc65 Attendees"}}]}
        },
        {
            "object": "block", "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "Kevin Chen - VP Manufacturing, UMC"}}]}
        },
        {
            "object": "block", "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "Lisa Wang - IT Director, UMC"}}]}
        },
        {
            "object": "block", "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "Michael Lin - CEO, Reality Matrix"}}]}
        },
        {
            "object": "block", "type": "heading_2",
            "heading_2": {"rich_text": [{"type": "text", "text": {"content": "\ud83d\ude4b\u200d\u2642\ufe0f \u6211\u65b9\u60f3\u554f\u7684\u554f\u984c (My Questions)"}}]}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "UMC \u76ee\u524d\u7684 OEE \u76e3\u63a7\u65b9\u5f0f\u662f\u4ec0\u9ebc\uff1f\uff08\u4e86\u89e3\u75db\u9ede\uff09"}}], "checked": false}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "Q2 \u5c0e\u5165\u6642\u7a0b\u6709\u6c92\u6709\u786c\u6027 deadline\uff1f\uff08\u78ba\u8a8d\u7dca\u8feb\u5ea6\uff09"}}], "checked": false}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "IT \u90e8\u9580\u5c0d\u96f2\u7aef\u90e8\u7f72\u7684\u614b\u5ea6\uff1f\uff08\u8a55\u4f30 on-premise \u9700\u6c42\uff09"}}], "checked": false}
        },
        {
            "object": "block", "type": "heading_2",
            "heading_2": {"rich_text": [{"type": "text", "text": {"content": "\u2753 \u5c0d\u65b9\u53ef\u80fd\u554f\u7684\u554f\u984c (Their Questions)"}}]}
        },
        {
            "object": "block", "type": "toggle",
            "toggle": {"rich_text": [{"type": "text", "text": {"content": "ROI \u600e\u9ebc\u7b97\uff1f\u6295\u8cc7\u56de\u6536\u671f\u591a\u4e45\uff1f"}}]}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "\u2192 \u55ae\u7dda $450K/yr \u7bc0\u7701\uff0c4 \u500b\u6708\u56de\u6536\u3002TSMC CoWoS \u6848\u4f8b OEE +2.1%"}}]}
        },
        {
            "object": "block", "type": "toggle",
            "toggle": {"rich_text": [{"type": "text", "text": {"content": "\u8ddf AVEVA \u6709\u4ec0\u9ebc\u4e0d\u540c\uff1f"}}]}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "\u2192 IDTF \u958b\u6e90\u67b6\u69cb\uff0c\u7121 vendor lock-in\u3002\u652f\u63f4 OpenUSD\uff0c\u5c0e\u5165\u6210\u672c\u4f4e 60%"}}]}
        },
        {
            "object": "block", "type": "toggle",
            "toggle": {"rich_text": [{"type": "text", "text": {"content": "\u8cc7\u5b89\u5408\u898f\u600e\u9ebc\u8655\u7406\uff1f"}}]}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "\u2192 ISO 27001 + SEMI E187\u3002\u53f0\u7063 GCP \u6a5f\u623f\uff0c\u8cc7\u6599\u4e0d\u51fa\u5883"}}]}
        },
        {
            "object": "block", "type": "toggle",
            "toggle": {"rich_text": [{"type": "text", "text": {"content": "PoC \u7bc4\u570d\u548c\u6642\u7a0b\uff1f"}}]}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "\u2192 \u55ae\u7dda\u5148\u884c\uff0c3 \u500b\u6708 PoC\u30021\u6708\u555f\u52d5 \u2192 3\u6708\u4ea4\u4ed8 \u2192 Q2 Pilot"}}]}
        },
        {
            "object": "block", "type": "toggle",
            "toggle": {"rich_text": [{"type": "text", "text": {"content": "\u5718\u968a\u898f\u6a21\uff1f\u80fd\u652f\u6491\u591a\u5927\u7684\u5c0e\u5165\uff1f"}}]}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "\u2192 \u6838\u5fc3 8 \u4eba + \u5408\u4f5c\u5925\u4f34\u3002\u5df2\u670d\u52d9 TSMC\u3001\u806f\u96fb\u7b49\u5927\u578b\u5c0e\u5165"}}]}
        },
        {
            "object": "block", "type": "toggle",
            "toggle": {"rich_text": [{"type": "text", "text": {"content": "\u5b9a\u50f9\u6a21\u5f0f\uff1f"}}]}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "\u2192 PoC $120K\uff08\u542b\u786c\u9ad4+\u8edf\u9ad4+\u5c0e\u5165\uff09\u3002\u6b63\u5f0f\u5c0e\u5165\u6309\u7dda\u6578\u8a08\u50f9"}}]}
        },
        {
            "object": "block", "type": "heading_2",
            "heading_2": {"rich_text": [{"type": "text", "text": {"content": "\ud83d\udccb Talking Points"}}]}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "[MUST] ROI \u9810\u4f30\u8207\u56de\u6536\u6642\u7a0b \u2014 \u55ae\u7dda $450K/yr\uff0c4 \u500b\u6708\u56de\u6536"}}], "checked": false}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "[MUST] \u8cc7\u5b89\u5408\u898f\u65b9\u6848 \u2014 ISO 27001 + SEMI E187 + \u53f0\u7063 GCP"}}], "checked": false}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "[SHOULD] Q1 \u5c0e\u5165\u6642\u7a0b\u78ba\u8a8d \u2014 1\u6708\u555f\u52d5 \u2192 3\u6708 PoC \u2192 Q2 Pilot"}}], "checked": false}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "[SHOULD] TSMC \u5148\u9032\u5c01\u88dd\u6210\u529f\u6848\u4f8b \u2014 CoWoS OEE +2.1%"}}], "checked": false}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "[NICE] OpenUSD \u6280\u8853\u512a\u52e2 \u2014 NVIDIA Omniverse \u539f\u751f\u652f\u63f4"}}], "checked": false}
        },
        {
            "object": "block", "type": "to_do",
            "to_do": {"rich_text": [{"type": "text", "text": {"content": "[NICE] \u8207 AVEVA \u5dee\u7570\u5316 \u2014 \u958b\u6e90 vs \u5c01\u9589\uff0c\u6210\u672c\u4f4e 60%"}}], "checked": false}
        },
        {
            "object": "block", "type": "heading_2",
            "heading_2": {"rich_text": [{"type": "text", "text": {"content": "\ud83d\udcca Pre-Analysis"}}]}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "UMC 2025 Q4 \u8ca1\u5831\u986f\u793a\u5148\u9032\u88fd\u7a0b\u7522\u80fd\u5229\u7528\u7387 92%\uff0cDigital Twin \u53ef\u63d0\u5347\u81f3 94-95%\u3002Kevin \u904e\u53bb\u5c0d AVEVA \u7684\u5c0e\u5165\u7d93\u9a57\u4e0d\u4f73\uff08\u8d85\u6642\u8d85\u9810\u7b97\uff09\uff0c\u5c0d\u65b0\u5ee0\u5546\u6301\u8b39\u614e\u614b\u5ea6\u3002\u5efa\u8b70\u7b56\u7565\uff1a\u5f37\u8abf\u300c\u5c0f\u898f\u6a21\u5148\u884c\u300d\u548c\u300c\u7121\u98a8\u96aa\u8a66\u7528\u300d\u964d\u4f4e\u6c7a\u7b56\u9580\u6abb\u3002"}}]}
        },
        {
            "object": "block", "type": "divider", "divider": {}
        },
        {
            "object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "Generated by MeetingCopilot v4.3 \u00a9 Reality Matrix Inc."}, "annotations": {"italic": true, "color": "gray"}}]}
        }
    ]
}
JSONEOF
)" | sed "s/PARENT_PLACEHOLDER/$PARENT_ID/g")

# 解析結果
PAGE_URL=$(echo "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'url' in data:
    print(data['url'])
elif 'message' in data:
    print('ERROR: ' + data['message'])
else:
    print('ERROR: Unknown response')
" 2>/dev/null || echo "ERROR: Failed to parse response")

if [[ "$PAGE_URL" == ERROR* ]]; then
    echo "❌ $PAGE_URL"
    echo "原始回應:"
    echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"
    exit 1
fi

PAGE_ID=$(echo "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('id', 'unknown'))
" 2>/dev/null || echo "unknown")

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ Notion 範例頁面建立成功！"
echo "════════════════════════════════════════════════════════"
echo ""
echo "📝 頁面標題: PreMeeting: Michael's QBR 11 Mar 2026"
echo "🔗 URL: $PAGE_URL"
echo "🆔 Page ID: $PAGE_ID"
echo ""
echo "→ 請將此 Page ID 貼到 TXT 檔案的 [SOURCES] 區塊:"
echo "  notion_page_id=$PAGE_ID"
echo ""
