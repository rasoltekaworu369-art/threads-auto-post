#!/usr/bin/env bash
# 本日のキューから「まだ投稿していない次の1本」を Threads に公開する。
# 遅延や取りこぼしに強い設計:時刻ではなく posted/ の件数で次を決める。
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
  echo "::warning::キューが無い: ${Q}(Routine A が前夜に作る)"
  exit 0
fi
[ -f "$P" ] || printf '{"date":"%s","posted":[]}\n' "$TODAY" > "$P"

DONE=$(jq '.posted | length' "$P")
TOTAL=$(jq '.posts | length' "$Q")
if [ "$DONE" -ge "$TOTAL" ]; then
  echo "本日分は投稿済み (${DONE}/${TOTAL})"
  exit 0
fi

# 残量確認(250本/24h の上限に対して)
REMAIN=$(curl -sS -G "${API}/${THREADS_USER_ID}/threads_publishing_limit" \
  -H "$AUTH" --data-urlencode "fields=quota_usage,config" \
  | jq -r '.data[0].quota_usage // "unknown"')
echo "本日の API 投稿数(Meta側カウント): ${REMAIN}"

TEXT=$(jq -r ".posts[${DONE}].text" "$Q")
if [ -z "$TEXT" ] || [ "$TEXT" = "null" ]; then
  echo "::error::queue の ${DONE} 番目に text が無い"; exit 1
fi
# ボスが朝のゲートで消した本は skip 扱いにする(text を空にする運用)
if [ "$(printf '%s' "$TEXT" | tr -d '[:space:]')" = "SKIP" ]; then
  echo "SKIP 指定。投稿せず記録だけ進める"
  jq --argjson i "$DONE" '.posted += [{"index":$i,"status":"skipped"}]' "$P" > "$P.tmp" && mv "$P.tmp" "$P"
  exit 0
fi

# ① コンテナ作成
CREATE=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads" -H "$AUTH" \
  --data-urlencode "media_type=TEXT" --data-urlencode "text=${TEXT}")
CID=$(printf '%s' "$CREATE" | jq -r '.id // empty')
if [ -z "$CID" ]; then echo "::error::コンテナ作成に失敗: ${CREATE}"; exit 1; fi

sleep 5

# ② 公開
PUB=$(curl -sS -X POST "${API}/${THREADS_USER_ID}/threads_publish" -H "$AUTH" \
  --data-urlencode "creation_id=${CID}")
MID=$(printf '%s' "$PUB" | jq -r '.id // empty')
if [ -z "$MID" ]; then echo "::error::公開に失敗: ${PUB}"; exit 1; fi

echo "公開成功 media_id=${MID}"
jq --argjson i "$DONE" --arg mid "$MID" --arg at "$(TZ=Asia/Tokyo date +'%F %T')" \
  '.posted += [{"index":$i,"media_id":$mid,"posted_at":$at,"status":"published"}]' \
  "$P" > "$P.tmp" && mv "$P.tmp" "$P"
