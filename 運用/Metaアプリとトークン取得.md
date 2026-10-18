# Meta アプリ作成とトークン取得（STEP 2 の詳細手順）

> ## 🔴 最初に：秘密は私に渡さないでください
>
> **App Secret と アクセストークンは、私（Claude）に貼らないでください。** 必要ありません。
> 下のコマンドはボスのターミナルで実行し、出てきた値はそのまま GitHub Secrets に入れてください。
> 私が手伝えるのは「コマンドの組み立て」と「通ったかどうかの確認」までです。
>
> **App ID は秘密ではありません**（公開情報）。これは教えてもらえれば認可URLを組み立てます。

---

## 用語の整理（ここを間違えると詰まる）

| 名前 | 何者か | 秘密か |
|---|---|---|
| **Threads App ID** | 認可URLに入れる数字の文字列 | 公開してよい |
| **Threads App Secret** | トークン交換に使う | 🔴 秘密 |
| **認可コード（code）** | ブラウザのURLに1回だけ出る。有効1時間・使い捨て | 🔴 秘密 |
| **短期トークン** | 有効1時間 | 🔴 秘密 |
| **長期トークン** | 有効60日。これを GitHub Secrets に入れる | 🔴 秘密 |
| **Threads ユーザーID** | 投稿先の指定に使う数字 | 公開してよい |

🔴 **App ID / App Secret は「Threads 用のもの」を使う。** アプリを作ると Meta は別系統の App ID / App Secret も作りますが、
**それでは動きません。** Threads 用のものを使ってください（Meta のサンプルリポジトリも同じ注意を書いています）。

---

## STEP 2-A｜アプリを作る＆App ID を見つける

1. https://developers.facebook.com/apps/ → **アプリを作成**
2. ユースケースの選択で **Threads** を選ぶ
3. 作成後、**アプリ設定 → ベーシック** を開く

### 🔴 ここで必ず迷う：App ID が2つある

Threads ユースケースでアプリを作ると、**Meta は App ID と App Secret を2組作ります。**
ベーシックのページには両方載っていて、**上に出ている方は使えません。**

| ページ上の表記 | 使うか |
|---|---|
| ページ**上部**の「**アプリID**」「app secret」 | 🔴 **使わない**（これが見つかっても違う） |
| ページを**下にスクロール**して出てくる「**ThreadsアプリID**」「**Threads App Secret**」 | ✅ **こちらを使う** |

→ **「アプリID」しか見つからないときは、ページを下までスクロールしてください。** 別枠で「Threads」と頭に付いた方があります。

### それでも見つからないとき

**ユースケース → Threads API → 設定**（または「カスタマイズ」）のページにも出ます。
Meta のダッシュボードは表示名と配置が変わりやすいので、**頭に「Threads」と付いている方**を探すのが確実です。

App Secret はこの時点で一度だけコピーしてメモしておきます（後で GitHub Secrets に入れる）。

## STEP 2-B｜リダイレクトURIを登録する

**ユースケース → Threads API → 設定** の「リダイレクトコールバックURL」に登録します。

### ✅ 確定：`https://localhost/` で登録できた（2026-10-18 実測）

このアプリでは **`https://localhost/`** がリダイレクトURIとして**受け付けられた。**

> ⚠️ Meta のサンプルリポジトリには「Threads アプリは localhost のリダイレクトURLに対応していない」と書かれているが、
> **2026-10-18 時点のダッシュボードでは通った。** 公式サンプルの記述のほうが古いと見られる。
> → 📌 **ドキュメントに「できない」と書かれていても、実際の画面で試す価値がある。**

ブラウザは「接続できません」と表示するが、**アドレスバーに認可コードが残る**のでそれをコピーする。

### 認可コードの扱いで絶対に外さない点

認可コードは **登録したURLのクエリ文字列に乗って飛ぶ。**
つまり**他人のサイトのURLを登録すると、認可コードがその相手のサーバーに届く。**
`https://localhost/` はどこにも飛ばないので、この点で最も安全。

### もし将来 localhost が弾かれるようになったら

ボス自身の GitHub Pages `https://rasoltekaworu369-art.github.io/` を使う（自分のドメインなのでコードが他人に渡らない）。
ページが存在せず 404 でも、アドレスバーにコードは残る。

🔴 **登録したURLは一字も変えずに使う。** 末尾スラッシュの有無が違うだけで `36008` エラーになる。

---

