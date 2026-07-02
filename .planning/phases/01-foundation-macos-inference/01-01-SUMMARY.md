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

## Real macOS model smoke status

Blocked in this workstation/Xcode combination.

The Qwen3 0.6B artifact export and App Support seed succeeded, but the app target cannot link Apple's `CoreAILM` package product in the current local SDK because the package declares macOS/iOS 27.0+ while this Xcode install exposes 26.5 SDK support. Earlier linked-build attempts failed before app compilation with CoreAI package targets reporting deployment target 27.0 outside the local supported deployment range.

Current app code keeps the `CoreAIChatEngine` wrapper in place behind `canImport(...)`, and the project retains the Apple `coreai-models` package reference plus `CoreAILM` product reference, but the target product dependency is intentionally not linked in this checkpoint so the app and tests remain buildable on this machine. Re-enable the `CoreAILM` target product dependency under Xcode/SDK 27 before running the real seeded-model smoke test.

## Deviations from plan

- `CoreAILM` is referenced but not linked into the app target in this checkpoint. Reason: linked builds are blocked by the local Xcode 26.5 SDK versus CoreAI's 27.0+ package platform requirement.
- The macOS real-model smoke test did not run for the same reason.
- The macOS and iOS verification commands used deployment-target overrides to 26.5 so this machine could compile and run tests. The project settings remain 27.0+.
- Title generation is prompt-only fallback from the first user message. No auxiliary model title prompt is run yet, avoiding cache/session complexity before real CoreAI inference is verified.

## Remaining work for Phase 02 / next checkpoint

- Re-enable and verify the `CoreAILM` app target product dependency under Xcode/SDK 27.
- Run the real macOS seeded-model smoke test:
  - launch without `--use-deterministic-chat-engine`;
  - send a short prompt;
  - verify assistant text becomes non-empty;
  - do not assert exact prose.
- Build the manifest/ZIP download/cache lifecycle against fixture assets first.
- Replace local App Support seeding with the production first-run download flow.
- Add model provenance/hash/version fields once the static manifest exists.
