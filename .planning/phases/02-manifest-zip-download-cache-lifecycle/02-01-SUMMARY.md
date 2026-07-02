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

## Verification commands and results

### macOS executable tests with CoreAILM temporarily unlinked

The committed app target remains linked to `CoreAILM` for Xcode/SDK 27 builds. This workstation is still running macOS 26.6, so macOS 27 deployment-target test bundles cannot launch here. To execute the offline cache/unit/UI suite on this host, `CoreAILM` was temporarily unlinked and deployment targets were overridden for the test invocation, then the link was restored:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  scripts/set-coreailm-link.py disable && \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project tinychat.xcodeproj -scheme tinychat \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  MACOSX_DEPLOYMENT_TARGET=26.5 \
  IPHONEOS_DEPLOYMENT_TARGET=26.5 \
  test; \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  scripts/set-coreailm-link.py enable
```

Result: passed.

Observed result:

```text
** TEST SUCCEEDED **
tinychatTests: 14 passed
tinychatUITests: 4 executed, 1 real-model smoke skipped by gate
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

## Still remaining for Phase 02

- Static manifest file/schema committed as fixture asset.
- ZIP creation/extraction path.
- SHA-256 verification.
- Foreground progress, cancel, retry, and disk-space checks.
- Real GitHub Release manifest/artifact URL support.
- Model panel listing 0.6B and 4B availability/current/provenance/actions.
- UI test that drives fixture install/delete through the visible model status controls.
