#!/usr/bin/env python3
# 日をまたいだ【中身】の被りを検出する。
#
# 🔴 なぜ要るのか（2026-10-21 ボス裁定）
#   「重要なのは内容。言い回しは3日空けたら使っていい。中身が被らないように工夫してくれ」
#   → 言い換え在庫は3日で「使える」に戻すようにした（harvest_phrasings.py --mark-used）。
#     そのぶん、同じ言い方が【同じテーマ・同じ切り口】で戻ってくると、読者には同じ投稿に見える。
#   cross_day_scan.py は12字の文字列一致しか見ないので、言い方を変えた同じ話は素通りする。
#   この器は「何の話をしたか」の側を見る。
#
# 見るもの（直近7日）
#   0. 🔴 題材の重なり      : posts[].題材（場面・行動の語。例 ["神社","お願いごと"]）が、
#                            直近7日のテーマ・親投稿・題材に出ていないか ← いちばん確実な検査
#   1. テーマの近さ        : テーマ欄の文字2-gram の重なり（Jaccard）
#   2. 親投稿の近さ        : 親投稿の文字2-gram の重なり
#   3. オリジンの再登場    : 同じ断片ID（A1 / B2 / C6 …）が直近3日に出ていないか
#   4. 言い換え行×テーマ   : 3日空けて戻した言い換え行を、前と近いテーマで使っていないか
#
# 使い方:  python3 scripts/content_scan.py --list                 # 書く前: 直近7日の中身の一覧
#          python3 scripts/content_scan.py queue/2026-10-22.json   # 書いた後: 被りの検査
# 戻り値:  0 = 被りなし / 1 = 被りあり（テーマか切り口を変える）
import sys, json, re, glob, os, io

try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

DAYS_BACK = 7
ORIGIN_DAYS = 3
THEME_TH = 0.28     # 2026-10-18〜21 の実データで校正（下の注記）
PARENT_TH = 0.30
# 🔴 アカウントの解決（正本=参照/アカウント対応表.md / 対=scripts/acct_env.sh）
#    ACCT を省略すると spi。そのとき PFX は空文字＝【従来と同じ置き場】になる。
ACCT = os.environ.get("ACCT", "spi")
PFX = "" if ACCT == "spi" else ACCT + "/"
GENRE = "スピ" if ACCT == "spi" else "恋愛"
INV = "参照/言い換え在庫_%s.md" % GENRE
# 校正(2026-10-21): 10/18〜10/21 の別の日どうしで、テーマ Jaccard の最大は 0.20、親投稿は 0.25
#   （どれも「別の話」）。一方「受け取れない／ご馳走されると受け取れない」は 0.31、
#   「銀行アプリを開く癖」の言い換えは 0.40。その間に線を引いた。
# ⚠️ 2-gram は「神社でお願いをするか／神社でお願いごとをしてはいけない理由」(0.19) を取りこぼす。
#   だから題材(0.)を主にし、2-gram は保険にする。
# 題材に書いてはいけない語（コンセプトそのもの。毎日出るので被りの判定に使えない）
CORE = {"天秤", "重り", "引き寄せ", "お金", "願う", "願い", "強く願う", "東洋式", "西洋式", "降ろす", "神の天秤"}

def grams(s):
    s = re.sub(r"[\s\"“”『』「」、。！？!?・／/()（）]", "", s or "")
    return {s[i:i + 2] for i in range(len(s) - 1)}

def jac(a, b):
    a, b = grams(a), grams(b)
    return len(a & b) / len(a | b) if a and b else 0.0

def origins(p):
    return set(re.findall(r"\b([ABC]\d{1,2})\b", p.get("オリジン", "")))

def inventory():
    rows = []
    if os.path.exists(INV):
        for ln in io.open(INV, encoding="utf-8"):
            m = re.match(r"^\| (H\d+) \| (.+?) \| (使える|使用済み) \|", ln)
            if m and len(m.group(2).strip()) >= 12:
                rows.append((m.group(1), m.group(2).strip()))
    return rows

