#!/usr/bin/env bash
# Threads の長期トークンを週1で面倒を見る。
#
# 🔴 安全設計（2026-10-18）：
#   refresh_access_token は新しいトークンを返す。それが古いトークンを無効化する仕様かは未確認。
#   もし無効化するなら、「更新したが保存できなかった」が起きた瞬間に仕組みが止まる。
#   だから **保存できる状態でなければ、更新そのものを行わない。**
#
#   GH_TOKEN あり（secrets:write の PAT を置いた）→ 更新して Secrets に保存する
#   GH_TOKEN なし                                  → 更新せず、トークンの生存確認だけして報告する
#
# 新しいトークンは標準出力に出さない。
set -euo pipefail
: "${THREADS_ACCESS_TOKEN:?}"
HOST="${THREADS_HOST:-graph.threads.com}"

if [ -z "${GH_TOKEN:-}" ]; then
  echo "GH_PAT_FOR_SECRETS が未設定のため、更新は行わない（保存できない更新は危険なので実行しない）。"
  echo "代わりにトークンの生存確認を行う。"
  RES=$(curl -sS -G "https://${HOST}/v1.0/me" --data-urlencode "fields=id,username" \
    -H "Authorization: Bearer ${THREADS_ACCESS_TOKEN}")
  if printf '%s' "$RES" | grep -q '"id"'; then
    echo "✅ トークンは有効。アカウント: $(printf '%s' "$RES" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')"
    echo "::warning::自動更新は無効。ダッシュボードの生成ツールで手動更新すること（発行から50日以内）"
    exit 0
  fi
  echo "::error::🔴 トークンが無効になっている。ダッシュボードの生成ツールで取り直して Secrets を更新すること"
  echo "応答: ${RES}"
  exit 1
fi

echo "GH_TOKEN あり。更新して Secrets に保存する。"
RES=$(curl -sS -G "https://${HOST}/refresh_access_token" \
  --data-urlencode "grant_type=th_refresh_token" \
  --data-urlencode "access_token=${THREADS_ACCESS_TOKEN}")
NEW=$(printf '%s' "$RES" | jq -r '.access_token // empty')
EXP=$(printf '%s' "$RES" | jq -r '.expires_in // empty')
if [ -z "$NEW" ]; then
  echo "::error::更新に失敗した: ${RES}"
  exit 1
fi
echo "更新成功。残り有効期間: $((EXP / 86400)) 日"

if ! command -v gh >/dev/null 2>&1; then
  echo "::error::gh が見つからない。新しいトークンを保存できなかった"
  echo "::error::🔴 古いトークンが無効化されている可能性がある。ダッシュボードで取り直すこと"
  exit 1
fi

printf '%s' "$NEW" | gh secret set THREADS_ACCESS_TOKEN --repo "${GITHUB_REPOSITORY}"
echo "✅ GitHub Secret を更新した"
