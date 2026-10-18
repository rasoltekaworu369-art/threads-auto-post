#!/usr/bin/env bash
# 24時間以上経った投稿の insights を取得し reaction-log.csv に追記する。
set -euo pipefail
: "${THREADS_USER_ID:?}" "${THREADS_ACCESS_TOKEN:?}"
# 公式ドキュメントは graph.threads.com へ移行中。graph.threads.net も現時点では同じ応答を返す。
# 片方が落ちたら THREADS_HOST を切り替えるだけで直るようにしてある。
HOST="${THREADS_HOST:-graph.threads.com}"
API="https://${HOST}/v1.0"
AUTH="Authorization: Bearer ${THREADS_ACCESS_TOKEN}"
TARGET="${1:-$(TZ=Asia/Tokyo date -d yesterday +%F)}"
P="posted/${TARGET}.json"
[ -f "$P" ] || { echo "対象日の記録が無い: ${P}"; exit 0; }
Q="queue/${TARGET}.json"

jq -r '.posted[] | select(.status=="published") | "\(.index) \(.media_id)"' "$P" |
while read -r IDX MID; do
  M=$(curl -sS -G "${API}/${MID}/insights" -H "$AUTH" \
    --data-urlencode "metric=views,likes,replies,reposts,quotes")
  get() { printf '%s' "$M" | jq -r --arg n "$1" '(.data[]? | select(.name==$n) | (.values[0].value // .total_value.value)) // 0'; }
  if [ -f "$Q" ]; then
    meta=$(jq -r --argjson i "$IDX" '.posts[$i] | "\(.テーマ // "")|\(.構成型 // "")|\(.開幕型 // "")|\(.締め型 // "")|\(.slot // "")"' "$Q")
  else meta="||||"; fi
  IFS='|' read -r THEME KOU KAI SHIME SLOT <<< "$meta"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,\n' \
    "$TARGET" "$SLOT" "$MID" "$THEME" "$KOU" "$KAI" "$SHIME" \
    "$(get views)" "$(get likes)" "$(get replies)" "$(get reposts)" "$(get quotes)" \
    >> reaction-log.csv
done

# clicks はアカウント単位でしか取れないため、日次の合計を別行で記録する
U=$(curl -sS -G "${API}/${THREADS_USER_ID}/threads_insights" -H "$AUTH" \
  --data-urlencode "metric=clicks,followers_count")
CLICKS=$(printf '%s' "$U" | jq -r '(.data[]? | select(.name=="clicks") | .total_value.value) // 0')
printf '%s,DAILY,,,,,,,,,,,%s\n' "$TARGET" "$CLICKS" >> reaction-log.csv
echo "追記完了: ${TARGET}(clicks合計=${CLICKS})"
