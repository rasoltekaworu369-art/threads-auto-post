#!/usr/bin/env bash
# 本日のキューから「まだ投稿していない次の1本」を Threads に公開する。
#
# 🔴 ツリー投稿が標準（2026-10-18 ボス指示。単発では反応が出なかった実績による）
#   posts[i].tree = 文字列の配列。[0] が親投稿（1文のみ）、[1..] がセルフリプで1本に伸ばす
#   posts[i].text = 旧形式（単発）。tree が無いときのフォールバック
#
# 遅延や取りこぼしに強い設計：時刻ではなく posted/ の件数で次を決める。
set -euo pipefail
: "${THREADS_USER_ID:?THREADS_USER_ID が未設定}"
: "${THREADS_ACCESS_TOKEN:?THREADS_ACCESS_TOKEN が未設定}"

# 公式ドキュメントは graph.threads.com へ移行中。graph.threads.net も現時点では同じ応答を返す。
# 片方が落ちたら THREADS_HOST を切り替えるだけで直るようにしてある。
HOST="${THREADS_HOST:-graph.threads.com}"
API="https://${HOST}/v1.0"
AUTH="Authorization: Bearer ${THREADS_ACCESS_TOKEN}"
TODAY="$(TZ=Asia/Tokyo date +%F)"
Q="queue/${TODAY}.json"
P="posted/${TODAY}.json"

if [ ! -f "$Q" ]; then
  echo "::warning::キューが無い: ${Q}（Routine A が前夜に作る）"
  exit 0
fi
[ -f "$P" ] || printf '{"date":"%s","posted":[]}\n' "$TODAY" > "$P"

DONE=$(jq '.posted | length' "$P")
TOTAL=$(jq '.posts | length' "$Q")
if [ "$DONE" -ge "$TOTAL" ]; then
  echo "本日分は投稿済み (${DONE}/${TOTAL})"
  exit 0
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

# ボスが朝のゲートで消した本は、親を SKIP に書き換えればツリーごと飛ばす
FIRST="$(decode "${PARTS[0]}")"
if [ "$(printf '%s' "$FIRST" | tr -d '[:space:]')" = "SKIP" ]; then
  echo "SKIP 指定。投稿せず記録だけ進める"
  jq --argjson i "$DONE" '.posted += [{"index":$i,"status":"skipped"}]' "$P" > "$P.tmp" && mv "$P.tmp" "$P"
  exit 0
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
    create=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads" -H "$AUTH" \
      --data-urlencode "media_type=TEXT" \
      --data-urlencode "text=${text}")
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
   '.posted += [{"index":$i,"root_media_id":($ids[0]),"media_ids":$ids,"posted_at":$at,"status":"published"}]' \
   "$P" > "$P.tmp" && mv "$P.tmp" "$P"

echo "ツリー ${#IDS[@]} 本を公開した（親: ${IDS[0]}）"
