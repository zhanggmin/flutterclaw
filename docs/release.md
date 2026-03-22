# Creating a new Android release

This guide covers bumping the app version, **writing a changelog by comparing with the previous release**, building a release APK, and publishing it as a downloadable GitHub Release.

Prerequisites:

- [Flutter](https://docs.flutter.dev/get-started/install) SDK on your PATH
- A clone of this repository
- For uploading releases: [GitHub CLI](https://cli.github.com/) (`gh`) authenticated (`gh auth login`), or use the GitHub web UI instead

---

## Language policy (commits, PRs, release text)

**All contributor-facing and release text must be in English.**

| Area | Requirement |
|------|-------------|
| **Git commits** | Subject and body in English (e.g. `chore: bump version to 1.0.9+10`). |
| **Pull requests** | Title and description in English; keep the main PR thread for that change in English so history and reviews stay consistent. |
| **Changelog & GitHub Releases** | Release notes and the summarized changelog (§2) in English. |
| **Store listings** | “What’s new” / release notes for this app: English unless a store requires a localized field (then mirror the English source). |

End-user text inside the app is localized via ARB files; this policy applies to **metadata** (git, GitHub, release tooling), not to UI translations.

---

## 1. Version bump

The **single source of truth** for Android `versionName` and `versionCode` is `pubspec.yaml`:

```yaml
version: 1.0.8+9
```

- **Before `+`:** user-visible version (`versionName` on Android), e.g. `1.0.8` — use [semantic versioning](https://semver.org/) as appropriate (patch/minor/major).
- **After `+`:** integer build number (`versionCode` on Android), e.g. `9` — **must increase** for every upload to Google Play; for GitHub-only releases, still bump it so installs are ordered correctly.

**Steps:**

1. Edit `pubspec.yaml` and set a new `version`, for example:
   - From `1.0.8+9` → `1.0.9+10` (new patch and higher build number).
2. Run:

   ```bash
   flutter pub get
   ```

3. Commit the change (recommended so the tag matches the tree users build from):

   ```bash
   git add pubspec.yaml
   git commit -m "chore: bump version to 1.0.9+10"
   ```

`android/app/build.gradle.kts` reads `versionName` and `versionCode` from Flutter; you do not need to edit Gradle for a normal bump.

---

## 2. Changelog (compare with the previous version)

Before you build or publish, **prepare the release notes** by summarizing what changed since the last shipped version. That baseline should be the **previous release tag** (or commit), not an arbitrary point in history.

**Why:** Users and store listings need to know what is new; comparing against the prior version keeps the changelog accurate and reviewable.

**Steps:**

1. **Identify the previous release** (same scheme as your tags, e.g. `v1.0.8`):

   ```bash
   git fetch --tags
   git tag -l 'v*' --sort=-v:refname | head -10
   ```

   Pick the tag that corresponds to the **last published** version (the one immediately before the version you are about to release).

2. **Generate a raw list of commits** between that tag and your current branch (replace `v1.0.8` and adjust the range if your tag names differ):

   ```bash
   git log v1.0.8..HEAD --oneline --no-merges
   ```

   For a slightly more readable summary:

   ```bash
   git shortlog v1.0.8..HEAD --no-merges
   ```

3. **Turn that into human-readable notes in English** (see **Language policy** above): group fixes vs features, drop noise (chore-only bumps if you prefer), and write the text you will paste into the GitHub Release description (and Play Store “What’s new” if applicable).

4. **Optional — GitHub compare in the browser:** open  
   `https://github.com/<org>/<repo>/compare/<previous-tag>...HEAD`  
   to review merged PRs and file diffs alongside the git log.

If there is **no earlier tag**, use the first public commit or the branch point you consider “v1.0.0”, or state clearly in the notes that this is an initial release.

Use the finished changelog as the body for `gh release create --notes` (see §4) or paste it into the release form on GitHub.

---

## 3. Build the release APK

From the repository root:

```bash
flutter build apk --release
```

**Output path:**

```text
build/app/outputs/flutter-apk/app-release.apk
```

**Signing:**

- If `android/key.properties` exists (see `android/app/build.gradle.kts`), the release build uses your Play/App signing keystore.
- If it does not exist, release builds still succeed but are signed with the **debug** keystore — fine for internal testing; use your real keystore for store or wide distribution.

Optional: confirm the version on the built artifact (example):

```bash
# macOS: path to aapt may vary; or inspect the APK in Android Studio
```

---

## 4. Publish a GitHub Release with the APK

### Option A: GitHub CLI (recommended)

1. Push your version-bump commit (and branch) if needed:

   ```bash
   git push origin <your-branch>
   ```

2. Create a tag that matches the release (example for `1.0.9`):

   ```bash
   git tag v1.0.9
   git push origin v1.0.9
   ```

3. Create the release and attach the APK (rename the asset for clarity):

   ```bash
   cp build/app/outputs/flutter-apk/app-release.apk flutterclaw-1.0.9.apk

   gh release create v1.0.9 \
     --title "v1.0.9" \
     --notes-file CHANGELOG.md \
     flutterclaw-1.0.9.apk
   ```

   Prepare `CHANGELOG.md` from §2 (changelog vs previous version), or use `--notes "..."` with inline text.

Users will see `flutterclaw-1.0.9.apk` under **Assets** on the release page.

**Notes:**

- Replace `v1.0.9` and filenames with the same version you put in `pubspec.yaml` (the part before `+`).
- You can add `--prerelease` or `--draft` if needed.

### Option B: GitHub web UI

1. Push your commits and create a tag (`v1.0.9`) as above, or create the tag when drafting the release in the UI.
2. Open the repository on GitHub → **Releases** → **Draft a new release**.
3. Choose the tag, set title and **paste the changelog** (from §2) into the description, then **Attach binaries** and upload `app-release.apk` (optionally renamed, e.g. `flutterclaw-1.0.9.apk`).
4. Publish the release.

---

## Checklist

| Step | Action |
|------|--------|
| 1 | Increase `version` in `pubspec.yaml` (`name+build`) |
| 2 | `flutter pub get` and commit `pubspec.yaml` |
| 3 | **Changelog:** compare `previous-tag..HEAD` (§2), draft notes in **English** for GitHub / store |
| 4 | `flutter build apk --release` |
| 5 | Tag, push tag, `gh release create` (or web UI) with APK attached and notes from §2 |

**Language:** Use English for all commits and PRs tied to the release, plus release notes (see **Language policy**).

---

## Troubleshooting

- **Build fails:** Run `flutter doctor` and fix reported issues; ensure Android toolchain is installed.
- **Wrong version inside the app:** Confirm `pubspec.yaml` was saved and rebuild after the bump; clean if needed: `flutter clean && flutter pub get && flutter build apk --release`.
