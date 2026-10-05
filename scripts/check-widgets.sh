#!/usr/bin/env bash
# 检查 GitHub Profile README 里用到的展示组件是否还活着。
#
# 用法:
#   bash scripts/check-widgets.sh              # 默认检查 tju-tomorrow
#   bash scripts/check-widgets.sh 别的用户名
#
# 为什么要这个脚本:
#   1. 这些卡片大多是别人免费部署的服务，额度用完就会突然挂掉，
#      挂的时候 README 上只会留下一片空白或一行文字，不会报错。
#   2. 但「图片不显示」不等于「服务挂了」，也可能是你自己网络的问题。
#      本脚本会把这两种情况分开报，别再把网络抽风当成服务挂了。

set -uo pipefail

USER_NAME="${1:-tju-tomorrow}"
REPO="$USER_NAME/$USER_NAME"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bad=0       # 真的有问题（服务挂了 / 返回的不是图片）
unknown=0   # 本地网络问题，判断不了

# 把 curl 的错误码翻译成人话
explain_curl() {
  case "$1" in
    6)  echo "DNS 解析不出来 —— 多半是你本机网络/代理的问题，不是服务挂了" ;;
    7)  echo "连不上端口 —— 可能是代理或防火墙" ;;
    28) echo "请求超时" ;;
    35) echo "TLS 握手失败 —— 网络中间有东西在拦" ;;
    60) echo "TLS 证书校验失败 —— 你大概挂着一个代理（本机的，不是服务的）" ;;
    *)  echo "curl 错误码 $1 —— 本地网络问题" ;;
  esac
}

check() {
  local name="$1" url="$2"
  local body="$TMP/body" out rc code ctype size attempt

  : > "$body"                       # 先清空！否则会残留上一次的内容，误报成这次的证据
  for attempt in 1 2 3; do          # 网不稳，重试 3 次
    out=$(curl -sL -o "$body" -w "%{http_code}|%{content_type}|%{size_download}" \
          --max-time 25 "$url" 2>/dev/null)
    rc=$?
    [ "$rc" -eq 0 ] && break
    [ "$attempt" -lt 3 ] && sleep 2
  done

  if [ "$rc" -ne 0 ]; then
    unknown=$((unknown + 1))
    printf '  %-22s ⚠️  查不了: %s\n' "$name" "$(explain_curl "$rc")"
    return 0
  fi

  code="${out%%|*}"; out="${out#*|}"
  ctype="${out%%|*}"; size="${out##*|}"

  local verdict
  case "$code" in
    200)
      if [ "${size:-0}" -lt 300 ]; then
        verdict="⚠️  返回内容过小（可能是错误占位）"; bad=$((bad + 1))
      elif printf '%s' "$ctype" | grep -qiE 'svg|image'; then
        verdict="✅ 正常"
      else
        verdict="❌ 返回的不是图片"; bad=$((bad + 1))
      fi
      ;;
    402) verdict="❌ 402 服务方停服（免费额度用完了）"; bad=$((bad + 1)) ;;
    503) verdict="❌ 503 服务被暂停"; bad=$((bad + 1)) ;;
    404) verdict="❌ 404 地址不存在"; bad=$((bad + 1)) ;;
    *)   verdict="⚠️  HTTP $code"; bad=$((bad + 1)) ;;
  esac

  printf '  %-22s %s\n' "$name" "$verdict"
  if [ "$bad" -gt 0 ] && [ "${verdict:0:1}" != "✅" ]; then
    printf '      %s\n' "$(head -c 90 "$body" | tr -d '\n')"
  fi
  return 0
}

echo "检查账号: $USER_NAME"
echo

echo "── 粉色统计卡（配色参数写错不会报错，只会静默失效，务必看渲染结果）──"
check "总览卡"     "https://github-readme-stats.vercel.app/api?username=$USER_NAME&show_icons=true&hide_border=true&border_radius=16&bg_color=45,2a1b3d,1a0f2e&title_color=ffb3d9&text_color=ffd6e8&icon_color=c084fc"
check "语言卡"     "https://github-readme-stats.vercel.app/api/top-langs/?username=$USER_NAME&layout=compact&hide_border=true&border_radius=16&bg_color=45,2a1b3d,1a0f2e&title_color=ffb3d9&text_color=ffd6e8&icon_color=c084fc"
check "连续提交卡" "https://streak-stats.demolab.com?user=$USER_NAME&hide_border=true&border_radius=16&locale=zh&background=1A0F2E&stroke=C084FC&ring=FF8FAB&fire=FF5C8A&currStreakLabel=FF8FAB&currStreakNum=FFD6E8&sideNums=FFB3D9&sideLabels=FFD6E8&dates=C0A8D9"
echo

echo "── 装饰 / 徽章 ──"
check "打字动画"   "https://readme-typing-svg.demolab.com?font=Fira+Code&pause=1000&color=F73F89&center=true&vCenter=true&width=500&lines=Hi"
check "渐变横幅"   "https://capsule-render.vercel.app/api?type=waving&color=0:ffb6d5,100:ff5c8a&height=200&section=header&text=V&fontSize=44&fontColor=ffffff"
check "技能图标墙" "https://skillicons.dev/icons?i=go,cpp,java,js,ts,react,vue,nodejs"
check "shields徽章" "https://img.shields.io/badge/test-ok-blue"
check "访客数"     "https://komarev.com/ghpvc/?username=$USER_NAME&color=ff8fab&style=flat-square"
echo

echo "── 自己仓库里生成的（最稳，第三方挂了也不影响）──"
check "贡献热力图" "https://raw.githubusercontent.com/$REPO/output/heatmap.svg"
echo

echo "── 已知已停服，留在这里是为了提醒别再往里加 ──"
keep=$bad; check "奖杯(已废)"     "https://github-profile-trophy.vercel.app/?username=$USER_NAME"; bad=$keep
keep=$bad; check "活跃度图(已废)" "https://github-readme-activity-graph.vercel.app/graph?username=$USER_NAME"; bad=$keep
echo

if [ "$bad" -gt 0 ]; then
  echo "❌ 有 $bad 项真的有问题"
  [ "$unknown" -gt 0 ] && echo "   （另有 $unknown 项因为本地网络问题没能判断）"
  exit 1
fi

if [ "$unknown" -gt 0 ]; then
  echo "🤔 没有发现服务问题，但有 $unknown 项因为本地网络问题没能判断。"
  echo "   如果你确认代理/VPN 是好的，再跑一次；连续几次都查不了，才需要怀疑服务。"
  exit 0
fi

echo "✅ 全部正常。"
echo "   提醒：这里正常不代表页面上一定显示得出来。如果服务正常但图不显示，"
echo "   八成是 markdown 排版问题（比如 HTML 标签后面漏了空行，整段会被当纯文本）。"
