# 02-01 Summary — Offline fixture cache lifecycle

Date: 2026-07-02

## What changed

- Extended `ModelCache` from a path/status helper into an installable cache boundary.
- Added `ModelArtifactManifest` with model ID, platform, version, source URL, and expected-file validation.
- Added `InstalledModelMetadata` persisted as `metadata.json` beside the installed model files.
- Added typed `ModelCacheError` cases for model mismatch, platform mismatch, missing source directory, missing expected files, and install/delete filesystem failures.
- Added `installBaseModel(from:installedAt:)` with staged copy into a temporary directory and atomic replacement of the App Support model directory.
- Added `removeBaseModel()` for explicit cache deletion.
- Added launch-argument gated fixture installation in `ContentView` using `--fixture-model-path`, so UI tests can exercise production install/delete state without network or real model inference.
- Added model status UI actions:
  - missing state: `Install Fixture Model` when fixture launch arg is present;
  - installed state: `Delete Model`.
- Adjusted deterministic streaming to avoid surfacing stale `<think>` text while the closing tag is incomplete.
- Added Swift Testing coverage for manifest validation, installation, replacement, metadata persistence, deletion, and missing/installed states.
- Added `ModelReleaseManifest` / `ModelReleaseArtifact` selection for platform-specific release artifacts.
- Added `ModelDownloadManager` to load release manifests, copy/download model ZIPs, verify byte size and SHA-256, extract stored ZIP entries safely, check disk space, and install atomically through `ModelCache`.
- Added first-run download UI support: `--model-release-manifest-url` exposes a `Download Model` action, progress text, and install error reporting while reusing the production cache path.
- Added a tiny ZIP fixture UI test that clicks the visible `Download Model` button and verifies the installed model status without relying on a real model artifact.

## Verification commands and results

### Linked macOS tests under Xcode 27 beta

The committed app target remains linked to `CoreAILM`, and the workstation is now booted on macOS 27. The offline cache/unit/UI suite runs with no deployment-target overrides or temporary unlinking. The real Qwen3 0.6B UI smoke is now gated behind `TINYCHAT_RUN_REAL_MODEL_UI_TEST=1` so the fast default suite remains fixture-only:
```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project tinychat.xcodeproj -scheme tinychat \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedDataBeta \
  test
```

Result: passed.

Observed result from `.build/DerivedDataBeta/Logs/Test/Test-tinychat-2026.07.02_04-57-24--0700.xcresult`:

```text
** TEST SUCCEEDED **
passedTests: 24
skippedTests: 1
failedTests: 0
tinychatUITests.testFirstRunDownloadButtonUsesManifest passed
tinychatUITests.testRealModelSmokeWhenEnabled skipped without TINYCHAT_RUN_REAL_MODEL_UI_TEST=1
```

### macOS build-for-testing under Xcode 27 beta with CoreAILM linked

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project tinychat.xcodeproj -scheme tinychat \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedDataBeta build-for-testing
```

Result: passed.

Observed result:

```text
** TEST BUILD SUCCEEDED **
```

Warnings observed:

```text
warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

This warning is unrelated to the cache lifecycle work; the app has no AppIntents dependency.

## Tests covered

- `ModelCache.baseModelStatus()` reports missing before install and installed after model directory creation.
- Cache path ends in `Models/qwen3-0.6b/<platform>`.
- Install rejects wrong model IDs.
- Install rejects wrong platform manifests.
- Install rejects missing source directories.
- Install rejects manifests whose expected files are absent.
- Install transitions missing to installed.
- Install writes decodable metadata with model ID, display name, version, platform, source URL, and installed timestamp.
- Install copies all fixture files needed by the manifest.
- Reinstall replaces stale installed files atomically from the caller perspective.
- Delete transitions installed back to missing.
- Release manifest selection picks the artifact matching `ModelCache.platformDirectoryName`.
- ZIP artifact install verifies SHA-256 before extraction.
- ZIP artifact install rejects SHA-256 mismatches.
- ZIP artifact install rejects unsupported deflate compression.
- ZIP artifact install rejects unsafe path traversal entries.
- First-run download UI exposes `Download Model`, installs from a manifest-backed ZIP fixture, and transitions to installed status after a click.

## Still remaining for Phase 02

- Real GitHub Release manifest/artifact URL support with production artifact locations.
- Foreground cancel and retry controls for long downloads.
- Model panel listing 0.6B and 4B availability/current/provenance/actions.
