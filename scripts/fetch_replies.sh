#!/usr/bin/env bash
# 自分の投稿についた【読者の返信】を集めて 参照/読者の声_返信.jsonl に追記する。
#
# 🔴 なぜ要るのか（2026-10-21）
#   言い換え在庫が10/21の生成で枯れた。ボスの原稿だけを出典にすると、いずれまた枯れる。
#   読者が自分の言葉で書いた悩み・内心は毎日増える出典になる。
#   （購入者コメント「結果がでたときが一番何もしていないとき」が最強のフックだったのと同じ種類のもの）
#   → 使い道は「1本目のセルフリプの内心描写と語彙」だけ。機序の言い方には使わない（手順書 ③-c）
#
# 🔴 必要な権限: threads_read_replies（2026-10-21 時点のトークンには無い。OAuth のやり直しが要る）
#    権限が無いあいだは何も書かずに警告だけ出して終わる（計測を巻き込んで落とさないため）。
#
# 🔴 読者の username は保存しない。返信の本文・日時・どの投稿への返信かだけを残す。
set -euo pipefail
: "${THREADS_ACCESS_TOKEN:?}"
HOST="${THREADS_HOST:-graph.threads.com}"
API="https://${HOST}/v1.0"
AUTH="Authorization: Bearer ${THREADS_ACCESS_TOKEN}"
OUT="参照/読者の声_返信.jsonl"
DAYS="${1:-7}"   # 返信は投稿から数日かけて付くので、直近7日分の親を毎回見直す
touch "$OUT"

for d in $(seq 0 "$DAYS"); do
  P="posted/$(TZ=Asia/Tokyo date -d "-${d} day" +%F).json"
  [ -f "$P" ] || continue
  jq -r '.posted[] | select(.status=="published") | (.root_media_id // .media_id)' "$P"
done | sort -u |
while read -r ROOT; do
  URL="${API}/${ROOT}/conversation?fields=id,text,timestamp,is_reply_owned_by_me&reverse=false"
  while [ -n "$URL" ]; do
    R=$(curl -sS "$URL" -H "$AUTH")
    if printf %s "$R" | jq -e ".error" >/dev/null 2>&1; then
      MSG=$(printf %s "$R" | jq -r '"\(.error.code // "") \(.error.message // "")"')
      # code 10 / 200 番台 = 権限が無い（Graph API 共通）
      if printf %s "$MSG" | grep -qiE '^(10|2[0-9][0-9]) |permission|scope|threads_read_replies'; then
        echo "::warning::返信を読む権限が無い（threads_read_replies）。トークンを取り直すまで何もしない。" >&2
        exit 0
      fi
      echo "::error::返信の取得に失敗した（media ${ROOT}）。書かずに中止する。" >&2
      printf %s "$R" | head -c 400 >&2; echo >&2
      exit 3
    fi
    # 自分のセルフリプ（is_reply_owned_by_me=true）は読者の声ではないので落とす。既に記録した id も落とす
    printf %s "$R" | jq -c --arg root "$ROOT" '.data[]?
        | select((.is_reply_owned_by_me // false) | not) | select((.text // "") != "")
        | {id, root_media_id: $root, timestamp, text}' |
    while read -r L; do
      ID=$(printf %s "$L" | jq -r .id)
      grep -q "\"id\":\"${ID}\"" "$OUT" || printf '%s\n' "$L" >> "$OUT"
    done
    URL=$(printf %s "$R" | jq -r '.paging.next // ""')
  done
done
echo "読者の返信: $(wc -l < "$OUT") 件（累計）"
