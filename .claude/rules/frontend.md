## フロントエンド (`front/`)

### 開発コマンド

```bash
pnpm install
pnpm dev            # 開発サーバー http://localhost:4020 (Turbopack)
pnpm build          # 本番ビルド
pnpm lint           # ESLint
```

### テスト実行コマンド

```bash
pnpm test:e2e         # Playwright E2E（バックエンド起動が必要）
pnpm test:components  # Playwright コンポーネントテスト
pnpm show-report      # Playwright HTML レポートを表示
```

### カバレッジ要件

- 新規コード: 80%以上（行カバレッジ）
- クリティカルパス（決済、認証）: 95%以上
- カバレッジが低下する PR はマージしない

### テスト詳細

#### E2E テスト（`playwright.config.ts`）

- **設定ファイル**: `playwright.config.ts`
- **テストディレクトリ**: `tests/e2e/`、マッチパターン: `tests/**/*.spec.ts`
- **対象ブラウザ**: Chromium / Firefox / WebKit
- **Web サーバー**: テスト実行時に `.next` をクリーンビルドして自動起動（`http://localhost:4020`）
  ※ `reuseExistingServer: false` のため、ローカルでも常に専用サーバーをクリーンビルドして起動する
- **環境変数**: `APP_ENV=test` が自動で設定される。`.env` から追加変数を読み込む

```bash
# 基本
pnpm test:e2e                                          # 全E2Eテスト（全ブラウザ）

# オプション指定（-- を付けてPlaywright CLIに渡す）
pnpm test:e2e --project=chromium                    # Chromiumのみ
pnpm test:e2e --headed                              # ブラウザUIを表示して実行
pnpm test:e2e --debug                               # Playwright Inspector でデバッグ
pnpm test:e2e -g "テスト名のキーワード"              # テスト名フィルタ（正規表現可）
pnpm test:e2e tests/e2e/path/to/file.spec.ts        # 特定ファイルのみ
pnpm test:e2e --workers=1                           # シリアル実行（CI相当）
pnpm test:e2e --reporter=list                       # コンソール出力形式を変更

pnpm show-report                                       # HTML レポートをブラウザで確認
```

#### コンポーネントテスト（`playwright-ct.config.ts`）

- **設定ファイル**: `playwright-ct.config.ts`
- **テストディレクトリ**: `tests/components/`
- **実行エンジン**: `@playwright/experimental-ct-react`（Vite 経由）
- **ポート**: 3100（`ctPort`）
- **タイムアウト**: 10 秒/テスト
- **パスエイリアス**: `@/` → プロジェクトルート（`./`）

```bash
# 基本
pnpm test:components                                   # 全コンポーネントテスト

# オプション指定
pnpm test:components --headed                       # ブラウザUIを表示
pnpm test:components --debug                        # デバッグモード
pnpm test:components --project=chromium             # Chromiumのみ
pnpm test:components -g "コンポーネント名"           # テスト名フィルタ
pnpm test:components tests/components/path/to/file.spec.tsx  # 特定ファイルのみ
```

### アーキテクチャ

- **Next.js App Router**、全ルートは `app/` 配下
- **Material UI 6** と Emotion（CSS-in-JS）; テーマは `theme.ts`
- **NextAuth.js 5** で Google OAuth; テスト時は credentials プロバイダーを使用; セッションにバックエンドのアクセストークンを保持
- **Monaco Editor** で問題作成・解答提出時のコード入力・表示
- **Google Maps**（`@vis.gl/react-google-maps`）で神社選択・奉納フロー

主要なディレクトリ構成:

- `app/lib/actions/` — Server Actions（フォーム送信・更新処理）
- `app/lib/data/` — データ取得関数（バックエンド API 呼び出し）
- `app/ui/` — ドメインごとに整理された再利用可能な UI コンポーネント（`sangaku/`、`shrine/`、`answer/` など）
- `routes.ts` — ルートパス定義の一元管理（ナビゲーションにはここを使用）
- `auth.ts` — NextAuth 設定
- `middleware.ts` — セッション認証ミドルウェア（未認証ユーザーをリダイレクト）

### 環境変数

```
NEXT_PUBLIC_API_URL=http://localhost:80
NEXT_AUTH_URL=http://localhost:4020
NEXT_AUTH_SECRET=<secret>
NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=<key>
```

バックエンドの環境変数は `back/.env`（Google API キー、フロントエンド URL、PaizaIO キー）。