## STEP 2-C｜自分をテスターとして招待する

1. **アプリのロール → ロール** で **Threads テスター** に自分の Threads アカウントを追加
2. **Threads 側（アプリまたは web）で招待を承諾する**

🔴 **これで App Review は不要になります。** 審査が必要なのは「ロールを持たない他人のアカウント」を扱うときだけです。
承諾を忘れると、この後の認可で権限が付きません。

---

## STEP 2-D｜認可URLを開く（確定版・2026-10-18）

**Threads App ID = `1924249725220987`**（公開情報）
**リダイレクトURI = `https://localhost/`**（登録済み・実測で確定）

この1本をブラウザで開く：

```
https://threads.com/oauth/authorize?client_id=1924249725220987&redirect_uri=https%3A%2F%2Flocalhost%2F&scope=threads_basic,threads_content_publish,threads_manage_insights,threads_manage_replies&response_type=code
```

### 開いたあと

1. Threads の認可画面が出る → **許可する**
2. `https://localhost/?code=...` に飛ぶ。**「接続できません」でも正常**
3. **アドレスバーの `code=` の値をコピー**
4. 🔴 **末尾に `#_` が付いていたら削る**（コードの一部ではない）
5. ⚠️ **有効1時間・使い捨て。** 失敗したらこのSTEPからやり直し

### ⚠️ ここで App ID の正否も分かる

認可画面が正常に出れば **App ID は正しい**（Threads用のもの）。
「アプリの設定に問題があります」系のエラーなら、ページ上部の「アプリID」を拾っているので 2-A に戻る。

## STEP 2-E｜認可コード → 短期トークン（1時間）

**ボスのターミナルで実行する。App Secret が入るので私には渡さないこと。**
`<APP_SECRET>` と `<CODE>` の2箇所だけ差し替える（App ID とリダイレクトURIは記入済み）。

```bash
curl -s "https://graph.threads.com/oauth/access_token" --data-urlencode "client_id=1924249725220987" --data-urlencode "client_secret=<APP_SECRET>" --data-urlencode "grant_type=authorization_code" --data-urlencode "redirect_uri=https://localhost/" --data-urlencode "code=<CODE>"
```

返ってくる JSON：

```json
{"access_token":"TH...","token_type":"bearer","user_id":1234567890}
```

- `access_token` → **短期トークン**。1時間以内に次のSTEPで交換する
- `user_id` → **Threads ユーザーID**。`THREADS_USER_ID` に入れる値（秘密ではない）

### 🔴 実際に踏んだ罠2つ（2026-10-18 実測）

**罠1：`curl` ではなく `curl.exe` と書く**

このターミナルは PowerShell で、**`curl` は別コマンド（Invoke-WebRequest）の別名**になっている。
`--data-urlencode` を受け付けずエラーになる。**必ず `curl.exe` と書く**（Windows 11 に標準で入っている）。

**罠2：`<` と `>` を外す**

プレースホルダの山カッコを付けたまま貼ると、山カッコごと送信される。

```
❌ --data-urlencode "client_secret=<実際の値>"
✅ --data-urlencode "client_secret=実際の値"
```

このとき返るエラー：

```json
{"error":{"message":"Invalid client_secret: <...>","type":"OAuthException","code":101}}
```

📌 **`code: 101` の `Invalid client_secret` でメッセージに山カッコが見えていたら、原因はこれ。**
🔴 **訂正（2026-10-18 実測）：この失敗でも認可コードは消費される。**
当初「client_secret の検証で止まるから消費されない」と書いたが**誤りだった。** 実際には1回目の失敗で消費され、
2回目は `used_authorization_code` で弾かれた。
→ 📌 **client_secret を間違えた場合も、認可URLから新しいコードを取り直す。**
→ 📌 **つまり「1回で通す」準備をしてから実行する。** `curl.exe` と山カッコ外しを先に確認しておくこと。

**うまくいかないとき：**

| エラー | 原因 |
|---|---|
| `36008` / redirect_uri mismatch | 登録URLと1文字でも違う。`https://localhost/` の末尾スラッシュを確認 |
| `used_authorization_code`（code 100 / subcode 4279030）| 🔴 **コードは1回使ったら死ぬ。** 失敗した試行でも消費される。2-D で新しいコードを取る |
| code already used | 同上 |
| 400 / invalid code | 1時間を超えた。2-D からやり直す |
| 権限が付いていない | 2-C のテスター承諾を忘れている |

