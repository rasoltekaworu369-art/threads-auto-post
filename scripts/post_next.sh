#!/usr/bin/env bash
# 本日のキューから「まだ投稿していない次の1本」を Threads に公開する。
#
# 🔴 ツリー投稿が標準（2026-10-18 ボス指示。単発では反応が出なかった実績による）
#   posts[i].tree = 文字列の配列。[0] が親投稿（1文のみ）、[1..] がセルフリプで1本に伸ばす
#   posts[i].text = 旧形式（単発）。tree が無いときのフォールバック
#
# 遅延や取りこぼしに強い設計：時刻ではなく posted/ の件数で次を決める。
#
# 🔴 時刻の設計（2026-10-19 ボス指示「毎回07分なのが気になる。00〜30分のランダムな時刻にしてくれ」）
#   【実測】GitHub の定時実行は +25〜26分 遅れていた（13:07予定→13:33実行 / 11:07予定→11:31実行）。
#   つまり分を正確に指定することはできない。そこで設計をこう変えた：
#     ① cron を25分前倒しして、遅れを吸収した結果が JST の 00〜30分 に入るようにする
#     ② 1枠につき3回発火させて、遅れが小さい日の取りこぼしを防ぐ
#     ③ このスクリプトが「時刻の門」を持ち、00〜30分の外では投稿しない
#     ④ 同じ枠で二重投稿しないガードを持つ（3回発火するので必須）
#   結果、投稿される分は GitHub 側のばらつきで毎回変わる＝狙いどおり機械的に見えなくなる。
set -euo pipefail
. "$(dirname "$0")/acct_env.sh"
acct_require_token
: "${THREADS_USER_ID:?THREADS_USER_ID が未設定（ACCT='${ACCT}'）}"
echo "対象アカウント: ${ACCT}（${GENRE}）"

# ----- 時刻の門（2026-11-21 改訂：取りこぼしを後から埋める「追いつき方式」） --------
# 旧方式は「各枠の 00〜30分 に起動した回だけが投稿できる」だった。
# 【実測 11/13〜11/21】GitHub の定時実行は 36回/日 のうち 14〜20回 しか起動せず、
#   11/18 以降は 4〜6回/日 まで落ちた。しかも遅れが 40〜60分ある回が多く（10時・16時は毎日 :37〜:59 着）、
#   門の外に着地した回はすべて「見送り」になっていた → 1日1〜7本しか出ていなかった。
# 新方式：
#   ① 各枠の投稿予定時刻 = 枠の時 + 0〜30分（日付・枠・アカウントから決まる乱数。再起動しても同じ）
#   ② 予定時刻を過ぎた枠の数 > 投稿済み本数 なら、次の1本を出す（遅れて起動しても取りこぼさない）
#   ③ 直前の投稿から MIN_GAP_MIN 分（既定30分）空いていなければ待つ（追いつき時の連投を防ぐ）
#   ④ 06:00 より前は投稿しない。日付が変わったら前日分は追わない
JST_H="$(TZ=Asia/Tokyo date +%H)"
JST_M="$(TZ=Asia/Tokyo date +%M)"
SLOT_HOURS="06 08 10 12 14 16 18 20 22"
MIN_GAP_MIN="${MIN_GAP_MIN:-30}"
TODAY_EARLY="$(TZ=Asia/Tokyo date +%F)"

slot_offset() {   # 枠ごとの 0〜30分 のずらし（決定的な乱数）
  local h="$1"
  echo $(( $(printf '%s' "${TODAY_EARLY}-${h}-${ACCT}" | cksum | cut -d' ' -f1) % 31 ))
}

