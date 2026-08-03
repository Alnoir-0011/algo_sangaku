## Git ブランチ運用ルール

`front/` と `back/` はそれぞれ独立したサブモジュールリポジトリ。**front/back のコードを変更する場合は、必ず各サブモジュール内でブランチを切ってから行う。親リポジトリでブランチを切って front/back のコードを変更してはいけない。**

```bash
# front を変更する場合
cd front && git checkout -b <branch-name>

# back を変更する場合
cd back && git checkout -b <branch-name>
```

**ただし、親リポジトリ自身のファイルを変更する場合は親リポジトリでブランチを切る。** 対象は `.github/`・`doc/`・`.claude/`・`CLAUDE.md` などのファイルと、submodule ポインタ（gitlink）の更新。ポインタ更新の具体的な手順は `doc/release.md` を参照する。

```bash
# 親リポ自身の変更（deploy.yml の修正、submodule ポインタ更新など）
cd <親リポ> && git checkout -b <branch-name>
```

いずれの場合も、`git checkout -b` の直前に `pwd` で作業ディレクトリを確認すること。永続シェルの cwd がずれたまま意図しないリポジトリにブランチを作る事故が起きやすい。

### git / gh コマンド実行前のブランチ確認

**`git commit` / `git push` / `gh pr create` などを実行する前に、必ず `git branch` で現在のブランチを確認する。**
main ブランチに直接コミット・push することは絶対に禁止。

```bash
# コミット・push・PR 作成の前に必ず確認
git branch   # * が main を指していないことを確認してから実行
```

## GitHub Issue / Pull Request ルール

### Issue 作成

issueを立てる際は `gh` コマンドを使い、**algo_sangaku** プロジェクトに紐付けて作成する。

```bash
# issue作成後、algo_sangaku プロジェクトに追加する
gh issue create --title "..." --body "..."
gh project item-add 2 --owner <owner> --url <issue-url>
```

#### プロジェクトへの追加ルール

- **GraphQL API（`gh api graphql`）は使用しない。** `gh project item-add` コマンドのみを使う。
  - GraphQL の `addProjectV2ItemById` mutation はコマンド成功を返してもボードに反映されないことがある。
- 追加後は必ず `gh project item-list 2 --owner <owner> --limit 200` で追加を確認する。
- プロジェクトボードに **Status が未設定** のアイテムはビューに表示されない。追加後に UI またはコマンドで Status（例: `Backlog`）を設定すること。

### Issue / PR のテンプレート

**Issue と PR の本文は、必ず対象リポジトリのテンプレートに沿って記述する。**

テンプレートは各リポジトリの `.github/ISSUE_TEMPLATE/` および `.github/pull_request_template.md` に定義されている。作成前に必ず確認すること。

```bash
# テンプレートを確認する
ls <repo>/.github/ISSUE_TEMPLATE/
cat <repo>/.github/pull_request_template.md
```

テンプレートが存在しない場合は自由形式で記述してよい。
