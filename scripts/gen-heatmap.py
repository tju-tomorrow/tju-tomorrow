#!/usr/bin/env python3
"""生成一张 GitHub 风格的贡献热力图（粉紫配色）。

读 GitHub GraphQL 的 contributionCalendar JSON，输出 SVG。
配色对齐 README 的「星愿紫粉」主题。
"""
import json
import sys
from datetime import date

# ── 配色（星愿紫粉）─────────────────────────────
BG = "#1a0f2e"          # 卡片底色
EMPTY = "#2b1b3d"       # 没贡献
RAMP = ["#2b1b3d", "#6b2d54", "#a8386b", "#e8548f", "#ffa8c8"]  # 逐级变亮
TEXT = "#ffd6e8"        # 正文
TITLE = "#ffb3d9"       # 标题/数字
DIM = "#c0a8d9"         # 次要文字

CW, CH, GAP = 11, 11, 3          # 格子宽高与间距
LEFT, TOP = 34, 34               # 左侧星期标签 / 顶部月份标签留白
PAD = 18

WEEKDAYS = ["", "一", "", "三", "", "五", ""]   # GitHub 只标这三个
MONTHS = ["1月", "2月", "3月", "4月", "5月", "6月",
          "7月", "8月", "9月", "10月", "11月", "12月"]


def level(count: int) -> int:
    """按 GitHub 的分档方式把贡献数映射到 0-4。"""
    if count <= 0:
        return 0
    if count <= 2:
        return 1
    if count <= 5:
        return 2
    if count <= 9:
        return 3
    return 4


def build(cal: dict) -> str:
    weeks = cal["weeks"]
    total = cal["totalContributions"]

    grid_w = len(weeks) * (CW + GAP)
    grid_h = 7 * (CH + GAP)
    width = LEFT + grid_w + PAD
    height = TOP + grid_h + 54

    p = []
    p.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" '
        f'font-family="Segoe UI, Ubuntu, PingFang SC, Helvetica Neue, sans-serif">'
    )
    p.append(f'<rect x="1" y="1" width="{width-2}" height="{height-2}" rx="16" '
             f'fill="{BG}" stroke="#5b3a6e" stroke-width="1"/>')

    # 月份标签：某周第一天所在的月变了就标一次
    last_month = None
    for i, w in enumerate(weeks):
        d = date.fromisoformat(w["contributionDays"][0]["date"])
        if d.month != last_month:
            if d.month in (1, 4, 7, 10):
                x = LEFT + i * (CW + GAP)
                p.append(f'<text x="{x}" y="{TOP - 10}" font-size="11" '
                         f'fill="{DIM}">{MONTHS[d.month-1]}</text>')
            last_month = d.month

    # 星期标签
    for row, name in enumerate(WEEKDAYS):
        if name:
            y = TOP + row * (CH + GAP) + CH - 1
            p.append(f'<text x="{PAD-6}" y="{y}" font-size="11" text-anchor="end" '
                     f'fill="{DIM}">{name}</text>')

    # 格子
    for i, w in enumerate(weeks):
        for row, day in enumerate(w["contributionDays"]):
            x = LEFT + i * (CW + GAP)
            y = TOP + row * (CH + GAP)
            p.append(f'<rect x="{x}" y="{y}" width="{CW}" height="{CH}" rx="2.5" '
                     f'fill="{RAMP[level(day["contributionCount"])]}"><title>'
                     f'{day["date"]}: {day["contributionCount"]} 次贡献</title></rect>')

    # 底部：总数 + 图例
    base_y = TOP + grid_h + 32
    p.append(f'<text x="{PAD}" y="{base_y}" font-size="15" font-weight="700" '
             f'fill="{TITLE}">{total:,} 次贡献</text>')
    p.append(f'<text x="{PAD + 108}" y="{base_y}" font-size="12" '
             f'fill="{DIM}">过去一年</text>')

    lx = width - PAD - 5 * (CW + GAP) - 26
    p.append(f'<text x="{lx - 6}" y="{base_y}" font-size="11" text-anchor="end" '
             f'fill="{DIM}">少</text>')
    for k, c in enumerate(RAMP):
        p.append(f'<rect x="{lx + k * (CW + GAP)}" y="{base_y - 11}" width="{CW}" '
                 f'height="{CH}" rx="2.5" fill="{c}"/>')
    p.append(f'<text x="{lx + 5 * (CW + GAP) + 2}" y="{base_y}" font-size="11" '
             f'fill="{DIM}">多</text>')

    p.append("</svg>")
    return "\n".join(p)


def fetch_calendar(user: str, token: str) -> dict:
    """用 GitHub GraphQL 拉过去一年的贡献日历。"""
    import urllib.request

    query = """
    query($login: String!) {
      user(login: $login) {
        contributionsCollection {
          contributionCalendar {
            totalContributions
            weeks { contributionDays { date contributionCount } }
          }
        }
      }
    }
    """
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=json.dumps({"query": query, "variables": {"login": user}}).encode(),
        headers={
            "Authorization": f"bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "heatmap-generator",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def extract_calendar(data: dict) -> dict:
    if "errors" in data:
        raise SystemExit(f"GitHub API 报错: {data['errors']}")
    return data["data"]["user"]["contributionsCollection"]["contributionCalendar"]


if __name__ == "__main__":
    import argparse
    import os

    ap = argparse.ArgumentParser(description="生成粉紫配色贡献热力图")
    ap.add_argument("input", nargs="?", default="-",
                    help="GraphQL 返回的 JSON 文件，默认从标准输入读")
    ap.add_argument("-o", "--output", default="heatmap.svg")
    ap.add_argument("--fetch", action="store_true",
                    help="自己调 GitHub API 拉数据（需要 GH_TOKEN 环境变量）")
    ap.add_argument("--user", default=os.environ.get("GITHUB_REPOSITORY_OWNER"),
                    help="用户名，默认取 GITHUB_REPOSITORY_OWNER")
    args = ap.parse_args()

    if args.fetch:
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if not token:
            raise SystemExit("缺少 GH_TOKEN 环境变量")
        if not args.user:
            raise SystemExit("缺少用户名（--user 或 GITHUB_REPOSITORY_OWNER）")
        cal = extract_calendar(fetch_calendar(args.user, token))
    else:
        raw = sys.stdin.read() if args.input == "-" else open(args.input, encoding="utf-8").read()
        cal = extract_calendar(json.loads(raw))

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(build(cal))
    print(f"已生成 {args.output}（总贡献 {cal['totalContributions']}）")
