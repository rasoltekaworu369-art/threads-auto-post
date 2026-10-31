#!/usr/bin/env python3
# 読みやすさの門(2026-10-31 ボス指示)
#
# 🔴 なぜ要るのか
#   ボス「ツリー1投稿は"言い切り型"にして。です・ます調だと刺さらないし読まれない」
#   ボス「ツリー2投稿目以降は分量が多すぎて、文字が詰まっている感じがして読みづらい」
#   → 2026-10-31 の queue は、恋愛のセルフリプに改行が0個、1段140〜160字の塊だった。
#     スピも改行はあったが、1段140字超が並んで「詰まって」見えていた。
#   目で見た「読みやすい」は信用しない(cross_day_scan.py と同じ理屈)。機械で見る。
#
# 見るもの
#   親(tree[0]) : 改行なし / です・ます・か？で終わらない / 本文40字以内 / 読点2個まで
#                 恋愛だけ、言い切りの後ろに「それが、」のような橋渡しの短い切れ端を許す(ボスの固定投稿の実物)
#   セルフリプ  : 2〜4本 / 1段 60〜150字(改行を除く) / 1行40字以内 / 40字を超える段は必ず改行する
#
# 使い方:  python3 scripts/readability_scan.py queue/2026-11-01.json
#          ACCT=renai python3 scripts/readability_scan.py renai/queue/2026-11-01.json
# 戻り値:  0 = 通過 / 1 = 直すところがある
import sys, json, os, re

try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

ACCT = os.environ.get("ACCT", "spi")
PARENT_MAX = 40
COMMA_MAX = 2
REPLIES = (2, 4)
BODY = (60, 150)
LINE_MAX = 40
POLITE = re.compile(r"(です|ます|ません|でした|ました|でしょう|ください|か[？?]?)[。！!]*$")
BRIDGE = re.compile(r"^(.*。)([^。]{1,10}[、,]+)$")   # 「〜考えられない。それが、」

def main():
    if len(sys.argv) < 2:
        print("使い方: readability_scan.py <queue.json>"); return 1
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    bad = []
    for p in d["posts"]:
        s, t = p["slot"], p["tree"]
        head = t[0].strip()
        if "\n" in head:
            bad.append((s, "親", "改行が入っている(親は1文で独立)"))
        m = BRIDGE.match(head)
        if m and ACCT != "spi":
            head = m.group(1)
        elif m:
            bad.append((s, "親", "橋渡しの切れ端「%s」はスピでは使わない(静・S15)" % m.group(2)))
            head = m.group(1)
        if POLITE.search(head):
            bad.append((s, "親", "です・ます/問いで終わっている → 言い切りにする"))
        if len(head) > PARENT_MAX:
            bad.append((s, "親", "%d字 > %d字。短く切る" % (len(head), PARENT_MAX)))
        if head.count("、") > COMMA_MAX:
            bad.append((s, "親", "読点%d個。1文が長い" % head.count("、")))
        n = len(t) - 1
        if not REPLIES[0] <= n <= REPLIES[1]:
            bad.append((s, "ツリー", "セルフリプ%d本(%d〜%d本)" % (n, *REPLIES)))
        for i, r in enumerate(t[1:], 2):
            body = len(r.replace("\n", ""))
            if not BODY[0] <= body <= BODY[1]:
                bad.append((s, "%d段目" % i, "%d字(%d〜%d字)" % (body, *BODY)))
            if body > LINE_MAX and "\n" not in r:
                bad.append((s, "%d段目" % i, "改行が0個。1文ごとに改行する"))
            for ln in r.split("\n"):
                if len(ln) > LINE_MAX:
                    bad.append((s, "%d段目" % i, "1行%d字 > %d字「%s…」" % (len(ln), LINE_MAX, ln[:15])))
    print("対象: %s (ACCT=%s)" % (os.path.basename(sys.argv[1]), ACCT))
    if not bad:
        print("✅ 読みやすさの門を通過"); return 0
    for b in bad:
        print("🔴 %s %s: %s" % b)
    print("→ %d件。直してからもう一度実行する" % len(bad))
    return 1

if __name__ == "__main__":
    sys.exit(main())
