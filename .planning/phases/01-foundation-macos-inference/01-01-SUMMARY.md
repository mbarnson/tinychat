# 01-01 Summary — Foundation and macOS local CoreAI inference

Date: 2026-07-02

## What changed

- Replaced the stock SwiftData `Item` template with `Chat` and `Message` SwiftData models.
  - `Chat` stores title, timestamps, context summary placeholder, thinking toggle state, and cascade-owned messages.
  - `Message` stores role, final text, optional reasoning text, stopped state, and error text.
- Updated `tinychatApp` to use the new `Chat`/`Message` schema.
- Built the first non-template SwiftUI chat shell:
  - `NavigationSplitView` sidebar/detail layout.
  - Transcript view.
  - Multiline composer.
  - Send/Stop controls.
  - Thinking toggle.
  - Selectable message text.
  - Per-message Copy button.
  - Collapsible reasoning display with separate Copy reasoning button.
  - Lightweight model status row.
- Added a narrow `ChatEngine` seam:
  - deterministic UI-test engine;
  - model-missing engine;
  - `CoreAIChatEngine` wrapper guarded by `canImport(CoreAILanguageModels) && canImport(FoundationModels)`.
- Added app-side model cache lookup for Qwen3 0.6B:
  - macOS path: `Application Support/tinychat/Models/qwen3-0.6b/macOS`.
  - iOS path: `Application Support/tinychat/Models/qwen3-0.6b/iOS`.
- Added `scripts/seed-qwen3-0_6b-macos-cache.sh`, which exports Qwen3 0.6B through the vendored CoreAI Python tooling and atomically seeds the macOS App Support cache.
- Added UI-test launch arguments:
  - `--reset-chat-state`
  - `--use-deterministic-chat-engine`
- Fixed the relaunch-selection race by delaying initial empty-chat creation and reselecting persisted chats when the SwiftData query changes.
- Added `.gitignore` entries for `.build/` and Xcode user data.

## Verification commands and results

### Seed script

```bash
scripts/seed-qwen3-0_6b-macos-cache.sh
```

Result: passed.

Observed output ended with:

```text
Export complete: /Users/patbarnson/devel/tinychat/.build/coreai-exports/qwen3-0.6b-macos/qwen3_0_6b_4bit_dynamic
Seeded Qwen3 0.6B macOS model cache: /Users/patbarnson/Library/Containers/org.barnson.tinychat/Data/Library/Application Support/tinychat/Models/qwen3-0.6b/macOS
```

### macOS build + unit/UI tests

```bash
xcodebuild -project tinychat.xcodeproj -scheme tinychat -destination 'platform=macOS' -derivedDataPath .build/DerivedData MACOSX_DEPLOYMENT_TARGET=26.5 IPHONEOS_DEPLOYMENT_TARGET=26.5 test
```

Result: passed.

Observed result:

```text
** TEST SUCCEEDED **
```

Tests covered:

- SwiftData `Chat`/`Message` persistence in memory.
- Model cache missing/installed path states.
- Reasoning parser splitting `<think>...</think>` from final text.
- macOS UI flow with deterministic engine:
  - reset state;
  - send prompt;
  - observe streaming assistant bubble;
  - stop generation;
  - verify assistant message and copy button;
  - relaunch and verify persisted assistant message is selected and visible.

### iOS simulator build

```bash
xcodebuild -project tinychat.xcodeproj -scheme tinychat -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData MACOSX_DEPLOYMENT_TARGET=26.5 IPHONEOS_DEPLOYMENT_TARGET=26.5 build
```

Result: passed.

Observed result:

```text
** BUILD SUCCEEDED **
```

### Xcode 27 beta linked builds

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project tinychat.xcodeproj -scheme tinychat \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedDataBeta build
```

Result: passed with `CoreAILM` linked.

Observed result:

```text
** BUILD SUCCEEDED **
```

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project tinychat.xcodeproj -scheme tinychat \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedDataBeta build
```

Result: passed with `CoreAILM` linked.

Observed result:

```text
** BUILD SUCCEEDED **
```

The beta install reports Xcode `27.0` build `27A5209h` and SDKs `macosx27.0`, `iphoneos27.0`, and `iphonesimulator27.0`.

The iOS 27 simulator runtime is installed, but `CoreAI` is not resolvable for the iOS Simulator build of Apple's `coreai-models` package:

```text
CoreAIShared/Runtime/ModelStructure.swift:6:8: error: Unable to resolve module dependency: 'CoreAI'
```

So iOS simulator UI tests remain useful for deterministic/no-CoreAI builds, but linked CoreAI iOS verification currently needs a physical iOS 27 device or an Apple package/SDK change that exposes `CoreAI` to the simulator SDK.

## Real macOS model smoke status

Partially unblocked by Xcode 27 beta.

The Qwen3 0.6B artifact export and App Support seed succeeded, and the app target now links Apple's `CoreAILM` package product under Xcode 27 beta. Build-only verification passes for macOS and generic iOS device using `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

The real macOS seeded-model smoke test still cannot run on this workstation because the host OS is macOS 26.6 while the app/test deployment target is macOS 27.0. `xcodebuild test -destination 'platform=macOS'` fails before launch with:

```text
Cannot test target “tinychatTests” on “My Mac”: My Mac’s macOS 26.6 doesn’t match tinychatTests’s macOS 27.0 deployment target.
```

Update after Xcode 27 Beta 2 install:

- `scripts/set-coreailm-link.py enable` successfully links the app target's `CoreAILM` product dependency and Frameworks phase.
- `testRealModelSmokeWhenEnabled`, gated by `TINYCHAT_RUN_REAL_MODEL_UI_TEST=1`, is ready but still host-runtime blocked for macOS until a macOS 27 runtime host is available.

## Deviations from plan

- The macOS real-model smoke test did not run because this machine is still booted on macOS 26.6; Xcode 27 beta provides SDK 27 but cannot run a macOS 27 deployment-target test bundle on a macOS 26.6 host.
- Linked macOS and generic iOS device builds now pass under Xcode 27 beta with no deployment-target overrides.
- Linked iOS simulator tests/builds fail in Apple's `coreai-models` package because the simulator SDK cannot resolve module `CoreAI`.
- Title generation is prompt-only fallback from the first user message. No auxiliary model title prompt is run yet, avoiding cache/session complexity before real CoreAI inference is verified.

## Remaining work for Phase 02 / next checkpoint

- To run the real macOS seeded-model smoke, boot a macOS 27 host/runtime, then run:
  - `TINYCHAT_RUN_REAL_MODEL_UI_TEST=1 DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project tinychat.xcodeproj -scheme tinychat -destination 'platform=macOS' -derivedDataPath .build/DerivedDataBeta test`
- For linked iOS runtime verification, use a physical iOS 27 device unless/until `CoreAI` becomes available to the iOS Simulator SDK.
- Build the manifest/ZIP download/cache lifecycle against fixture assets first.
- Replace local App Support seeding with the production first-run download flow.
- Add model provenance/hash/version fields once the static manifest exists.
