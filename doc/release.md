# リリース手順書

親リポジトリ（`algo_sangaku`）の `main` ブランチ更新（PRマージ）を、本番デプロイの唯一のトリガーとする運用の手順書。詳細設計は [Alnoir-0011/algo_sangaku#38](https://github.com/Alnoir-0011/algo_sangaku/issues/38) を参照。

## 全体像

```
front/back それぞれで通常通り開発・レビュー・マージ（各リポジトリの既存CIはそのまま実行される。本番デプロイはここでは起きない）
        │
        ▼
リリースしたくなったら、本ドキュメントの手順で親リポの submodule ポインタを更新して PR 作成・マージ
        │  .github/workflows/deploy.yml が起動
        ▼
   変更のあった submodule（back / front）だけ、対象リポジトリの
   workflow_dispatch(sha) をリモート起動（fire-and-forget。完了は待たない）
        │
        ├─→ back: autodeploy.yml → Required reviewer 承認 → ECR push → ECS deploy
        └─→ front: deploy.yml    → Required reviewer 承認 → Vercel production deploy
```

**重要**: 親リポの `deploy.yml` は dispatch の呼び出しが成功した時点でジョブを終了する。実際のデプロイ成否・承認待ちは追跡しないため、以下の手順で毎回手動確認すること。

## 前提条件

- 親リポジトリの Secrets に `DEPLOY_DISPATCH_TOKEN`（back/front 双方への `workflow_dispatch` を起動できる fine-grained PAT）が登録済みであること
- back/front それぞれの GitHub Environment `production` に Required reviewer が設定されており、承認できるメンバーであること

## 通常リリース手順

1. リリース対象を確定する。back/front どちらか一方でも、両方でもよい
2. 各サブモジュールで最新の `main` を取得する
   ```bash
   cd back && git checkout main && git pull
   cd ../front && git checkout main && git pull
   ```
3. 親リポジトリで submodule ポインタを進める
   ```bash
   cd ..
   git checkout main && git pull
   git checkout -b release/YYYY-MM-DD   # 親リポでもブランチを切る
   git add back front                    # 更新があった方だけでも可
   git commit -m "release: back/front submodule ポインタ更新"
   git push -u origin release/YYYY-MM-DD
   gh pr create --title "Release YYYY-MM-DD" --body "..."
   ```
4. 親リポの PR をレビューし、`main` へマージする
5. マージ後、`.github/workflows/deploy.yml` の実行を親リポの Actions タブで確認する
   - 変更があったリポジトリ（back/front）に対してのみ dispatch のログ（`::notice`）が出力される
6. dispatch されたリポジトリの Actions タブを開き、起動されたワークフロー（back: `ECS deploy` / front: `Deploy`）を確認する
   - `environment: production` の承認待ち状態になっているので、Required reviewer が承認する
7. 承認後、デプロイが完了するまで進捗を確認する
   - back: ECS サービスが安定化（`deployments` が1件になる）するまで最大20分ポーリングされる。失敗時はジョブが赤くなる
   - front: `vercel deploy --prod` 後、ヘルスチェック（`curl` によるデプロイ先URLへのリクエスト）が実行される。失敗時はジョブが赤くなり、コミットステータス（`deploy/vercel-production`）も `failure` になる
8. 両サービスとも正常完了したことを確認して完了とする

## ロールバック手順

### 親リポ側からの一括ロールバック（推奨）

直前のリリース（マージコミット）を revert して push する。同じ `deploy.yml` が古い（ロールバック先の）SHA で両サービスに再度 dispatch する。

```bash
git checkout main && git pull
git revert -m 1 <マージコミットのSHA>
git push
```

以降の手順（Actions 確認・承認）は通常リリース手順の 5〜8 と同じ。

### 片方だけをロールバックしたい場合

親リポでの revert は back/front 両方のポインタを戻してしまうため、片方だけ戻したい場合は該当する gitlink のみを対象コミットに戻すコミットを作成する。

```bash
git checkout main && git pull
git checkout -b rollback/back-only
git -C back checkout <戻したいコミットSHA>    # 対象サブモジュールのみ移動
git add back
git commit -m "rollback: back のみ直前バージョンに戻す"
git push -u origin rollback/back-only
gh pr create ...
```

## トラブルシューティング

| 症状 | 原因の見当 | 対処 |
| --- | --- | --- |
| 親リポの `deploy.yml` 自体が失敗する（dispatch呼び出しでエラー） | `DEPLOY_DISPATCH_TOKEN` の期限切れ・権限不足、対象リポジトリ名/ワークフローファイル名の変更 | トークンを再発行し Secrets を更新する。対象ワークフローのファイル名が変わっていないか確認する |
| dispatch はされたが、対象リポジトリの Actions に何も出てこない | ワークフロー名・ファイル名の指定間違い、`--ref main` が対象ブランチに存在しない | `gh workflow list --repo <repo>` で対象ワークフローの状態を確認する |
| 承認待ちのまま進まない | Required reviewer が誰も承認していない、承認者に通知が届いていない | 対象リポジトリの Actions タブ → 該当 run → `Review deployments` から手動で承認する。承認者・エスカレーション先は下記「緊急連絡フロー」を参照 |
| back のデプロイが「service did not stabilize」でタイムアウトする | ECS タスクが `unhealthy` を繰り返している、リソース不足 | ECS コンソールでタスクのイベントログ・CloudWatch Logs を確認する。必要なら手動でロールバック手順を実施する |
| front のヘルスチェックが失敗する | Vercel 側のビルド・デプロイは成功したがアプリが起動していない、環境変数不足 | Vercel ダッシュボードでデプロイログを確認する。必要ならロールバック手順を実施する |
| 指定した SHA が「is not an ancestor of main」で弾かれる | fork 由来の未マージコミットや、まだ push されていないローカルコミットの SHA を指定した | `main` に実際にマージされたコミットの SHA を指定し直す |
| front で「CI has not passed」エラーになる | 対象 SHA の check-runs が全て success になっていない（実行中含む） | 対象コミットの CI が完了し全て成功していることを確認してから再実行する（back 側にはこの検証はない点に注意） |

## 緊急連絡フロー

<!-- TODO: 承認者一覧・エスカレーション先（Slackチャンネル等）を記入する -->

- 承認者（Required reviewer）: TODO
- 連絡先（障害時のエスカレーション先）: TODO

## 参考

- [Alnoir-0011/algo_sangaku#38](https://github.com/Alnoir-0011/algo_sangaku/issues/38) — 本仕組みの詳細設計
- [Alnoir-0011/algo_sangaku_back#296](https://github.com/Alnoir-0011/algo_sangaku_back/issues/296) — back 側トリガー変更
- [Alnoir-0011/algo_sangaku_front#100](https://github.com/Alnoir-0011/algo_sangaku_front/issues/100) — front 側デプロイワークフロー新規追加
- [Alnoir-0011/algo_sangaku_back#300](https://github.com/Alnoir-0011/algo_sangaku_back/issues/300) — Environment `production` の Required reviewer / Repository Rulesets 設定
- [Alnoir-0011/algo_sangaku_back#301](https://github.com/Alnoir-0011/algo_sangaku_back/issues/301) — OIDC 信頼ポリシーの絞り込み
