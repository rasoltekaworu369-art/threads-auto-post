#!/usr/bin/env bash
# 常駐ループ（2026-11-21 新設）。1回の起動で最長 LOOP_MINUTES 分とどまり、
# 2分おきに spi → renai の順で post_next.sh を呼ぶ。投稿したらその場でコミットして push する。
#
# なぜ常駐か：GitHub の定時実行は 11/18 以降 1日4〜6回しか起動しなくなった（設定は36回）。
#   起動を「投稿の瞬間」に合わせる設計では、何本出るかが GitHub の気分で決まってしまう。
#   常駐すれば、起動が1日に数回あるだけで 9枠すべてを予定時刻（各枠 00〜30分）に出せる。
#
# 終わる前に自分の後継を workflow_dispatch で起動する（GITHUB_TOKEN でも dispatch は起動できる）。
# → 定時実行が落ちても、06:00〜24:00 のあいだは途切れずに見張り続ける。cron は予備。
#
# 必要な環境変数:
#   THREADS_USER_ID_SPI / THREADS_ACCESS_TOKEN_SPI / THREADS_USER_ID_RENAI / THREADS_ACCESS_TOKEN_RENAI
#   GH_TOKEN（後継の起動用。無ければ後継は起動せず cron に任せる）
set -uo pipefail
cd "$(dirname "$0")/.."

LOOP_MINUTES="${LOOP_MINUTES:-330}"
INTERVAL_SEC="${INTERVAL_SEC:-120}"
END=$(( $(date +%s) + LOOP_MINUTES * 60 ))

git config user.name  "threads-bot"
git config user.email "threads-bot@users.noreply.github.com"

commit_push() {
  local acct="$1"
  git add posted/ renai/posted/ 2>/dev/null || true
  git diff --staged --quiet && return 0
  git commit -q -m "記録: ${acct} $(TZ=Asia/Tokyo date +'%F %H:%M') の投稿"
  for i in 1 2 3 4 5; do
    git pull -q --rebase origin main && git push -q origin HEAD:main && return 0
    sleep $(( i * 5 ))
  done
  echo "::error::push に5回失敗した（${acct}）"
}

run_acct() {
  local acct="$1" uid="$2" tok="$3" dormant="$4"
  ACCT="$acct" ALLOW_DORMANT="$dormant" THREADS_USER_ID="$uid" THREADS_ACCESS_TOKEN="$tok" \
    bash scripts/post_next.sh 2>&1 | sed "s/^/[${acct}] /"
  commit_push "$acct"
}

while :; do
  H=$((10#$(TZ=Asia/Tokyo date +%H)))
  # 予定の取り込み（Routine が queue を push した場合に備える）
  git pull -q --rebase origin main || true
  run_acct spi   "${THREADS_USER_ID_SPI:-}"   "${THREADS_ACCESS_TOKEN_SPI:-}"   ""
  run_acct renai "${THREADS_USER_ID_RENAI:-}" "${THREADS_ACCESS_TOKEN_RENAI:-}" "1"

  NOW=$(date +%s)
  [ "$NOW" -ge "$END" ] && break
  # 23時台の最後の確認が済んだら、その日の仕事は終わり（翌朝は cron が起こす）
  if [ "$H" -eq 23 ] && [ "$(TZ=Asia/Tokyo date +%M)" -ge 50 ]; then
    echo "23:50 を過ぎた。今日の見張りを終える"; exit 0
  fi
  sleep "$INTERVAL_SEC"
done

# 後継を起動（06:00〜23:00 の間に終わったときだけ。夜中は cron が朝に起こす）
H=$((10#$(TZ=Asia/Tokyo date +%H)))
if [ "$H" -ge 5 ] && [ "$H" -le 22 ] && [ -n "${GH_TOKEN:-}" ]; then
  echo "持ち時間が尽きた。後継の常駐を起動する"
  gh workflow run post.yml --ref main || echo "::warning::後継の起動に失敗。cron に任せる"
fi
