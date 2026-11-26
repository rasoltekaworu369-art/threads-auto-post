#!/usr/bin/env bash
# アカウントごとの置き場を決める【唯一の場所】。各スクリプトはこれを source する。
#
# 🔴 人間向けの正本は `参照/アカウント対応表.md`。このファイルはその機械読み版。
#    片方だけ直すと必ずズレる。両方同時に直すこと。
#
# 🔴 設計の要点（2026-10-30 晴明）：
#    ACCT を省略すると spi になり、PFX が空文字になる。
#    つまり【スピの挙動は1バイトも変わらない】。既存の配線を壊さないための形。
#
# 使い方:
#   . "$(dirname "$0")/acct_env.sh"
#   → ACCT / PFX / GENRE / QUEUE_DIR / POSTED_DIR / RLOG / CONCEPT / IMPROVE /
#     LIMIT_FILE / RECENT / MIHON / ORIGIN / INV / MANU_DIR / REPLIES / UID_ENV が入る

ACCT="${ACCT:-spi}"

case "$ACCT" in
  spi)
    PFX=""
    GENRE="スピ"
    MIHON="参照/お手本_Threads_スピ.md"
    ORIGIN="参照/オリジン在庫_スピ.md"
    INV="参照/言い換え在庫_スピ.md"
    MANU_DIR="参照/ボス原稿"
    REPLIES="参照/読者の声_返信.jsonl"
    RECENT="参照/型カタログ_Threads版.md"   # スピは禁止節をカタログ末尾に置いている（既存のまま）
    DEFAULT_TOPIC="スピリチュアル"          # 🆕 2026-11-26 親投稿に付けるトピックタグ（queue の topic_tag が無いとき）
    ;;
  renai)
    PFX="renai/"
    GENRE="恋愛"
    MIHON="参照/お手本_Threads_恋愛.md"
    ORIGIN="参照/オリジン在庫_恋愛.md"
    INV="参照/言い換え在庫_恋愛.md"
    MANU_DIR="参照/ボス原稿_恋愛"
    REPLIES="参照/読者の声_返信_恋愛.jsonl"
    RECENT="renai/直近の型.md"
    DEFAULT_TOPIC="恋愛"
    ;;
  *)
    echo "::error::未知のアカウント: ${ACCT}（参照/アカウント対応表.md を見ること）" >&2
    exit 1
    ;;
esac

QUEUE_DIR="${PFX}queue"
POSTED_DIR="${PFX}posted"
RLOG="${PFX}reaction-log.csv"
CONCEPT="${PFX}concept.md"
IMPROVE="${PFX}improve.md"
LIMIT_FILE="${PFX}本数.txt"

# 🔴 未有効化のアカウントは、黙って飛ばしてよい（ALLOW_DORMANT=1 のときだけ）。
#    スピは今までどおり大声で落ちる。Secret が消えたのを見逃すほうが危険だから。
acct_require_token() {
  if [ -z "${THREADS_ACCESS_TOKEN:-}" ]; then
    if [ -n "${ALLOW_DORMANT:-}" ]; then
      echo "⏸ ${ACCT}（${GENRE}）は未有効化。Secret が登録されるまで何もしない。"
      exit 0
    fi
    echo "::error::THREADS_ACCESS_TOKEN が未設定（ACCT=${ACCT}）" >&2
    exit 1
  fi
}

# 1日の本数の栓。ファイルが無ければ 9。
# 🔴 ボスが本数を落としたいときは、この数字を書き換えるだけでよい（コードは触らない）。
acct_daily_limit() {
  local n=9
  if [ -f "$LIMIT_FILE" ]; then
    # 🔴 1行目だけを読む。全文を tr に流すとコメント中の数字まで拾う（2026-10-30 自己検査で発覚）
    n="$(head -1 "$LIMIT_FILE" | tr -dc '0-9')"
    [ -n "$n" ] || n=9
  fi
  printf '%s' "$n"
}
