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

- 親リポジトリの Environment `deploy-dispatch`（Deployment branch policy: `main` 限定）に、Secrets `DEPLOY_DISPATCH_TOKEN`（back/front 双方への `workflow_dispatch` を起動できる fine-grained PAT）が登録済みであること。repository secret ではなく environment secret にすることで、`main` 以外のブランチのワークフローから読めないようにしている
- back/front それぞれの GitHub Environment（back: `production` / front: `production`）に Required reviewer と Deployment branch policy（`main` 限定）が設定されており、承認できるメンバーであること
- back の Environment に ECS/ECR 関連 secrets（`AWS_OIDC_ROLE_ARN`、`ECR_RAILS_URL`、`ECR_NGINX_URL`、`ECS_CLUSTER_NAME`、`ECS_SERVICE_NAME`、`ECS_TASK_FAMILY` 等）が登録済みであること
- front の Environment に `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID` / `VERCEL_TOKEN` が登録済みであること（未登録だと dispatch 自体は成功するが front 側のジョブが必ず失敗する）

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
   git submodule status                  # detached/dirty なサブモジュールがないか確認
   git add back front                    # 更新があった方だけでも可
   git diff --cached --submodule=log     # 各ポインタが「進んでいる」ことを目視確認（巻き戻しがないか）
   git commit -m "release: back/front submodule ポインタ更新"
   git push -u origin release/YYYY-MM-DD
   gh pr create --title "Release YYYY-MM-DD" --body "..."
   ```
   - `deploy.yml` は gitlink の後退（GitHub の compare API で `behind`）または分岐（`diverged`）を検知すると、push されたコミット範囲のコミットメッセージに `[rollback]`（大文字小文字問わず）が含まれるかどうかで挙動を分ける。含まれていれば `::warning::` を出して続行し、含まれていなければ `::error::` を出して fail し dispatch しない。ロールバック目的の意図的な後退は、下記「ロールバック手順」に従ってコミットメッセージに必ず `[rollback]` を含めること
   - 併せて、更新後の gitlink SHA が対象リポジトリの `main` から到達可能であること（compare API `main...NEW` が `identical` または `behind`）も検証される。fork 由来の未マージコミットを指すポインタはここで弾かれる
4. 親リポの PR をレビューし、`main` へマージする
5. マージ後、`.github/workflows/deploy.yml` の実行を親リポの Actions タブで確認する
   - 変更があったリポジトリ（back/front）に対してのみ dispatch のログ（`::notice`）が出力される
6. dispatch されたリポジトリの Actions タブを開き、起動されたワークフロー（back: `ECS deploy` / front: `Deploy`）を確認する
   - `environment: production` の承認待ち状態になっているので、Required reviewer が承認する
   - 親リポの `deploy.yml` は commit 単位で concurrency を分離している（`group: deploy-sync-${{ github.sha }}`）。短時間に連続してマージすると複数の run が同時に dispatch されうるため、承認待ちの run が複数並んでいる場合は対象の SHA が今回リリースしたい commit と一致しているか確認してから承認すること
7. 承認後、デプロイが完了するまで進捗を確認する
   - back: ECS サービスが安定化（`deployments` が1件、`rolloutState` が `COMPLETED`、かつ新しいタスク定義に一致）するまで最大20分ポーリングされる。`rolloutState` が `FAILED`（circuit breaker によるロールバックの可能性が高い）になった場合は即座に失敗する。それ以外の失敗はタイムアウトでジョブが赤くなる
   - front: `vercel build --prod` → `vercel deploy --prebuilt --prod` 後、ヘルスチェック（`curl` によるデプロイ先URLへのリクエスト）が実行される。失敗時はジョブが赤くなり、コミットステータス（`deploy/vercel-production`）も `failure` になる
8. 両サービスとも正常完了したことを確認して完了とする

## ロールバック手順

**注意**: 親リポの `main` には branch protection（PR必須・管理者にも適用）が設定されているため、`main` への直接 `push` は拒否される。ロールバックも通常リリースと同様に必ず PR 経由で行うこと。

**`[rollback]` マーカーが必須**: `deploy.yml` は gitlink の後退（`behind`）または分岐（`diverged`）を検知すると、push されたコミット範囲のコミットメッセージに `[rollback]`（大文字小文字問わず）が含まれているかで挙動を分ける。

- 含まれる → `::warning::` を出して続行し、通常どおり dispatch する
- 含まれない → `::error::` を出して失敗し、dispatch しない（意図しないダウングレードを止める fail-closed 設計）

そのため、以下の一括ロールバック・片方だけのロールバックのいずれでも、コミットメッセージに必ず `[rollback]` を含めること。squash マージ・マージコミットのどちらでマージしても、ブランチ側のコミットのいずれかにマーカーが含まれていれば検出される（push イベントのコミット範囲全体が検査対象のため）。

マーカーを付け忘れたまま `main` へマージしてしまうと、submodule ポインタ自体は更新されるが親リポの `deploy.yml` が `::error::` で失敗し、dispatch は行われない（実デプロイは走らない）。リカバリ方法は次のとおり。

- マージ前に気づいた場合: ロールバック用ブランチのコミットメッセージを amend して `[rollback]` を追加してから push し直す（force-push）
- マージ後に気づいた場合: submodule ポインタは既に `main` 上で意図した値になっているため、同じ内容の PR を作り直しても gitlink に差分がなく再 dispatch されない。対象リポジトリ（back/front）で直接ワークフローを手動実行する
  ```bash
  gh workflow run <ファイル名> --repo <repo> --ref main -f sha=<戻したいSHA>
  # 例: gh workflow run autodeploy.yml --repo Alnoir-0011/algo_sangaku_back --ref main -f sha=<戻したいSHA>
  ```

### 親リポ側からの一括ロールバック（推奨）

直前のリリース（マージコミット）を revert し、PR を作成してマージする。同じ `deploy.yml` が古い（ロールバック先の）SHA で両サービスに再度 dispatch する。

`git revert -m 1 --no-edit` はメッセージを自動生成するため `[rollback]` が入らない。revert 後に `git commit --amend` でメッセージに追記する。

```bash
git checkout main && git pull
git checkout -b rollback/YYYY-MM-DD-revert
git revert -m 1 --no-edit <マージコミットのSHA>
git commit --amend -m "$(git log -1 --pretty=%B)" -m "[rollback]"
git push -u origin rollback/YYYY-MM-DD-revert
gh pr create --title "Rollback: revert <マージコミットのSHA>" --body "..."
```

親リポの必須承認数は 0 のため、緊急時は self-merge で問題ない（レビューを待てない場合はその旨を PR に明記する）。

以降の手順（Actions 確認・承認）は通常リリース手順の 5〜8 と同じ。

### 片方だけをロールバックしたい場合

親リポでの revert は back/front 両方のポインタを戻してしまうため、片方だけ戻したい場合は該当する gitlink のみを対象コミットに戻すコミットを作成する。コミットメッセージに `[rollback]` を含めること。

```bash
git checkout main && git pull
git checkout -b rollback/back-only
git -C back checkout <戻したいコミットSHA>    # 対象サブモジュールのみ移動
git add back
git commit -m "rollback: back のみ直前バージョンに戻す [rollback]"
git -C back checkout main                     # 作業後は detached HEAD を解消しておく（放置すると次回リリース時に誤って古い SHA を再記録するおそれがある）
git push -u origin rollback/back-only
gh pr create --title "Rollback: back のみ直前バージョンに戻す" --body "..."
```

## トラブルシューティング

| 症状 | 原因の見当 | 対処 |
| --- | --- | --- |
| 親リポの `deploy.yml` 自体が失敗する（dispatch呼び出しでエラー） | `DEPLOY_DISPATCH_TOKEN` の手動失効・権限変更・GitHubアカウント設定変更による無効化（PAT自体は無期限で発行しているため期限切れではない）、権限不足、対象リポジトリ名/ワークフローファイル名の変更 | トークンを再発行し Secrets を更新する。対象ワークフローのファイル名が変わっていないか確認する |
| dispatch はされたが、対象リポジトリの Actions に何も出てこない | ワークフロー名・ファイル名の指定間違い、`--ref main` が対象ブランチに存在しない | `gh workflow list --repo <repo>` で対象ワークフローの状態を確認する |
| 承認待ちのまま進まない | Required reviewer が誰も承認していない、承認者に通知が届いていない | 対象リポジトリの Actions タブ → 該当 run → `Review deployments` から手動で承認する。承認者・エスカレーション先は下記「緊急連絡フロー」を参照 |
| back のデプロイが「service did not stabilize」でタイムアウトする | ECS タスクが `unhealthy` を繰り返している、リソース不足 | ECS コンソールでタスクのイベントログ・CloudWatch Logs を確認する。必要なら手動でロールバック手順を実施する |
| back のデプロイが「deployment rollout failed」で即座に失敗する（20分の stabilize 待ちに入らない） | ECS の deployment circuit breaker がロールバックを発動した可能性が高い（新タスクが unhealthy と判定された） | ECS コンソールでタスクのイベントログ・CloudWatch Logs を確認する。必要なら手動でロールバック手順を実施する |
| front のヘルスチェックが失敗する | Vercel 側のビルド・デプロイは成功したがアプリが起動していない、環境変数不足 | Vercel ダッシュボードでデプロイログを確認する。必要ならロールバック手順を実施する |
| 指定した SHA が ancestor チェックで弾かれる（front: 「is not an ancestor of main」／back: 「は origin/main の履歴に含まれていません」。メッセージ文言はリポジトリにより異なる） | fork 由来の未マージコミットや、まだ push されていないローカルコミットの SHA を指定した | `main` に実際にマージされたコミットの SHA を指定し直す |
| front で「required check '...' is missing or not successful」エラーになる | 対象 SHA の必須チェック（build / lint / componentstest / coverage / e2etest chromium・firefox・webkit）のいずれかが最新実行で success になっていない（実行中・check-runs が0件の場合も含む） | 対象コミットの CI が完了し全て成功していることを確認してから再実行する（back 側にはこの検証はない点に注意） |
| 親リポの `deploy.yml` が「pointer moved backwards or diverged」で失敗する | ロールバック用コミットのメッセージに `[rollback]` が含まれていない。または `git submodule update` 忘れ・detached HEAD の取り違え等による意図しない後退 | コミットメッセージを確認する。ロールバックが目的なら `[rollback]` を含むコミットを作り直す（上記「ロールバック手順」参照）。意図しない後退なら PR を修正して正しいポインタに直す。back/front どちらか一方の検証失敗でも `detect` ジョブ全体が失敗し、もう一方に変更があっても dispatch されない点に注意 |
| 親リポの `deploy.yml` が「is not reachable from ...#main」で失敗する | submodule 側で未 push のローカルコミットや、fork 由来の未マージコミットを指すポインタを親リポにコミットしてしまった | submodule を対象リポジトリの `main` 上に実在するコミットへ checkout し直してから、親リポ側のコミットをやり直す |
| dispatch には成功したがそのまま放置され、後から同じ SHA で再 dispatch したい | Required reviewer の承認忘れ、対象リポのワークフローが誤ってキャンセルされた等 | (a) 親リポの `deploy.yml` の該当 run を Actions 画面から「Re-run all jobs」する（同じ before/after で再実行され、変更がなかった側は再びスキップされる）。(b) もしくは対象リポで直接 `gh workflow run <ファイル名> --repo <repo> --ref main -f sha=<sha>` を手動実行する |

## 緊急連絡フロー

本プロジェクトはリポジトリオーナー（@Alnoir-0011）1人のみが開発・レビュー・デプロイ承認を行う個人開発である。

- 承認者（Required reviewer）: リポジトリオーナー @Alnoir-0011 単独（back/front 双方の `production` Environment とも同一人物）
- 連絡先（障害時のエスカレーション先）: なし（個人開発のため、第三者へのエスカレーション先は存在しない）
- **単一障害点である点に注意**: 承認者が1人のみのため、@Alnoir-0011 が対応できない間はデプロイの承認・ロールバックの承認のいずれも進行しない。長期不在が見込まれる場合は、事前にリリースを控えるなど運用でカバーすること

## 既知の制約とリスク

- **親リポの write 権限 ≒ `DEPLOY_DISPATCH_TOKEN` の入手**: 親リポの `main` は PR 必須だが必須承認数は 0 のため、`deploy.yml` を書き換える PR を自己マージすれば、そのジョブに Secrets `DEPLOY_DISPATCH_TOKEN` を渡して外部に送信できてしまう。個人開発でレビュアーが1人しかいない構造上、コードでは解消できない制約である
- **緩和策（実施済み）**: back/front 双方の `production` Environment に Required reviewer が設定されているため、PAT が漏洩しても「デプロイのトリガー」までは可能だが「デプロイの完了」はできない
- **緩和策（実施済み）**: 親リポの Environment `deploy-dispatch` は Deployment branch policy を `main` 限定にしており、`main` 以外のブランチのワークフローからは `DEPLOY_DISPATCH_TOKEN` を読めない
- **PAT の性質**: `DEPLOY_DISPATCH_TOKEN` は個人アカウントに紐づく無期限の fine-grained PAT である。本来は GitHub App（installation token・短命）に置き換えるのが本筋であり、将来的な改善候補とする
- **gitlink 検証は back/front が public リポジトリであることに依存**: `detect` ジョブの後退・分岐検証／main 到達可能性検証は `DEPLOY_DISPATCH_TOKEN` ではなく既定の `GITHUB_TOKEN` で back/front の compare API を呼んでいる。これは back/front が public リポジトリだから通っている権限であり、将来どちらかを private 化すると compare API が 404 になり検証が機能しなくなる（その場合は検証用トークンを PAT に切り替える等の対応が必要になる）

## 参考

- [Alnoir-0011/algo_sangaku#38](https://github.com/Alnoir-0011/algo_sangaku/issues/38) — 本仕組みの詳細設計
- [Alnoir-0011/algo_sangaku_back#296](https://github.com/Alnoir-0011/algo_sangaku_back/issues/296) — back 側トリガー変更
- [Alnoir-0011/algo_sangaku_front#100](https://github.com/Alnoir-0011/algo_sangaku_front/issues/100) — front 側デプロイワークフロー新規追加
- [Alnoir-0011/algo_sangaku_back#300](https://github.com/Alnoir-0011/algo_sangaku_back/issues/300) — Environment `production` の Required reviewer / Repository Rulesets 設定
- [Alnoir-0011/algo_sangaku_back#301](https://github.com/Alnoir-0011/algo_sangaku_back/issues/301) — OIDC 信頼ポリシーの絞り込み
