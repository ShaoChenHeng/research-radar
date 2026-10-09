#!/usr/bin/env bash
# Research Radar 桌面通知。
# 用法: notify.sh "<标题>" ["<正文>"] [--persistent]
#   --persistent → 紧急级 + 不超时（KDE 下"点掉才消失"，类似 macOS 常驻）
set -u
title="${1:-Research Radar}"
body="${2:-}"
extra=()
[ "${3:-}" = "--persistent" ] && extra=(-u critical -t 0)

if command -v notify-send >/dev/null 2>&1; then
  if [ "${#extra[@]}" -gt 0 ]; then
    notify-send -a "Research Radar" -i dialog-information -u critical -t 0 "$title" "$body" 2>/dev/null && exit 0
  fi
  notify-send -a "Research Radar" -i dialog-information "$title" "$body" 2>/dev/null && exit 0
fi
if command -v kdialog >/dev/null 2>&1; then
  kdialog --title "$title" --passivepopup "$body" 10 2>/dev/null && exit 0
fi
echo "[radar] (无法弹出通知) $title${body:+ :: $body}" >&2
exit 0
