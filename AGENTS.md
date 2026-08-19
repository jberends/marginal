# AGENTS.md

Guidance for automated agents and contributors working in this repository.

## App icon: beta vs production

Marginal ships two app-icon sets in `Sources/Marginal/App/Assets.xcassets`:

- **`AppIcon`** — the production icon.
- **`AppIconBeta`** — the development/beta icon (the "m/β" mark). It is generated
  from the designed source `assets/icon/marginal-icon-3-beta_1024.png` by
  `scripts/make-beta-icon.sh` (resizes into every macOS slot).

`ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml` selects between them, and it
**changes over the life of a branch**: `AppIconBeta` while a feature is in development,
flipped back to `AppIcon` when the feature is accepted, so `main` always sits
release-shaped. The feature workflow and release checklist below each own one half of
that flip. Whichever way you set it, run `xcodegen generate` afterwards.

The side-by-side build (`scripts/build-sidebyside.sh`) forces `AppIconBeta` on the
command line regardless of `project.yml`, and installs a distinct, ad-hoc-signed
`/Applications/Marginal-<version>.app` (bundle id
`com.jochemberends.marginal.v<version>`) so a beta build can run next to the released
app. Because it overrides the setting, that script **cannot** verify the production
icon — only a plain Release build can (release checklist step 3).

If you change the designed beta art, replace
`assets/icon/marginal-icon-3-beta_1024.png` and re-run `scripts/make-beta-icon.sh`.

## Self-updating: direct downloads only, never the App Store

The same build ships to both channels, so `UpdateChecker.channel` decides at runtime by looking
for `Contents/_MASReceipt/receipt`. `UpdateChecker.canSelfUpdate` is true only for `.direct`.

On an App Store install the "Check for Updates…" menu item is **omitted**, and
`UpdateInstaller.downloadAndInstall` refuses as a second line of defence. Three independent
reasons, any one of which is enough:

1. The update swaps the app bundle, which destroys `_MASReceipt/receipt` — the app can then no
   longer prove it was purchased.
2. The sandbox blocks every step. It refuses to launch Terminal, and the handoff `.command` is
   quarantined on write, so Gatekeeper reports it as "damaged".
3. Apple requires App Store apps to update through the App Store.

It is omitted rather than redirected to the App Store on purpose: review lag means the App Store
build is routinely behind the newest GitHub release, so asking GitHub gets an answer that does not
apply to that install. Reporting "0.10.0 is available" to someone who can only get 0.9.0 is worse
than saying nothing.

**Two traps in `UpdateInstaller` that bite if you refactor it:**

- The downloaded file must be moved **synchronously inside** the `URLSession` completion handler.
  URLSession deletes it the moment that closure returns, so hopping to another actor first loses
  the download — which surfaces as `CFNetworkDownload_xxxxx.tmp couldn't be moved … the former
  doesn't exist`.
- The `.command` needs its `com.apple.quarantine` attribute stripped after writing
  (`clearQuarantine`). Without it Gatekeeper refuses the script and the error says "damaged",
  which sounds like a corrupt file and is not.

## Feature workflow

Every feature-sized change runs on its own branch, ships a build a human can actually drive,
and lands squashed. In order:

1. **Branch, then open the PR early.** `git checkout -b <topic>-<version>` off `main`, and
   `gh pr create` as soon as there is a first commit. The PR body is where the reasoning
   lives — what was broken, why the fix is shaped the way it is, what was ruled out. Open it
   while the work is in progress, not as a formality at the end.
2. **Switch the app icon to beta.** Set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIconBeta` in
   `project.yml` and run `xcodegen generate`. A development build must never wear the
   production mark; see the icon section above.
3. **Propose the next logical version** — minor bump for a feature, patch for a fix — and say
   which you picked and why before changing anything. Bump `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` (integer) in `project.yml`, `xcodegen generate`, and open the
   changelog section under that number headed **`— Unreleased`**. It earns a date only when
   the release is actually cut.
4. **Develop under the normal superpowers flows**: brainstorm before creative work,
   test-driven development for each feature and bugfix, systematic debugging before proposing
   a fix, and verification before claiming anything passes. Commit in logical slices rather
   than one lump, with conventional-commit subjects carrying a scope (`fix(editor):`,
   `docs(changelog):`) and a body explaining the why.
5. **Install a build a human can test:** `scripts/build-sidebyside.sh` installs
   `/Applications/Marginal-<version>.app` (ad-hoc signed, beta icon forced, version-suffixed
   bundle id) alongside the released app. Then **ask for a human pass** and say specifically
   what needs eyes — anything the tests cannot reach, such as caret placement, selection and
   drag, live resize, scrolling, or print preview. Green tests and offscreen bitmaps prove the
   layout maths, not that the app is usable.
6. **On acceptance, flip the icon back** to `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and
   run `xcodegen generate`, so `main` is always release-shaped.