## STEP 2-F.5｜🔴 App Secret のローテーション（露出させてしまった場合）

App Secret は**初回のトークン交換にしか使わない。**
`refresh_access_token`（60日ごとの更新）は `access_token` だけで動くので、**日常運用に App Secret は不要。**
→ **だからローテーション（作り直し）は安く済む。**

### 手順

1. まず STEP 2-F まで終わらせて、**長期トークンが動くことを確認する**（STEP 2-G）
2. Meta ダッシュボード → アプリ設定 → ベーシック → **Threads App Secret を「リセット」**
3. リセット後、STEP 2-G をもう一度実行して**長期トークンがまだ生きているか確認する**
4. 死んでいたら STEP 2-D から認可をやり直す（新しい Secret で 2-E・2-F を通す）

> ⚠️ **App Secret のリセットが既存のユーザートークンを無効化するかは、公式ドキュメントで確認できなかった。**
> 「アプリに紐づく有効なトークンを全部無効化する」という第三者情報があるが**未確認。**
> だから手順3で**必ず確認する。** 確信度50%なので、どちらに転んでも進める手順にしてある。

### 露出のリスク評価

| | |
|---|---|
| 露出先 | ボス自身の Claude セッションの記録のみ（公開されていない） |
| App Secret 単体でできること | Threads への投稿は**できない**（ユーザートークンが別途必要） |
| リスク | **低い。確信度85%** |
| 反証条件 | セッションの記録が外部に共有・エクスポートされている場合は上がる |

**それでもローテーションは推奨。** 上の通り日常運用に影響しないので、やらない理由がない。

---

## STEP 2-F｜短期トークン → 長期トークン（60日）

```bash
curl -s -G "https://graph.threads.com/access_token" --data-urlencode "grant_type=th_exchange_token" --data-urlencode "client_secret=<APP_SECRET>" --data-urlencode "access_token=<短期トークン>"
```

返ってくる `access_token` が**長期トークン（60日）**。これを `THREADS_ACCESS_TOKEN` に入れます。

🔴 **ここで止まらないこと。** 短期トークンのまま GitHub Secrets に入れると、**1時間後に全部動かなくなります。**

---

## STEP 2-G｜通ったことを確認する

```bash
curl -s -G "https://graph.threads.com/v1.0/me" --data-urlencode "fields=id,username" -H "Authorization: Bearer <長期トークン>"
```

`id` と `username` が返れば配線は通っています。

投稿の残量（250本/24h の上限）も見られます：

```bash
curl -s -G "https://graph.threads.com/v1.0/me/threads_publishing_limit" --data-urlencode "fields=quota_usage,config" -H "Authorization: Bearer <長期トークン>"
```

---

## STEP 2-H｜GitHub Secrets に入れる

https://github.com/rasoltekaworu369-art/threads-auto-post/settings/secrets/actions
→ **New repository secret**

| 名前 | 中身 |
|---|---|
| `THREADS_USER_ID` | 2-E の `user_id` |
| `THREADS_ACCESS_TOKEN` | 2-F の長期トークン |

これを入れ終えたら、`運用/セットアップ手順.md` の **STEP 4（手動で1本テスト投稿）** に進みます。
そこが通れば、この仕組みで一番不確実だった部分が片付きます。

---

## 🔴 60日の時計が、ここから動き始める

長期トークンは**取得した日から60日**で、更新しないと**恒久的に失効**します（OAuth からやり直し）。
事前警告は出ず、ある日いきなり 401 になります。

`.github/workflows/refresh-token.yml` が毎週日曜に更新しますが、**動くのは Secrets を入れた後からです。**
Secrets を入れた直後に、Actions タブから「Threads トークン更新」を **Run workflow** で1回手動実行して、
緑になることを確認してください。**ここを確認せずに放置すると、60日後に静かに全停止します。**

---

## API のホストについて（2026-10-18 時点）

公式ドキュメントは `graph.threads.com` に移行中で、旧ホスト `graph.threads.net` も現時点では同じ応答を返します。
スクリプトは `graph.threads.com` を既定にしつつ、環境変数 `THREADS_HOST` で切り替えられるようにしてあります。
片方が落ちたら、GitHub Actions の env に `THREADS_HOST: graph.threads.net` を足すだけで直ります。

**認可画面のホストも `threads.com/oauth/authorize` が新しい表記です**（旧 `threads.net/oauth/authorize`）。
