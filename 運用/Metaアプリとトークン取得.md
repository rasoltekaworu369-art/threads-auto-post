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

### 🔴 どのURLを使うか（ここが一番迷うところ）

認可コードは **登録したURLのクエリ文字列に乗って飛んでいきます。**
つまり**他人のサイトのURLを登録すると、認可コードがその相手のサーバーに届きます。** 絶対に避けてください。

**推奨の順番：**

1. **まず `https://localhost/` を登録してみる**
   - 通れば一番簡単。ブラウザは「接続できません」と表示しますが、**アドレスバーに認可コードが残る**のでそれをコピーします
   - ⚠️ Meta のサンプルリポジトリには「Threads アプリは localhost のリダイレクトURLに対応していない」と書かれています。**ダッシュボードが弾いたら次へ**
2. **弾かれたら、ボス自身の GitHub Pages を使う**
   - `https://rasoltekaworu369-art.github.io/` を登録する（ボス自身のドメインなので、コードが他人に渡らない）
   - ページが存在しなくても構いません。404 でもアドレスバーにコードは残ります
3. ボスが持っているドメインがあれば、それでも可（HTTPS必須）

🔴 **登録したURLは一字も変えずに使う。** 末尾のスラッシュの有無が違うだけで `36008` エラーで弾かれます。
ダッシュボードが勝手に末尾スラッシュを足すことがあるので、**登録後の一覧に表示されている文字列をコピーして使ってください。**

---

## STEP 2-C｜自分をテスターとして招待する

1. **アプリのロール → ロール** で **Threads テスター** に自分の Threads アカウントを追加
2. **Threads 側（アプリまたは web）で招待を承諾する**

🔴 **これで App Review は不要になります。** 審査が必要なのは「ロールを持たない他人のアカウント」を扱うときだけです。
承諾を忘れると、この後の認可で権限が付きません。

---

## STEP 2-D｜認可URLを開く（App ID 記入済み・2026-10-18）

**Threads App ID = `1924249725220987`**（ボス提供・公開情報なのでこのファイルに記録してよい）

リダイレクトURIは 2-B で登録したものに合わせて、下の**どちらか**を使う。
🔴 **登録していない方を使うと `36008` で弾かれる。**

### A. `https://localhost/` を登録した場合

```
https://threads.com/oauth/authorize?client_id=1924249725220987&redirect_uri=https%3A%2F%2Flocalhost%2F&scope=threads_basic,threads_content_publish,threads_manage_insights,threads_manage_replies&response_type=code
```

### B. `https://rasoltekaworu369-art.github.io/` を登録した場合

```
https://threads.com/oauth/authorize?client_id=1924249725220987&redirect_uri=https%3A%2F%2Frasoltekaworu369-art.github.io%2F&scope=threads_basic,threads_content_publish,threads_manage_insights,threads_manage_replies&response_type=code
```

### 末尾スラッシュが無い形で登録した場合

`%2F` の最後の1つを消す。例:`https%3A%2F%2Flocalhost` （登録一覧の文字列と**一字も違わないこと**）

### 開いたあと

1. Threads の認可画面が出る → **許可する**
2. リダイレクト先に飛ぶ。**ページが「接続できません」や 404 でも問題ない**
3. **アドレスバーの `?code=` 以降をコピーする**
4. 🔴 **末尾に `#_` が付いていたら削る**（コードの一部ではない）
5. ⚠️ **有効1時間・使い捨て。** 失敗したらこのSTEPからやり直し

### ⚠️ ここで App ID の正否が分かる

認可画面が正常に出れば、**App ID は正しい**（Threads用のもの）。
「アプリの設定に問題があります」等のエラーが出たら、**ページ上部の「アプリID」を拾ってしまっている**ので 2-A に戻る。

## STEP 2-E｜認可コード → 短期トークン（1時間）

**ボスのターミナルで実行してください。App Secret が入るので、私には渡さないでください。**

```bash
curl -s -X POST "https://graph.threads.com/oauth/access_token" -d "client_id=<APP_ID>" -d "client_secret=<APP_SECRET>" -d "grant_type=authorization_code" -d "redirect_uri=<REDIRECT_URI>" -d "code=<CODE>"
```

返ってくる JSON：

```json
{"access_token":"TH...","token_type":"bearer","user_id":1234567890}
```

- `access_token` → これが**短期トークン**。次のSTEPで1時間以内に使う
- `user_id` → これが **Threads ユーザーID**。`THREADS_USER_ID` に入れる値（秘密ではない）

**うまくいかないとき：**

| エラー | 原因 |
|---|---|
| `36008` / redirect_uri mismatch | 2-B で登録したURLと1文字でも違う。末尾スラッシュを確認 |
| code already used | コードは使い捨て。2-D からやり直す |
| 400 / invalid code | 1時間を超えた。2-D からやり直す |
| 権限が付いていない | 2-C の承諾を忘れている |

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