def rows_used(body, inv):
    return {h for h, f in inv if any(f[x:x + 12] in body for x in range(len(f) - 11))}

def load(path):
    d = json.load(io.open(path, encoding="utf-8"))
    out = []
    for p in d.get("posts", []):
        tree = p.get("tree") or [p.get("text", "")]
        out.append({"date": os.path.basename(path)[:10], "slot": p.get("slot", ""),
                    "theme": p.get("テーマ", ""), "kou": p.get("構成型", "")[:12],
                    "parent": tree[0], "body": "".join(tree), "orig": origins(p),
                    "topics": [w for w in (p.get("題材") or []) if w and w not in CORE]})
    return out

def main():
    files = sorted(glob.glob(PFX + "queue/*.json"), key=os.path.basename)
    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        # 書く前に使う: 直近7日（最新の日を含む）に何の話をしたかだけ出す
        for f in files[-DAYS_BACK:]:
            for p in load(f):
                print(f"  {p['date']} {p['slot']}  {p['theme'][:34]}  [{p['kou']}] "
                      f"{' '.join(sorted(p['orig']))}  題材={'・'.join(p['topics'])}")
        return 0
    target = sys.argv[1] if len(sys.argv) > 1 else files[-1]
    tbase = os.path.basename(target)
    past = [f for f in files if os.path.basename(f) < tbase][-DAYS_BACK:]
    inv = inventory()
    new = load(target)
    old = [p for f in past for p in load(f)]
    recent = {os.path.basename(f)[:10] for f in past[-ORIGIN_DAYS:]}

    print(f"対象: {tbase} / 比較: {[os.path.basename(f)[:10] for f in past]}")
    print("\n── 直近7日に書いた中身（テーマを選ぶ前にこれを見る）──")
    for p in old:
        print(f"  {p['date']} {p['slot']}  {p['theme'][:34]}  [{p['kou']}] {' '.join(sorted(p['orig']))}")

    hits = []
    for n in new:
        if not n["topics"]:
            hits.append(f"[題材が空] 今日 {n['slot']} … posts[].題材 に場面・行動の語を2〜4個入れること")
    for n in new:
        n_rows = rows_used(n["body"], inv)
        for o in old:
            tj, pj = jac(n["theme"], o["theme"]), jac(n["parent"], o["parent"])
            where = f"今日 {n['slot']} ⇔ {o['date']} {o['slot']}"
            seen = o["theme"] + o["parent"] + " ".join(o["topics"])
            dup = [w for w in n["topics"] if w in seen]
            if dup:
                hits.append(f"[題材が重なる {'・'.join(dup)}] {where}\n      「{o['theme']}」")
            if tj >= THEME_TH:
                hits.append(f"[テーマが近い {tj:.2f}] {where}\n      「{n['theme']}」\n      「{o['theme']}」")
            if pj >= PARENT_TH:
                hits.append(f"[親投稿が近い {pj:.2f}] {where}\n      「{n['parent']}」\n      「{o['parent']}」")
            if o["date"] in recent and n["orig"] & o["orig"]:
                hits.append(f"[オリジンが3日以内に再登場 {' '.join(sorted(n['orig'] & o['orig']))}] {where}")
            same = n_rows & rows_used(o["body"], inv)
            if same and tj >= THEME_TH * 0.6:
                hits.append(f"[戻した言い換え {' '.join(sorted(same))} を、近いテーマ({tj:.2f})でまた使っている] {where}")

    if not hits:
        print("\n✅ 中身の被りなし"); return 0
    print(f"\n🔴 {len(hits)}件。テーマか切り口（場面・オリジン・誰に向けるか）を変えること。言い方を変えるだけでは直らない。")
    for h in hits:
        print("\n  " + h)
    return 1

if __name__ == "__main__":
    sys.exit(main())
