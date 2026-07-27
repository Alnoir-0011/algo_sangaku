## プロジェクト概要

**Algo Sangaku (アルゴ算額)** は、ユーザーがアルゴリズム問題を作成して「算額」として神社に奉納し、他のユーザーが作成した問題を解くことができるフルスタック Web アプリです。

モノレポ構成で2つのアプリが存在します:

- `back/` — Ruby on Rails 8.1.0 API（API モード）
- `front/` — Next.js 15 フロントエンド（App Router、TypeScript）

## バックエンド (`back/`)

### 開発コマンド

```bash
# 全サービス起動（事前に Docker ネットワーク作成が必要）
docker network create algo_sangaku_back-network
docker-compose up

# データベース
rails db:create && rails db:migrate && rails db:seed
```

> **注意:** Rails/bundle コマンドはローカルではなく Docker コンテナ内で実行する。
>
> ```bash
> docker-compose exec web bundle exec rails ...
> docker-compose exec web bundle exec rspec ...
> ```

### テスト実行コマンド

```bash
bundle exec rspec                            # 全テスト
bundle exec rspec spec/models/              # モデルテストのみ
bundle exec rspec spec/requests/            # API リクエストテストのみ
bundle exec rspec spec/path/to/file_spec.rb # 単一ファイル
```

### OpenAPI ドキュメントの更新

OpenAPI ドキュメント（`doc/openapi/`）は **`OPENAPI=1` を付けてテストを実行することで自動生成する**。手動編集は禁止。

```bash
docker-compose exec -e OPENAPI=1 web bundle exec rspec spec/requests/api/v1/admin/users_spec.rb
```

- ドキュメントにパラメータを追加したい場合は、そのパラメータを使う **動作確認テスト**（`openapi: false` なし）を用意することで反映する
- **OpenAPI ドキュメント更新のためだけのテストを作ることは禁止**。テストは必ず動作の仕様を表すものとして書く

### カバレッジ要件

- 新規コード: 80%以上（行カバレッジ）
- クリティカルパス（決済、認証）: 95%以上
- カバレッジが低下する PR はマージしない

### アーキテクチャ

- **Rails API モード**、バージョン付きルーティング `/api/v1/`
- **認証**: `ApiKey` モデルによるトークン認証; `Authorization: Bearer <token>` ヘッダー
- **シリアライズ**: JSONAPI Serializer
- **バックグラウンドジョブ**: Solid Queue（`bin/jobs` ワーカー）; 主要ジョブは `CorrectnessCheckJob` で PaizaIO を呼び出して提出コードを実行
- **外部 API**: Google OAuth（認証）、Google Maps/Places（神社データ）、PaizaIO（コード実行）

主要なモデルの関係:

- `User` → `Sangaku`（問題）→ `FixedInput`（テストケース）
- `User` → `Answer` → `AnswerResult`（テストケースごとの実行結果）
- `Shrine` ← 奉納 ← `Sangaku`
- `UserSangakuSave` — ユーザーが問題をブックマークするための中間テーブル

`app/models/concerns/` の共有 Concern:

- `PaizaioApi` — リモートコード実行
- `PlaceApi` — Google Places 神社検索
- `SphericalCosineTheorem` — 奉納時の地理的距離チェック
- `Api::Authentication` — トークン認証ヘルパー

### Docker サービス

| サービス | 説明                          |
| -------- | ----------------------------- |
| `db`     | PostgreSQL 18.0               |
| `web`    | Puma（nginx 経由でポート 80） |
| `queue`  | Solid Queue ワーカー          |
| `nginx`  | リバースプロキシ              |

## 主要なワークフロー

1. **問題を解く**: ユーザーが算額を保存 → コード解答を提出 → `CorrectnessCheckJob` が各 `FixedInput` で PaizaIO を呼び出す → `AnswerResult` のステータスを更新
2. **神社への奉納**: ユーザーが地図上で神社を選択 → `SphericalCosineTheorem` で距離を検証 → 算額が神社と紐付けられる
3. **認証フロー**: Google OAuth → バックエンドが `ApiKey` トークンを生成 → NextAuth セッションに保存 → 全 API 呼び出しで Bearer トークンとして送信
