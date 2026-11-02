# MacFiles development and upstream updates

`main` is the integrated macOS port. `upstream/main` tracks Files Community's Windows source; `origin/main` is this fork on GitHub. Fetching upstream does not change the working tree. Upstream C# changes do not automatically implement Swift features: review portable behavior changes separately in `src/Files.Mac`.

The sole runnable app is `MacFiles.app` at the primary checkout root. It, Finder metadata, Swift build products, and native work/dist folders are ignored. Source commits do not replace the running application. Do not commit app bundles or rewrite history to remove older bundles.

## Start an isolated feature

From this repository:

```sh
python3 scripts/macfiles-workflow.py feature cloud-status
```

This creates `feature/cloud-status` from local `main` in a sibling `MacFiles-worktrees/feature-cloud-status` directory. Work there, commit source changes, and run `swift build` / `swift test` inside `src/Files.Mac`. The primary checkout and app remain untouched. Do not use build.py for feature previews: it creates an app bundle.

For the full test suite, set `MACFILES_SFTP_TEST_PYTHON` to a Python interpreter with Paramiko. The existing primary checkout has one at `src/Files.Mac/work/ssh-test-env/bin/python`. Set `MACFILES_RENDER_DIR` to an existing output directory to also render dialog checks. Review skipped tests rather than treating a skipped integration test as verified.

## Bring in Files upstream

```sh
python3 scripts/macfiles-workflow.py sync
```

This fetches upstream and merges its exact fetched commit into a new `sync/files-<commit>` worktree based on local `main`. Conflicts stay in that worktree. Resolve and commit there, or run `git merge --abort` there. Inspect changes to shared assets, translations, contracts, and Windows behavior; implement relevant native behavior deliberately. Run native checks before promoting. A Mac cannot validate the Windows solution; use Windows CI for that.

## Promote tested changes

Finish and commit your feature/integration work. In the primary checkout, ensure `git status --short` is empty, then:

```sh
git switch main
git merge --ff-only feature/cloud-status
```

Use the actual `sync/files-...` branch name for an upstream sync. If fast-forward fails because main advanced, merge main into the feature worktree, resolve, and retest. Never force-reset main to make promotion work.

Only when publishing a new runnable version, quit MacFiles and run in the primary checkout:

```sh
python3 src/Files.Mac/build.py --universal
```

This replaces the one root app. A guard rejects the default bundle output in secondary worktrees. `git push origin main` publishes reviewed commits; this setup does not push automatically. Remove a finished, clean worktree using `git worktree remove <path>`, then optionally delete its merged local branch with `git branch -d <branch>`.

Local configuration uses origin as the default push remote, fast-forward-only pulls, three-way conflict context, and recorded conflict resolutions. Review reused resolutions before committing.

## Upstream sync: 2026-11-02

Included upstream through `7f7f67c5e` (v4.3.2): Windows SDK BuildTools update, shell-service migration, location catalog/live-notification migration, and release metadata. The four commits touch no files in `src/Files.Mac`. They update the retained Windows reference implementation; they do not convert the native port to the Windows server architecture.

`backup/pre-upstream-2026-11-02` preserves the committed 0.7.4 port source before repository cleanup/integration. The root app stays on 0.7.4 because this sync changes no native runtime behavior.
