---
name: megaphone-release
description: Prepare, validate, publish, and verify Megaphone releases. Use when the user asks to release Megaphone, choose or bump its version, update release notes, validate release readiness, create a stable vX.Y.Z tag, inspect the moving Dev release, publish Megaphone.dmg, verify updater compatibility, or confirm that megaphone.kuber.studio reflects the latest GitHub release.
---

# Megaphone Release

Release Megaphone through its tag-driven GitHub Actions pipeline. Treat `CHANGELOG.md` as the stable release-notes source. A `vX.Y.Z` tag builds `Megaphone.dmg`, optionally signs and notarizes it, publishes the stable GitHub release, and asks the Pages workflow to hydrate the website with that release. Each push to `main` separately replaces the `dev` prerelease and `Megaphone-Dev.dmg`.

## Guardrails

- Work only in `Kuberwastaken/megaphone`. Do not infer repository identity from a remote named `origin`; inherited clones may still use that name for FreeFlow.
- Preserve unrelated changes and never use destructive cleanup.
- Keep sequential release-prep commits. Stage only deliberate files.
- Do not push a branch or tag, publish a release, or move the `dev` tag without explicit user authorization.
- Require explicit confirmation of the stable version and changelog before tagging.
- Do not hand-build and upload a stable DMG. The tagged workflow is the source of truth.
- Never expose signing or notarization secrets. Confirm only whether required GitHub secrets are configured through workflow behavior.

## Prepare a stable release

1. Inspect the repository and fetch the Megaphone remote:

   ```bash
   git status --short --branch
   git remote -v
   git fetch <megaphone-remote> --tags --prune
   git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname
   ```

   Choose `<megaphone-remote>` by matching its URL to `Kuberwastaken/megaphone`, not by its name. Stop if the worktree contains substantial unrelated work.

2. Use the newest stable semver tag reachable from the release branch as the comparison boundary. Inspect both merge-level and individual history:

   ```bash
   git log --first-parent --reverse --oneline <previous-tag>..HEAD
   git log --reverse --oneline <previous-tag>..HEAD
   git diff --stat <previous-tag>..HEAD
   git diff --name-status <previous-tag>..HEAD
   ```

3. Choose the next version:

   - Patch: fixes, reliability, polish, or small compatible improvements.
   - Minor: a notable new user-facing capability.
   - Major: breaking behavior or compatibility.

4. Update both version keys in `Info.plist` to the target version:

   - `CFBundleShortVersionString`
   - `CFBundleVersion`

   The workflow stamps them again, but keeping source synchronized makes Dev builds, About, and the next release proposal accurate.

5. Add the target section above the previous release in `CHANGELOG.md`. Describe everything user-visible since the previous tag, including merged work that predates the prep commit. Use only relevant headings among `Added`, `Changed`, `Improved`, and `Fixed`. Avoid commit hashes, internal implementation narration, and claims not supported by the diff.

6. Validate on the companion Mac because Megaphone requires the macOS 26 SDK:

   ```bash
   .agents/skills/megaphone-release/scripts/megaphone-release-check.sh <version>
   git diff --check
   make clean
   make test
   make ARCH="$(uname -m)" APP_NAME="Megaphone Dev" BUNDLE_ID=studio.kuber.megaphone.dev CODESIGN_IDENTITY=-
   codesign --verify --deep --strict "build/Megaphone Dev.app"
   ```

7. Commit the prep as `Prepare v<version> release`. Show the exact changelog and version diff to the user before tagging.

## Publish

After explicit approval:

```bash
git push <megaphone-remote> <release-branch>:main
git tag -a v<version> -m "Megaphone v<version>"
git push <megaphone-remote> v<version>
```

Do not tag a commit that is not on Megaphone’s remote `main`. Watch `.github/workflows/release.yml` through completion.

## Verify the shipped release

Confirm all of the following:

- GitHub Release `v<version>` is published, stable, and marked latest.
- Its only expected app artifact is `Megaphone.dmg`; the asset is non-empty and downloadable.
- Release notes came from the matching changelog section and include the macOS 26 requirement.
- The workflow ran tests, built the universal app, and completed the configured signing/notarization path.
- The DMG contains `Megaphone.app` with version `<version>` and bundle ID `com.kuberwastaken.megaphone`.
- `UpdateManager` can see the semantic release and locate the `.dmg` asset. When practical, test update discovery from the previous installed stable version.
- The Pages workflow completes and `https://megaphone.kuber.studio` shows the same stable version and download URL.
- The moving `dev` prerelease remains separate and is not marked latest.

If any verification fails, do not silently retag or replace a stable release. Diagnose the failed stage and ask before mutating published state.

## Helper

Run `.agents/skills/megaphone-release/scripts/megaphone-release-check.sh <version>` after preparing `Info.plist` and `CHANGELOG.md`. It checks repository identity, semver and tag availability, synchronized source versions, changelog extraction, Megaphone artifact names, workflow triggers, updater wiring, website hydration, and release ancestry.
