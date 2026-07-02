# tinychat Brief

Date: 2026-07-02

## Objective

Build `tinychat`: a small, local-first SwiftUI chat app for macOS and iOS using Apple's CoreAI stack. The first-run experience is: install app, download a base model, start chatting.

## Current repo state

- Existing Xcode project: `tinychat.xcodeproj`.
- Current app is the stock SwiftData template (`Item`, `ContentView` list of timestamps).
- `vendor/coreai-models` exists as a local reference/export checkout only. It is not the app dependency.
- No `.planning/` structure existed before this brief.

## SLC scope

SLC means Simple, Lovable, Complete:

- macOS 27.0+ and iOS 27.0+.
- SwiftUI, Swift 6 where needed.
- CoreAI/CoreAILM via FoundationModels wrapper.
- Qwen3 0.6B as first-run base model.
- Qwen3 4B as manual upgrade on both macOS and iOS.
- Pre-exported model ZIP artifacts from GitHub Releases via static manifest.
- Local-only SwiftData chat persistence.
- Multiple chats: create, switch, delete with confirmation.
- Streaming responses, Stop button, persisted partial output on stop.
- Thinking mode on by default with composer toggle.
- Collapsible persisted reasoning, copyable separately, not fed back into prompts initially.
- Plain selectable message text plus Copy buttons.
- Model panel for download/progress/cancel/retry/switch/delete/update.
- Rolling context summary with “Summarize and continue” at 80% context, editable in chat inspector.
- No telemetry, no iCloud, no cloud inference, no embedded Python runtime.

## Explicit non-goals for SLC

- Vision / Qwen3-VL.
- Markdown/code rendering.
- Message editing, regeneration, branching.
- App Store polish/legal hardening.
- Long-context export overrides beyond CoreAI presets.
- Lower-level CoreAI engine path for exact TopP/TopK/MinP/presence penalty.

## Source-grounded CoreAI constraints

- CoreAI Models declares macOS 27.0+ and iOS 27.0+.
- Qwen3 text models are under `models/qwen3`; Qwen3-VL is separate under `models/vlm`.
- CoreAI presets found in `vendor/coreai-models/python/src/coreai_models/model_registry.py`:
  - Qwen3 0.6B macOS: 8192 context.
  - Qwen3 0.6B iOS: 4096 context.
  - Qwen3 4B macOS: 40960 context.
  - Qwen3 4B iOS: 4096 context.
- `CoreAILanguageModel` FoundationModels bridge currently maps only `GenerationOptions.temperature` into `SamplingConfiguration`.
- CoreAI emits reasoning as separate `.reasoning` entries and explicitly skips prior `.reasoning` when rebuilding prompts.
- CoreAI inference engines expose one active token/KV history per engine instance; no multiple named cache API was found.

## Major decisions

- Use FoundationModels wrapper first, accepting temperature-only sampling.
- Thinking temperature: 0.6. Non-thinking temperature: 0.7.
- Implement Think toggle via hidden `/think` / `/no_think` soft switch.
- Store reasoning now for display/history/future compatibility; do not include reasoning in future prompts or summaries.
- Keep active conversation cache in memory for current chat/model. Reconstruct from messages after app launch, model switch, summary edit, or cache invalidation.
- Title generation may sacrifice/rebuild the initial cache. Summary generation is user-triggered because it disrupts cache.
- iOS real inference comes after download/cache path because physical iOS App Support cache should not be seeded by hacks.
