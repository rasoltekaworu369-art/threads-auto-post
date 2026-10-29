#!/usr/bin/env bash
# 24時間以上経った投稿の insights を取得し reaction-log.csv に追記する。
#
# ツリー投稿に対応：1ツリーにつき各投稿を1行ずつ記録する。
#   tree_pos = 0 が親投稿、1以降がセルフリプ。
#   🔴 型の優劣を判定するときは tree_pos=0 の行だけを見る（親の数字がリーチそのもの）。
#      セルフリプの行は「どこまで読まれたか（読了率）」を見るために使う。
set -euo pipefail
. "$(dirname "$0")/acct_env.sh"
acct_require_token
: "${THREADS_USER_ID:?}"
echo "対象アカウント: ${ACCT}（${GENRE}）"
# 公式ドキュメントは graph.threads.com へ移行中。graph.threads.net も現時点では同じ応答を返す。
# 片方が落ちたら THREADS_HOST を切り替えるだけで直るようにしてある。
HOST="${THREADS_HOST:-graph.threads.com}"
API="https://${HOST}/v1.0"
AUTH="Authorization: Bearer ${THREADS_ACCESS_TOKEN}"
TARGET="${1:-$(TZ=Asia/Tokyo date -d yesterday +%F)}"
P="${POSTED_DIR}/${TARGET}.json"
[ -f "$P" ] || { echo "対象日の記録が無い: ${P}"; exit 0; }
Q="${QUEUE_DIR}/${TARGET}.json"
# 追記先が無ければ見出しだけ作る（新しいアカウントの初日）
[ -f "$RLOG" ] || printf 'date,time,media_id,tree_pos,テーマ,構成型,開幕型,締め型,views,likes,replies,reposts,quotes,clicks,followers\n' > "$RLOG"

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
  # 🔴 API が error を返したら「0」を書かずに即座に落ちる（2026-10-20 の事故）。
  #    この検査が無かったため、Meta が "API access blocked." を返していた 04:35 の実行が
  #    42行すべて views=0 の【偽のデータ】を書き込み、しかも success で終わった。
  #    数字が無いことより、嘘の数字が残ることのほうが有害である。
  if printf %s "$M" | jq -e ".error" >/dev/null 2>&1; then
    echo "::error::insights の取得に失敗した（media ${MID}）。0 を書かずに中止する。" >&2
    printf %s "$M" | head -c 400 >&2; echo >&2
    exit 3
  fi
  get() { printf '%s' "$M" | jq -r --arg n "$1" '(.data[]? | select(.name==$n) | (.values[0].value // .total_value.value)) // 0'; }
  if [ -f "$Q" ]; then
    meta=$(jq -r --argjson i "$IDX" '.posts[$i] | "\(.["テーマ"] // "")|\(.["構成型"] // "")|\(.["開幕型"] // "")|\(.["締め型"] // "")|\(.slot // "")"' "$Q")
  else meta="||||"; fi
  IFS='|' read -r THEME KOU KAI SHIME SLOT <<< "$meta"
  # セルフリプの行には型を書かない（型は1ツリーに1つなので、親の行だけが持つ）
  if [ "$POS" -ne 0 ]; then THEME=""; KOU=""; KAI=""; SHIME=""; fi
  [ -n "$ACTUAL" ] || ACTUAL="$SLOT"   # 旧記録には posted_at が無いので枠で代用
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,,\n' \
    "$TARGET" "$ACTUAL" "$MID" "$POS" "$THEME" "$KOU" "$KAI" "$SHIME" \
    "$(get views)" "$(get likes)" "$(get replies)" "$(get reposts)" "$(get quotes)" \
    >> "$RLOG"
done

# clicks はアカウント単位でしか取れないため、日次の合計を別行で記録する
U=$(curl -sS -G "${API}/${THREADS_USER_ID}/threads_insights" -H "$AUTH" \
  --data-urlencode "metric=clicks,followers_count")
# 🔴 こちらも同じ。error なら clicks=0 / followers="" を書かずに落ちる
if printf %s "$U" | jq -e ".error" >/dev/null 2>&1; then
  echo "::error::アカウント単位の insights の取得に失敗した。DAILY 行を書かずに中止する。" >&2
  printf %s "$U" | head -c 400 >&2; echo >&2
  exit 3
fi
CLICKS=$(printf '%s' "$U" | jq -r '(.data[]? | select(.name=="clicks") | .total_value.value) // 0')
FOLLOWERS=$(printf '%s' "$U" | jq -r '(.data[]? | select(.name=="followers_count") | .total_value.value) // ""')
# 🔴 2026-10-19 以降、投稿にURLを貼らない方針に変更したため clicks は構造上0になる。
#    列は消さない（0が並ぶこと自体が方針どおりに動いている証拠になる）。
#    代わりの主KPIは followers_count の日次の伸び（→ concept.md §6）。
printf '%s,DAILY,,,,,,,,,,,,%s,%s\n' "$TARGET" "$CLICKS" "$FOLLOWERS" >> "$RLOG"
echo "追記完了: ${TARGET}（clicks合計=${CLICKS} / フォロワー=${FOLLOWERS}）"
