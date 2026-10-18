#!/usr/bin/env bash
# 24時間以上経った投稿の insights を取得し reaction-log.csv に追記する。
#
# ツリー投稿に対応：1ツリーにつき各投稿を1行ずつ記録する。
#   tree_pos = 0 が親投稿、1以降がセルフリプ。
#   🔴 型の優劣を判定するときは tree_pos=0 の行だけを見る（親の数字がリーチそのもの）。
#      セルフリプの行は「どこまで読まれたか（読了率）」を見るために使う。
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

# 旧形式(media_id 単体)と新形式(media_ids 配列)の両方を扱う。
# 🔴 jq は日本語のフィールド名を .テーマ の形で読めない。必ず .["テーマ"] と書く。
#    2026-10-19 の初回実行がこれで失敗した（jq: try .["field"] instead of .field）。
# 🔴 time 列には「予定の枠」ではなく【実際に投稿した時刻】を入れる。
#    GitHub の定時実行は25分前後遅れるため、予定の枠では時間帯分析が成立しない。
jq -r '.posted[] | select(.status=="published")
       | .index as $i
       | ((.posted_at // "") | split(" ") | (.[1] // "")) as $at
       | (.media_ids // [.media_id])
       | to_entries[]
       | "\($i) \(.key) \(.value) \($at)"' "$P" |
while read -r IDX POS MID AT; do
  ACTUAL="${AT%:*}"   # HH:MM:SS -> HH:MM
  M=$(curl -sS -G "${API}/${MID}/insights" -H "$AUTH" \
    --data-urlencode "metric=views,likes,replies,reposts,quotes")
  get() { printf '%s' "$M" | jq -r --arg n "$1" '(.data[]? | select(.name==$n) | (.values[0].value // .total_value.value)) // 0'; }
  if [ -f "$Q" ]; then
    meta=$(jq -r --argjson i "$IDX" '.posts[$i] | "\(.["テーマ"] // "")|\(.["構成型"] // "")|\(.["開幕型"] // "")|\(.["締め型"] // "")|\(.slot // "")"' "$Q")
  else meta="||||"; fi
  IFS='|' read -r THEME KOU KAI SHIME SLOT <<< "$meta"
  # セルフリプの行には型を書かない（型は1ツリーに1つなので、親の行だけが持つ）
  if [ "$POS" -ne 0 ]; then THEME=""; KOU=""; KAI=""; SHIME=""; fi
  [ -n "$ACTUAL" ] || ACTUAL="$SLOT"   # 旧記録には posted_at が無いので枠で代用
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,\n' \
    "$TARGET" "$ACTUAL" "$MID" "$POS" "$THEME" "$KOU" "$KAI" "$SHIME" \
    "$(get views)" "$(get likes)" "$(get replies)" "$(get reposts)" "$(get quotes)" \
    >> reaction-log.csv
done

# clicks はアカウント単位でしか取れないため、日次の合計を別行で記録する
U=$(curl -sS -G "${API}/${THREADS_USER_ID}/threads_insights" -H "$AUTH" \
  --data-urlencode "metric=clicks,followers_count")
CLICKS=$(printf '%s' "$U" | jq -r '(.data[]? | select(.name=="clicks") | .total_value.value) // 0')
FOLLOWERS=$(printf '%s' "$U" | jq -r '(.data[]? | select(.name=="followers_count") | .total_value.value) // ""')
printf '%s,DAILY,,,,,,,,,,,,%s\n' "$TARGET" "$CLICKS" >> reaction-log.csv
echo "追記完了: ${TARGET}（clicks合計=${CLICKS} / フォロワー=${FOLLOWERS}）"
