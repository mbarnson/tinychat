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

Complete for macOS local inference after booting the workstation onto macOS 27.

The Qwen3 0.6B artifact export and App Support seed succeeded, and the app target links Apple's `CoreAILM` package product under Xcode 27 beta. Full linked macOS verification now passes using `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

The real macOS seeded-model UI smoke now exercises the app end to end: the UI test seeds the exported Qwen3 0.6B artifact into the sandbox App Support cache, launches the app, auto-sends a prompt with thinking disabled, waits for the persisted assistant message, and fails if the model status, chat-level error, or assistant-message error appears. The app streams real CoreAI/FoundationModels output and persists the assistant message.

Observed correction during verification:

- The app must pass a plain prompt string to `LanguageModelSession.streamResponse(to:options:)`; prior transcript-shaped prompt text caused the real model path to stall in UI smoke.
- `ChatEngine.responseEvents(for:)` is `nonisolated` so test and generation tasks can call it without main-actor isolation.
- SwiftUI `Text` with `.textSelection(.enabled)` should not be given an explicit `.accessibilityLabel(message.text)`/`.accessibilityLabel(text)` that mirrors its own content. On macOS 27 this triggered recursive SwiftUI accessibility label resolution and crashed under XCUI automation; the text already exposes its content.

## Deviations from plan

- Linked iOS simulator tests/builds still fail in Apple's `coreai-models` package because the simulator SDK cannot resolve module `CoreAI`.
- Title generation remains prompt-only fallback from the first user message. No auxiliary model title prompt is run yet, avoiding cache/session complexity before real CoreAI inference is verified on iOS.

## Remaining work for Phase 02 / next checkpoint

- For linked iOS runtime verification, use a physical iOS 27 device unless/until `CoreAI` becomes available to the iOS Simulator SDK.
- Build the manifest/ZIP download/cache lifecycle against fixture assets first.
- Replace local App Support seeding with the production first-run download flow.
- Add model provenance/hash/version fields once the static manifest exists.