NOW_MIN=$(( 10#$JST_H * 60 + 10#$JST_M ))
DUE=0
NEXT_AT=""
for h in $SLOT_HOURS; do
  at=$(( 10#$h * 60 + $(slot_offset "$h") ))
  if [ "$NOW_MIN" -ge "$at" ]; then
    DUE=$((DUE + 1))
  elif [ -z "$NEXT_AT" ]; then
    NEXT_AT="$(printf '%02d:%02d' $((at / 60)) $((at % 60)))"
  fi
done

if [ -n "${FORCE_POST:-}" ]; then
  echo "FORCE_POST が指定された（手動実行）。時刻の門と間隔の門を飛ばす"
elif [ "$DUE" -eq 0 ]; then
  echo "まだ今日の最初の枠の予定時刻前（JST ${JST_H}:${JST_M}・次は ${NEXT_AT:-なし}）。何もしない"
  exit 0
else
  echo "JST ${JST_H}:${JST_M} 時点で予定時刻を過ぎた枠: ${DUE}本（次の予定 ${NEXT_AT:-本日分なし}）"
fi

# 公式ドキュメントは graph.threads.com へ移行中。graph.threads.net も現時点では同じ応答を返す。
# 片方が落ちたら THREADS_HOST を切り替えるだけで直るようにしてある。
HOST="${THREADS_HOST:-graph.threads.com}"
API="https://${HOST}/v1.0"
AUTH="Authorization: Bearer ${THREADS_ACCESS_TOKEN}"
TODAY="$(TZ=Asia/Tokyo date +%F)"
Q="${QUEUE_DIR}/${TODAY}.json"
P="${POSTED_DIR}/${TODAY}.json"
mkdir -p "$POSTED_DIR"

if [ ! -f "$Q" ]; then
  echo "::warning::キューが無い: ${Q}（Routine A が前夜に作る）"
  exit 0
fi
[ -f "$P" ] || printf '{"date":"%s","posted":[]}\n' "$TODAY" > "$P"

DONE=$(jq '.posted | length' "$P")
TOTAL=$(jq '.posts | length' "$Q")
# 🔴 本数の栓（2026-10-30）。ボスが本数を落としたいときは ${LIMIT_FILE} の数字を書き換えるだけ。
LIMIT="$(acct_daily_limit)"
if [ "$TOTAL" -gt "$LIMIT" ]; then
  echo "本数の栓: キュー ${TOTAL} 本のうち ${LIMIT} 本までに絞る（${LIMIT_FILE}）"
  TOTAL="$LIMIT"
fi
if [ "$DONE" -ge "$TOTAL" ]; then
  echo "本日分は投稿済み (${DONE}/${TOTAL})"
  exit 0
fi
if [ -z "${FORCE_POST:-}" ] && [ "$DONE" -ge "$DUE" ]; then
  echo "予定時刻を過ぎた枠はすべて投稿済み (${DONE}/${DUE})。次の予定 ${NEXT_AT:-なし}"
  exit 0
fi

# ----- 間隔の門（旧「同じ時台で二重投稿しない」ガードの置き換え） --------------
# 追いつきのときに連投しないよう、直前の公開から MIN_GAP_MIN 分は空ける。
LAST_AT="$(jq -r '[.posted[] | select(.posted_at != null) | .posted_at] | last // empty' "$P")"
if [ -z "${FORCE_POST:-}" ] && [ -n "$LAST_AT" ]; then
  GAP=$(( ( $(date +%s) - $(TZ=Asia/Tokyo date -d "$LAST_AT" +%s) ) / 60 ))
  if [ "$GAP" -lt "$MIN_GAP_MIN" ]; then
    echo "直前の投稿（${LAST_AT}）から ${GAP} 分。${MIN_GAP_MIN} 分空くまで待つ（遅れ ${DONE}/${DUE}）"
    exit 0
  fi
fi

# 残量確認。親投稿だけが 250本/24h を消費し、セルフリプは別枠（1,000件/24h）。
REMAIN=$(curl -sS -G "${API}/${THREADS_USER_ID}/threads_publishing_limit" \
  -H "$AUTH" --data-urlencode "fields=quota_usage" \
  | jq -r '.data[0].quota_usage // "unknown"' 2>/dev/null || echo "unknown")
echo "本日の API 投稿数（Meta側カウント）: ${REMAIN}"

# ツリーの各文を取り出す（tree が無ければ text を1要素の配列として扱う）
# 改行を含むので base64 で受け渡す
mapfile -t PARTS < <(jq -r --argjson i "$DONE" \
  '(.posts[$i].tree // [.posts[$i].text]) | .[] | @base64' "$Q")

if [ "${#PARTS[@]}" -eq 0 ]; then
  echo "::error::queue の ${DONE} 番目に tree も text も無い"; exit 1
fi

decode() { printf '%s' "$1" | base64 -d; }

# 🆕 2026-11-26 トピックタグ（Threads API の topic_tag。1投稿1つ・1〜50字・「.」「&」不可）
#   Meta 公式「タグ付きの投稿は一般により多く表示される」(2025-03)。フォロワーがほぼ0の今、
#   フォロワー外に届く入口がほぼこれしか無い。親投稿にだけ付ける（セルフリプには付けない）。
#   queue の posts[i].topic_tag があればそれ、無ければアカウントの既定（acct_env.sh の DEFAULT_TOPIC）。
TOPIC="$(jq -r --argjson i "$DONE" '.posts[$i].topic_tag // empty' "$Q")"
TOPIC="${TOPIC:-${DEFAULT_TOPIC:-}}"
TOPIC="$(printf '%s' "$TOPIC" | tr -d '.&#' | cut -c1-50)"

# ボスが朝のゲートで消した本は、親を SKIP に書き換えればツリーごと飛ばす
FIRST="$(decode "${PARTS[0]}")"
if [ "$(printf '%s' "$FIRST" | tr -d '[:space:]')" = "SKIP" ]; then
  echo "SKIP 指定。投稿せず記録だけ進める"
  jq --argjson i "$DONE" --arg h "$JST_H" \
    '.posted += [{"index":$i,"slot_hour":$h,"status":"skipped"}]' "$P" > "$P.tmp" && mv "$P.tmp" "$P"
  exit 0
fi

# 🔴 URLの門（2026-10-19 ボス指示：全面禁止に変更）
# 当初は「最後のセルフリプだけ許可」だったが、ボスの手動アカウントで
# シャドバン的な挙動が出たため【どの段であってもURL禁止】に切り替えた。
# 導線は「プロフィールの固定記事を見てください」の形（URLなし）で行う。
# 1段でもURLがあれば、そのツリーは投稿せずに落とす。
#   （リスクのある投稿を出すより、1枠捨てるほうが安い＝ボス裁定）
BAD_URL_AT=""
for idx in "${!PARTS[@]}"; do
  if printf '%s' "$(decode "${PARTS[$idx]}")" | grep -qiE 'https?://'; then
    BAD_URL_AT="${BAD_URL_AT}${BAD_URL_AT:+,}${idx}"
  fi
done
if [ -n "$BAD_URL_AT" ]; then
  echo "🔴 URL禁止違反（段 ${BAD_URL_AT}）。投稿にURLは一切入れられないため、このツリーは投稿しない。" >&2
  echo "   導線は「プロフィールの固定記事を見てください」の形で書くこと（参照/Routine_Aの読む順序.md）。" >&2
  jq --argjson i "$DONE" --arg h "$JST_H" --arg at "$BAD_URL_AT"     '.posted += [{"index":$i,"slot_hour":$h,"status":"blocked_url","違反の段":$at}]' "$P" > "$P.tmp" && mv "$P.tmp" "$P"
  git add "$P" >/dev/null 2>&1 || true
  exit 1
fi

# コンテナを作って公開する。
# 公式は「作成から公開まで平均30秒待つ」ことを推奨。テキストのみなら通常は即座に通るので、
# 短い待ちから始めて失敗したら伸ばす（固定で30秒待つより速く、かつ取りこぼさない）。
publish_one() {
  local text="$1" parent="${2:-}"
  local create cid pub mid attempt wait

  if [ -n "$parent" ]; then
    create=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads" -H "$AUTH" \
      --data-urlencode "media_type=TEXT" \
      --data-urlencode "text=${text}" \
      --data-urlencode "reply_to_id=${parent}")
  else
    if [ -n "${TOPIC:-}" ]; then
      create=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads" -H "$AUTH" \
        --data-urlencode "media_type=TEXT" \
        --data-urlencode "text=${text}" \
        --data-urlencode "topic_tag=${TOPIC}")
      # タグが原因で弾かれても枠を失わないよう、タグ無しで1回だけ作り直す
      if [ -z "$(printf '%s' "$create" | jq -r '.id // empty')" ]; then
        echo "::warning::topic_tag「${TOPIC}」付きの作成に失敗。タグ無しで作り直す: ${create}" >&2
        create=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads" -H "$AUTH" \
          --data-urlencode "media_type=TEXT" \
          --data-urlencode "text=${text}")
      fi
    else
      create=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads" -H "$AUTH" \
        --data-urlencode "media_type=TEXT" \
        --data-urlencode "text=${text}")
    fi
  fi
  cid=$(printf '%s' "$create" | jq -r '.id // empty')
  if [ -z "$cid" ]; then
    echo "::error::コンテナ作成に失敗: ${create}" >&2; return 1
  fi

  for attempt in 1 2 3 4 5; do
    if [ "$attempt" -eq 1 ]; then wait=5; else wait=15; fi
    sleep "$wait"
    pub=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads_publish" -H "$AUTH" \
      --data-urlencode "creation_id=${cid}")
    mid=$(printf '%s' "$pub" | jq -r '.id // empty')
    if [ -n "$mid" ]; then printf '%s' "$mid"; return 0; fi
    echo "::warning::公開 ${attempt} 回目が失敗（再試行する）: ${pub}" >&2
  done
  echo "::error::公開に5回失敗した" >&2; return 1
}

IDS=()
PARENT=""
for idx in "${!PARTS[@]}"; do
  TEXT="$(decode "${PARTS[$idx]}")"
  if [ -z "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ]; then
    echo "::warning::${idx} 番目が空。飛ばす"; continue
  fi

  if [ -z "$PARENT" ]; then
    echo "--- 親投稿を公開 ---"
    MID="$(publish_one "$TEXT")"
  else
    echo "--- ${idx} 番目をセルフリプで公開（返信先: ${PARENT}） ---"
    MID="$(publish_one "$TEXT" "$PARENT")"
  fi

  echo "公開成功 media_id=${MID}"
  IDS+=("$MID")
  PARENT="$MID"   # 次は「直前の投稿」に返信する＝ツリーが1本に伸びる
done

if [ "${#IDS[@]}" -eq 0 ]; then
  echo "::error::1本も公開できなかった"; exit 1
fi

IDS_JSON=$(printf '%s\n' "${IDS[@]}" | jq -R . | jq -cs .)
jq --argjson i "$DONE" \
   --argjson ids "$IDS_JSON" \
   --arg at "$(TZ=Asia/Tokyo date +'%F %T')" \
   --arg h "$JST_H" --arg tp "${TOPIC:-}" \
   '.posted += [{"index":$i,"slot_hour":$h,"root_media_id":($ids[0]),"media_ids":$ids,"posted_at":$at,"status":"published","topic_tag":$tp}]' \
   "$P" > "$P.tmp" && mv "$P.tmp" "$P"

echo "ツリー ${#IDS[@]} 本を公開した（親: ${IDS[0]}）"
