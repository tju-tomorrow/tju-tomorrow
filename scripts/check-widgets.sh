#!/usr/bin/env bash
# 检查 GitHub Profile README 里用到的展示组件是否还活着。
#
# 用法:
#   bash scripts/check-widgets.sh              # 默认检查 tju-tomorrow
#   bash scripts/check-widgets.sh 别的用户名
#
# 为什么要这个脚本:
#   这些卡片大多是别人免费部署的服务，服务方额度用完就会突然挂掉，
#   而且挂的时候 README 上只会留下一片空白或一行文字，不会报错。
#   定期跑一下这个脚本，就知道是服务挂了还是自己的排版坏了。

set -uo pipefail

USER_NAME="${1:-tju-tomorrow}"
REPO="$USER_NAME/$USER_NAME"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# 检查一个链接：必须是 200，而且要返回真的图片（不是错误文案）
check() {
  local name="$1" url="$2"
  local out code ctype size
  out=$(curl -sL -o "$TMP/body" -w "%{http_code}|%{content_type}|%{size_download}" \
        --max-time 25 "$url" 2>/dev/null) || out="000||0"
  code="${out%%|*}"; out="${out#*|}"; ctype="${out%%|*}"; size="${out##*|}"

  local verdict
  case "$code" in
    200)
      if [ "${size:-0}" -lt 300 ]; then
        verdict="⚠️  返回内容过小"
      elif printf '%s' "$ctype" | grep -qiE 'svg|image'; then
        verdict="✅ 正常"
      else
        verdict="⚠️  返回的不是图片"
      fi
      ;;
    402) verdict="❌ 402 服务方停服（额度用完了）" ;;
    503) verdict="❌ 503 服务暂停" ;;
    404) verdict="❌ 404 地址不存在" ;;
    000) verdict="❌ 连不上" ;;
    *)   verdict="⚠️  状态 $code" ;;
  esac

  [ "$verdict" = "✅ 正常" ] || fail=1
  printf '  %-26s %s\n' "$name" "$verdict"
  [ "$verdict" != "✅ 正常" ] && printf '      %s\n' "$(head -c 90 "$TMP/body" | tr -d '\n')"
  return 0
}

echo "检查账号: $USER_NAME"
echo

echo "── 粉色统计卡（配色参数写错不会报错，只会静默失效，务必看渲染结果）──"
check "总览卡"      "https://github-readme-stats.vercel.app/api?username=$USER_NAME&show_icons=true&hide_border=true&border_radius=16&bg_color=45,2a1b3d,1a0f2e&title_color=ffb3d9&text_color=ffd6e8&icon_color=c084fc"
check "语言卡"      "https://github-readme-stats.vercel.app/api/top-langs/?username=$USER_NAME&layout=compact&hide_border=true&border_radius=16&bg_color=45,2a1b3d,1a0f2e&title_color=ffb3d9&text_color=ffd6e8&icon_color=c084fc"
check "连续提交卡"  "https://streak-stats.demolab.com?user=$USER_NAME&hide_border=true&border_radius=16&locale=zh&background=1A0F2E&stroke=C084FC&ring=FF8FAB&fire=FF5C8A&currStreakLabel=FF8FAB&currStreakNum=FFD6E8&sideNums=FFB3D9&sideLabels=FFD6E8&dates=C0A8D9"
echo

echo "── 装饰 / 徽章 ──"
check "打字动画"    "https://readme-typing-svg.demolab.com?font=Fira+Code&pause=1000&color=F73F89&center=true&vCenter=true&width=500&lines=Hi"
check "渐变横幅"    "https://capsule-render.vercel.app/api?type=waving&color=0:ffb6d5,100:ff5c8a&height=200&section=header&text=V&fontSize=44&fontColor=ffffff"
check "技能图标墙"  "https://skillicons.dev/icons?i=go,cpp,java,js,ts,react,vue,nodejs"
check "shields徽章" "https://img.shields.io/badge/test-ok-blue"
check "访客数"      "https://komarev.com/ghpvc/?username=$USER_NAME&color=ff8fab&style=flat-square"
echo

echo "── 自己仓库里生成的（最稳，第三方挂了也不影响）──"
check "贪吃蛇·浅色" "https://raw.githubusercontent.com/$REPO/output/snake.svg"
check "贪吃蛇·深色" "https://raw.githubusercontent.com/$REPO/output/snake-dark.svg"
echo

echo "── 已知已停服，留在这里是为了提醒别再往里加 ──"
# 这两个本来就该是坏的，不计入失败，也不会影响退出码
info_check() {
  local keep="$fail"
  check "$1" "$2"
  fail="$keep"
}
info_check "奖杯(已废)"      "https://github-profile-trophy.vercel.app/?username=$USER_NAME"
info_check "活跃度图(已废)"  "https://github-readme-activity-graph.vercel.app/graph?username=$USER_NAME"
echo

if [ "$fail" -eq 1 ]; then
  echo "⚠️  上面有项目异常。但先别慌，按这个顺序排查："
  echo "   1) 服务挂了  → 就是本脚本报出来的"
  echo "   2) 排版坏了  → 服务正常但页面不显示，多半是 HTML 标签后面漏了空行，整段被当纯文本"
  echo "   3) 只是没加载完 → 这些卡片有淡入动画，刚打开的一瞬间是空白的"
  exit 1
else
  echo "✅ 全部正常"
fi
