#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""言い換え在庫の採取器（層1）。

🔴 これは「発明しない」ための道具である。
   憲章:「型が足りなくなっても発明しない。自作の型は必ず"整ったAI文"になる。
         ボスの実物から追加する。」
   在庫が枯れたときに呪術者が新しい言い方を作ってしまうのを防ぐため、
   ボスが実際に書いた文だけを機械で集めて在庫表にする。

やること / やらないこと
   ⭕ 採る     : ボス実物から機序を説明している文を抜く
   ⭕ 機械処理 : note専用の装飾（「、、」絵文字 (笑)）を落とす
   ⭕ 印をつける: 「静」や憲章に反する箇所を flag で指摘する
   ⭕ 倒す・戻す: 直近3日の queue に出た行を 使用済み に、3日空いた行を 使える に戻す（--mark-used）
   🔴 やらない : 文を書き換える・新しい言い方を作る
                → 「静」への変換は人（呪術者）がやる。この器は候補と指摘までで止まる。
                  変換後も出典列にボスの原文を必ず残す（翻訳か発明かを後から検証できる）。

使い方
   python3 scripts/harvest_phrasings.py                 # 採取して追記（既存行は触らない）
   python3 scripts/harvest_phrasings.py --dry-run       # 出力せず件数だけ見る
   python3 scripts/harvest_phrasings.py --mark-used     # 使った言い換えを倒す
   python3 scripts/harvest_phrasings.py --src D:/path   # お手本の置き場を指定
