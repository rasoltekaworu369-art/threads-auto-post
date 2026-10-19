#!/usr/bin/env python3
# 日をまたいだ被りを検出する。
#
# 🔴 なぜ要るのか（2026-10-19 の事故）
#   横断スキャン（工程8-b）は「その日の9本の中」しか見ない。
#   10/20 の生成は 8-b を正しく実行して全9本が合格したが、
#   『強く願う ＝ 天秤に"まだ無い"という重りを乗せる』が
#   10/19 08:00 と 10/20 18:00 に【一字も違わず】出ていた。
#   毎日これが続けば、7日目には誰が見てもテンプレートに見える。
#   → その日の中だけ見ても検出できない欠陥がここにある。
#
# 使い方:  python3 scripts/cross_day_scan.py queue/2026-10-20.json
#          引数を省くと queue/ の最新日を対象にする。比較は直近3日。
# 戻り値:  0 = 被りなし / 1 = 被りあり（書き換えが必要）
import sys, json, re, glob, os, collections

# 端末のコードページに関係なく UTF-8 で出す（Windowsのcp932で文字化けするため）
try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

N_GRAM = 12        # 憲章の横断スキャンと同じ粒度
DAYS_BACK = 3
MIN_REPORT = 12    # 結合後、これ未満の一致は報告しない

# 一般的すぎて被りとして数えないもの（手順書の注記に対応）
GENERIC = re.compile(
    r"^[\s。、ー！？]*(で|では|の|と|が|を|に|は|も|か|ね|よ|い|な|ら|る|た)*"
    r"あり(ま)?せん(でした)?。?[\s]*$"
    r"|^[\s。、ー！？]*$"
    r"|^[\s。、ー]*(つもりは|問題では|わけでは|ことでは|せいでは)"
    r"あり(ま)?せん(でした)?。?[\s]*$"
)

def bodies(path):
    d = json.load(open(path, encoding="utf-8"))
    return [(p.get("slot"), "".join(p.get("tree") or [p.get("text", "")]))
            for p in d.get("posts", [])]

def merged_matches(new_body, old_body):
    """old_body にも出てくる N_GRAM 以上の一致を、重なりを結合して返す"""
    old_grams = {old_body[i:i + N_GRAM] for i in range(len(old_body) - N_GRAM + 1)}
    spans = [(i, i + N_GRAM) for i in range(len(new_body) - N_GRAM + 1)
             if new_body[i:i + N_GRAM] in old_grams]
    out, cur = [], None
    for a, b in spans:                      # 位置順。重なる区間を1つに潰す
        if cur and a <= cur[1]:
            cur = (cur[0], max(cur[1], b))
        else:
            if cur: out.append(cur)
            cur = (a, b)
    if cur: out.append(cur)
    return [new_body[a:b] for a, b in out]

def main():
    files = sorted(glob.glob("queue/*.json"), key=os.path.basename)
    if not files:
        print("queue/ にファイルが無い"); return 0
    target = sys.argv[1] if len(sys.argv) > 1 else files[-1]
    # 🔴 Windows の glob は "queue\2026-10-18.json" を返す。
    #    target が "queue/2026-10-20.json" だと生の文字列比較が壊れるので、
    #    必ずファイル名だけで比べる（2026-10-19 にこれで過去日を1件も拾えなかった）。
    tbase = os.path.basename(target)
    past = [f for f in files if os.path.basename(f) < tbase][-DAYS_BACK:]

    print(f"対象: {tbase} / 比較: {[os.path.basename(f) for f in past]}")
    if not past:
        print("✅ 比較対象の過去日が無い（この日が最初）"); return 0

    hits = collections.defaultdict(list)   # 一致文字列 -> [(過去日, 過去枠, 今日の枠)]
    new_posts = bodies(target)
    for f in past:
        for oslot, obody in bodies(f):
            for nslot, nbody in new_posts:
                for m in merged_matches(nbody, obody):
                    if len(m) < MIN_REPORT or GENERIC.match(m) or "http" in m:
                        continue
                    hits[m].append((os.path.basename(f)[:10], oslot, nslot))

    # 長いものに含まれる短い一致は捨てる（同じ事故を何度も報告しないため）
    keys = sorted(hits, key=len, reverse=True)
    keep = [k for i, k in enumerate(keys) if not any(k in j for j in keys[:i])]

    if not keep:
        print("✅ 日をまたいだ被りなし"); return 0

    print(f"🔴 {len(keep)}件の被り。該当する本を書き換えること。")
    for k in keep:
        where = "; ".join(f"{d} {o} → 今日 {n}" for d, o, n in hits[k])
        print(f"\n  [{len(k)}字] 「{k.strip()}」")
        print(f"      {where}")
    print()
    print("🔴 とくに次のものは、1字でも一致したら必ず書き換える:")
    print("   ・コンセプトの等式の正式な形（『強く願う ＝ …』）")
    print("   ・『神の天秤』などの命名を導入する一文")
    print("   ・締めの最終文の形")
    print("   ・導線の一文")
    return 1

if __name__ == "__main__":
    sys.exit(main())