7. **Land it squashed** — squash-merge the PR, or rebase the branch onto `main` as a single
   commit. Then, if this version ships, follow the release checklist below.

**Never delete an app from `/Applications` because the name looks stray.** The Mac App Store
install carries the same bundle id as the direct download, so when both are present Finder
names one of them `Marginal 2.app` — which looks like leftover junk and is not. Identify a
build by `Contents/_MASReceipt/receipt` (present only on the App Store copy) and by owner
(`root:wheel` for App Store, `jochem:admin` for a direct download), never by filename.
Removing it destroys the receipt that proves the app was purchased. Only
`Marginal-<version>.app`, the ad-hoc-signed side-by-side build, is safe to delete.

## Release checklist (production)

Before cutting a production release, do these in order. Steps 1 and 2 are usually already
done — the feature workflow bumps the version when the branch opens and flips the icon back
on acceptance — so **confirm** them rather than doing them twice:

1. **Confirm the version** in `project.yml`: `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` (integer). If the branch never set them, set them now and run
   `xcodegen generate`.
2. **Confirm the app icon is production:** `ASSETCATALOG_COMPILER_APPICON_NAME` reads
   **`AppIcon`**, not `AppIconBeta`. (This is the one icon reference to flip — the beta icon
   is dev-only and must never ship in a production/App Store build.) If you change it, run
   `xcodegen generate`.
3. **Verify the icon** in a Release build: `Contents/Resources/Assets.car` should
   render the production `AppIcon`, not the beta mark. Confirm in Finder/Dock.
4. Run the full test suite: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`.
5. **Date the changelog:** replace that version's `— Unreleased` heading with the release
   date.
6. **Write the App Store copy** to `marketing/appstore/whats-new-<version>.md`, in three
   paste-ready blocks. Count the characters with a script and record the counts in the file —
   do not estimate, both fields are hard limits:
   - **Promotional text** (170 characters). Always opens
     `Marginal - Markdown editor that renders as you type. Now …`, then what this version
     adds. Apple lets this be changed later without a new build.
   - **What's New in This Version** (4,000 characters), with the release's headline change
     first. Three habits App Review sends notes back for, all avoidable: opening on a version
     number, writing only "bug fixes and performance improvements", and mentioning other
     platforms or pricing.
   - **App Review notes**: what did and did not change in data handling, entitlements,
     sandboxing, and network use, plus a one-line reproduction so the reviewer can see the
     headline change without hunting for it.
7. **Tag and publish the GitHub release** once the release commit is on `main`:
   `git tag -a v<version>`, push the tag, then `gh release create v<version>` with notes
   written for users and a link to `CHANGELOG.md` at that tag. Write the notes **first**:
   pushing the tag fires `.github/workflows/release.yml`, which creates a release with
   `--generate-notes` if none exists yet — a raw commit list where your notes should be.

   That workflow also builds Release (ad-hoc signed; the runner has no KE-works
   certificate), zips it, and attaches it as `Marginal-<version>.zip`. **Confirm the asset
   landed** — the run takes about two minutes, so `gh release view` straight after tagging
   shows an empty release and means nothing. The zip is what makes direct-download updates
   work: `UpdateChecker` reads `releases/latest` and announces any newer tag, while
   `UpdateInstaller` takes the first asset whose name ends in `.zip`. A release without one
   tells every direct-download user an update exists and then fails with
   `noDownloadableAsset`. App Store installs never see the menu item at all.
8. Remove any local side-by-side beta build if it would confuse distribution:
   `rm -rf /Applications/Marginal-<version>.app` (ad-hoc signed, local only —
   never distribute it). Read the warning in the feature workflow first: only the
   `Marginal-<version>.app` builds are yours to delete.
9. Archive and submit through the normal App Store / notarization flow.

After the release, the next feature branch switches
`ASSETCATALOG_COMPILER_APPICON_NAME` back to `AppIconBeta` (feature workflow step 2).

## Build notes

- **Never run two `xcodebuild` processes at once** — they corrupt the shared
  module cache. If a build wedges at 0% CPU:
  `pkill -9 -f xcodebuild; rm -rf ~/Library/Developer/Xcode/DerivedData/Marginal-* ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex`.
- A full `xcodebuild test` run is ~7–10 minutes. Scope with
  `-only-testing:MarginalTests/<ClassName>` while iterating.
- The `.xcodeproj` is generated by XcodeGen from `project.yml` and is gitignored —
  never commit it. Run `xcodegen generate` after adding/removing source files.