"""
import argparse
import glob
import io
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

OUT = "参照/言い換え在庫_スピ.md"

# ── 出典として認めるもの ───────────────────────────────────────────
# 🔴 ボスが書いた物だけ。my秘書/制作/ は呪術者が書いたAI下書きを含むので入れない。
#    実測(2026-10-20): 制作/ は405,637字あるが大半がAI文。採ると再循環する。
BOSS_NAME = re.compile(r"ボス推敲|ボス下書き|ボス手書き|ボス加筆")

# 🔴 ジャンルはファイル名で判定できない（2026-10-20 の失敗）。
#    「40代50代から彼女を作った人が…」は恋愛だが名前に「恋愛」が無く、
#    最初の版はこれを出典に通してしまった。→ 中身の語彙で判定する。
SPI_W = re.compile(r"天秤|引き寄せ|重り|言霊|予祝|アファメ")
OTH_W = re.compile(r"彼女|マチアプ|デート|プロンプト|ChatGPT|記事を書")


def is_spi(text):
    """スピ語が1つ以上あり、かつ他ジャンル語より多いファイルだけを出典にする。

    実測(2026-10-20): 神の天秤=44対0 / スピお金コーパス=52対4 / 大丈夫=1対0 が通り、
    恋愛コーパス=0対101 / AI副業コーパス=1対25 が落ちる。
    """
    spi = len(SPI_W.findall(text))
    return spi >= 1 and spi > len(OTH_W.findall(text))


# ── 機序を説明している文の判定 ─────────────────────────────────────
WISH = re.compile(r"願|欲し|求め|想像|アファメ|予祝|祈|叶|執着")
LACK = re.compile(r"無い|足り|持って|まだ|欠け|不足|沈")
MECH = re.compile(r"天秤|皿|重り|重さ|重た|沈|傾|軽く|降ろ|乗せ|不足感")

# ── 私（AI）が書いた注記を弾く ─────────────────────────────────────
# 🔴 参照/お手本_*.md の冒頭には私の注記が入っている。そこから採ると
#    「AI文を出典として登録する」という最悪の事故になる。
META = re.compile(r"憲章|呪術者|Routine|queue|採点|条項|ボス|出典|工程|スキャン|"
                  r"在庫|禁止|Threads|note専用|S\d\d|L\d\d|確信度|反証")

# ── 🔴 有料部分の核（採ったらThreadsで有料部分を漏らす）────────────────
#    出典: 参照/お手本_無料部分_東洋式の引き寄せ.md の境界表
#      書かない: 重り3種類の「正体」/ 重りの「降ろし方」/ 天秤診断21問の中身 /
#                セルフトーク台本5本 / 30日実行表 / 天秤が上がった時に先に起きること5つ
#    ⚠️ 「重りを降ろす」「天秤を軽くする」は【使ってよい語】。禁じられているのは"降ろし方"。
PAID = re.compile(r"降ろし方|診断|21問|台本|実行表|30日|正体|回し方|起きること|"
                  r"この記事でやるのは|1つずつ特定|名前を付けて")

# 商品説明・目次・CTA（機序の言い換えではない）
NOT_MECH = re.compile(r"[・].*[・]|プロフ|興味があれば|読んでみて|そういう作りに|"
                      r"書いていますので|タイムラグ|私の体感では")

# ── 「静」と憲章に反するもの ────────────────────────────────────────
# 🔴 この検査は【疑わしきは要変換】に倒す。
#    2026-10-20 の初版は「、、絵文字(笑)タメ口」だけを見ていたため、
#    S22違反（「20年かけて」）・常体（「〜引き寄せる。」）・途中で切れた文を
#    すべて「使える」と誤判定した。機械が見落とすと禁止表現が投稿に乗る。
EMOJI = re.compile("[\u2190-\u21ff\u2300-\u27bf\u2b00-\u2bff"
                   "\U0001F000-\U0001FAFF\ufe0f]")
S15_FLAGS = [
    ("尻切れフック「、、」", re.compile(r"、、")),
    ("絵文字", EMOJI),
    ("(笑)", re.compile(r"[（(]笑[)）]")),
    ("タメ口", re.compile(r"だよ|だね|だろ|しろ|よね。|ぶっちゃけ|なら.?残念|"
                        r"ですよ。|ますよ。|でしょ。")),
    ("擬音", re.compile(r"ドキ|ズバ|グサ|ガーン|ドヨーン")),
    ("ランキング", re.compile(r"第\d位|ワースト|ベスト\d")),
    ("断定副詞", re.compile(r"必ず|絶対|誰でも|ほぼ全員|いちばん多い")),
    # 🔴 S22: フィード短文で権威の年数を使わない（お手本のnote原稿には入っている）
    ("権威の年数(S22)", re.compile(r"\d+\s*年(かけて|かかり|続け|見てき|やってき)")),
    # 等式の正式形は「9本に1本だけ」の別管理。在庫から引かせない
    ("等式の正式形", re.compile(r"強く願う\s*[＝=]\s*天秤")),
]

# です・ます以外で終わる文は常体（CLAUDE.md「全ジャンルです・ます調」違反）
POLITE_END = re.compile(r"(です|ます|ません|ましょう|ください|でしょう|ですね|ますね|"
                        r"ですか|ますか|でした|ました|んです|のです)[。？！?!]?$")

PAIRS = [("「", "」"), ("『", "』"), ("（", "）"), ("(", ")")]


def broken(s):
    """途中で切れた文を弾く。引用符の数が合わない文は分割の失敗。"""
    for a, b in PAIRS:
        if s.count(a) != s.count(b):
            return True
    return s.count(chr(34)) % 2 == 1


def check(s):
    """反する箇所を全部返す。空リストなら そのまま使える。"""
    flags = [n for n, p in S15_FLAGS if p.search(s)]
    if broken(s):
        flags.append("文が途中で切れている")
    if not POLITE_END.search(s):
        flags.append("常体(です・ます調でない)")
    return flags


def strip_decor(s):
    """機械で落として差し支えないもの（装飾だけ。文意は変えない）。"""
    s = re.sub(r"、、+", "、", s)
    s = EMOJI.sub("", s)
    s = re.sub(r"[（(]笑[)）]", "", s)
    return re.sub(r"\s+", "", s).strip()


def sources(src_root):
    found = []
    pattern = os.path.join(src_root, ".claude/skills/ozunu/お手本/*.md")
    for f in sorted(glob.glob(pattern)):
        if not BOSS_NAME.search(os.path.basename(f)):
            continue
        if is_spi(io.open(f, encoding="utf-8", errors="replace").read()):
            found.append(f)
    # リポジトリ内のボス実物の抽出版も出典に含める
    for f in ["参照/お手本_無料部分_東洋式の引き寄せ.md",
              "参照/お手本_Threads_スピ.md"]:
        if os.path.exists(f):
            found.append(f)
    # 🔴 2026-10-21 追加: ボスが置いた原稿と、週末の音声メモの文字起こし。
    #    ボス本人が置く場所なので名前の印は問わない。ジャンルだけは中身で判定する（恋愛・副業を落とす）
    for f in sorted(glob.glob("参照/ボス原稿/*.md") + glob.glob("参照/ボス原稿/*.txt")):
        if os.path.basename(f).startswith("README"):
            continue
        if is_spi(io.open(f, encoding="utf-8", errors="replace").read()):
            found.append(f)
    return found


def candidates(path):
    t = io.open(path, encoding="utf-8", errors="replace").read()
    # 見出し・表・箇条書き・引用を落とす（私の注記はほぼここに入っている）
    t = re.sub(r"^\s*[#>|\-*].*$", "", t, flags=re.M)
    t = re.sub(r"```.*?```", "", t, flags=re.S)
    for s in re.split(r"(?<=[。？！?!])\s*", t):
        s = re.sub(r"\s+", "", s).strip()
        if not (15 <= len(s) <= 80):
            continue
        if META.search(s):          # 私が書いた注記
            continue
        if PAID.search(s):          # 🔴 有料部分の核
            continue
        if NOT_MECH.search(s):      # 目次・CTA・商品説明
            continue
        # 機序語が入っていれば単独で通す。無ければ願望語+欠乏語の両方を要求する
        if not (MECH.search(s) or (WISH.search(s) and LACK.search(s))):
            continue
        yield s


def used_cores(files=None):
    """queue に既に出た文の核を集める（12字の塊で照合する）。"""
    cores = set()
    for f in (glob.glob("queue/*.json") if files is None else files):
        d = json.load(io.open(f, encoding="utf-8"))
        for p in d.get("posts", []):
            b = "".join(p.get("tree") or [p.get("text", "")])
            for i in range(len(b) - 12):
                cores.add(b[i:i + 12])
    return cores


def existing_rows():
    """既存の在庫表にある出典（原文）を読む。🔴 使用状況を消さないため。"""
    if not os.path.exists(OUT):
        return set(), ""
    body = io.open(OUT, encoding="utf-8").read()
    return set(re.findall(r"\|\s*`([^`]+)`\s*\|", body)), body


ROW = re.compile(r"^\| (H\d+) \| (.+?) \| (使える|使用済み) \|")

# 🔴 2026-10-21 ボス裁定:「重要なのは内容。言い回しは3日空けたら使っていい」
#    → 直近3日の queue に出ていない行は「使える」に戻す。
#    cross_day_scan.py も直近3日と比べるので、窓を揃えておけば戻した行で exit 1 にならない。
#    中身（テーマ・切り口・オリジン）の被りは scripts/content_scan.py が別に見る。
COOLDOWN_DAYS = 3


def mark_used():
    """🔴 「使った」の記録を人の手に任せると必ず忘れる（手順書に書いても実行されない）。
    直近3日の queue に実際に出ているかで、使用済み⇔使える を機械的に揃える。"""
    if not os.path.exists(OUT):
        print("在庫表が無い。先に採取すること")
        return 2
    files = sorted(glob.glob("queue/*.json"), key=os.path.basename)[-COOLDOWN_DAYS:]
    print("使用中とみなす窓: " + ", ".join(os.path.basename(f)[:10] for f in files))
    used = used_cores(files)
    lines = io.open(OUT, encoding="utf-8").read().splitlines()
    to_used = to_free = 0
    for i, ln in enumerate(lines):
        m = ROW.match(ln)
        if not m:
            continue
        form = m.group(2).strip()
        if len(form) < 12:
            continue
        hit = any(form[x:x + 12] in used for x in range(len(form) - 11))
        if hit and m.group(3) == "使える":
            lines[i] = ln.replace("| 使える |", "| 使用済み |", 1)
            to_used += 1
            print("  使用済みに倒した: " + m.group(1) + " " + form[:30])
        elif not hit and m.group(3) == "使用済み":
            lines[i] = ln.replace("| 使用済み |", "| 使える |", 1)
            to_free += 1
            print("  3日空いたので戻した: " + m.group(1) + " " + form[:30])
    if to_used or to_free:
        io.open(OUT, "w", encoding="utf-8", newline="\n").write(
            chr(10).join(lines) + chr(10))
    print("使用済みに倒した行: " + str(to_used) + " / 使えるに戻した行: " + str(to_free))
    return 0


HEADER = [
    "# 言い換え在庫・スピ（機序の説明を毎回違う言い方で書くための在庫）",
    "",
    "> 🔴 **ここに無い言い方を使ってはいけない。** 枯れたら発明せず、",
    "> `scripts/harvest_phrasings.py` を回して実物から採取する。",
    "",
    "> **全件、ボスが書いた原稿が出典。** `my秘書/制作/` のAI下書きからは採っていない。",
    "",
    "> **状態** の意味: `要変換`=「静」に直してから使う / `使える`=そのまま使える /",
    "> `使用済み`=直近3日の queue に出ている（3日空くと自動で `使える` に戻る） / `不採用`=機序の言い換えではない",
    "",
    "---",
    "",
    "| # | 言い換え（使う形） | 状態 | 機械が指摘した箇所 | 備考 | 出典（ボスの原文） |",
    "|---|---|---|---|---|---|",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src",
                    default=os.path.abspath(os.path.join(os.getcwd(), "..")))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--mark-used", action="store_true",
                    help="queue に出た言い換えを 使える→使用済み に倒す")
    a = ap.parse_args()

    if a.mark_used:
        return mark_used()

    srcs = sources(a.src)
    if not srcs:
        print("出典が1つも見つからない。--src でお手本の置き場を指定すること")
        return 2
    print("出典 " + str(len(srcs)) + " ファイル:")
    for f in srcs:
        print("   " + os.path.basename(f))

    known, body = existing_rows()
    used = used_cores()
    rows, seen = [], set()
    for f in srcs:
        for s in candidates(f):
            if s in seen or s in known:
                continue
            seen.add(s)
            clean = strip_decor(s)
            flags = check(s)
            already = any(clean[i:i + 12] in used
                          for i in range(max(0, len(clean) - 12)))
            rows.append((s, clean, flags, already))

    new = [r for r in rows if not r[3]]
    print()
    print("候補 " + str(len(rows)) + " 本（既出を除く）/ うち未使用 "
          + str(len(new)) + " 本")
    print("  要変換（反する箇所あり）: " + str(sum(1 for r in new if r[2])) + " 本")
    print("  そのまま使える見込み    : " + str(sum(1 for r in new if not r[2])) + " 本")
    if a.dry_run:
        return 0

    # 🔴 新規が0件なら1バイトも書かない（書くと空行が毎回増える）
    if not new and body:
        print()
        print("新しい候補は無い。在庫表は触っていない: " + OUT)
        return 0

    lines = [] if body else list(HEADER)
    # 🔴 既存の最大番号から続ける（番号が重複すると在庫表が壊れる）
    nums = [int(x) for x in re.findall(r"^\| *H(\d+)", body, flags=re.M)]
    n0 = max(nums) if nums else 0
    for i, (s, clean, flags, _) in enumerate(new, n0 + 1):
        state = "要変換" if flags else "使える"
        lines.append("| H" + str(i) + " | " + ("" if flags else clean) + " | "
                     + state + " | " + ("／".join(flags) if flags else "—")
                     + " | — | `" + s + "` |")
    with io.open(OUT, "a" if body else "w", encoding="utf-8",
                 newline="\n") as fh:
        fh.write((chr(10) if body else "") + chr(10).join(lines) + chr(10))
    print()
    print(("追記" if body else "新規作成") + ": " + OUT
          + "（" + str(len(new)) + "行）")
    print("🔴 状態が『要変換』の行は、呪術者が「静」の形を2列目に書くまで使えない。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
