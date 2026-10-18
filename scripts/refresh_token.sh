#!/usr/bin/env bash
# Threads の長期トークンを更新する。60日放置すると恒久的に失効するため週1で必ず走らせる。
# 新しいトークンは標準出力に出さない。GitHub Secret への反映は gh CLI 経由で行う。
set -euo pipefail
: "${THREADS_ACCESS_TOKEN:?}"
RES=$(curl -sS -G "https://graph.threads.net/refresh_access_token" \
  --data-urlencode "grant_type=th_refresh_token" \
  --data-urlencode "access_token=${THREADS_ACCESS_TOKEN}")
NEW=$(printf '%s' "$RES" | jq -r '.access_token // empty')
EXP=$(printf '%s' "$RES" | jq -r '.expires_in // empty')
if [ -z "$NEW" ]; then echo "::error::更新に失敗: ${RES}"; exit 1; fi
echo "更新成功。残り有効期間: $((EXP / 86400)) 日"
if command -v gh >/dev/null 2>&1; then
  printf '%s' "$NEW" | gh secret set THREADS_ACCESS_TOKEN
  echo "GitHub Secret を更新した"
else
  echo "::warning::gh が無いため Secret を自動更新できない。手で差し替えること"
fi
