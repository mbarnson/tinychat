# tinychat Roadmap

Date: 2026-07-02

## Milestone: SLC

Build the Simple, Lovable, Complete tinychat app: local CoreAI chat on macOS/iOS with Qwen3 0.6B base, Qwen3 4B upgrade, model download/cache management, multi-chat persistence, thinking/reasoning UI, and context summarization.

## Phase 01 — Foundation and macOS local inference

Status: complete for macOS local inference; linked iOS simulator remains blocked by Apple's CoreAI package/SDK availability

Purpose: replace the stock template, establish CoreAI dependency/platform baseline, seed a macOS App Support model cache, and prove real Qwen3 0.6B streaming inference in the beginning of the final chat UI.

Checkpoint 2026-07-02: schema/UI/cache/test infrastructure is implemented; Qwen3 0.6B macOS export and App Support seeding succeeded; `CoreAILM` is linked into the app target; full linked macOS tests pass on a macOS 27 host under `/Applications/Xcode-beta.app` / SDK 27, including a real Qwen3 0.6B CoreAI UI smoke through the app. Linked iOS simulator builds still fail inside Apple's `coreai-models` package because the iOS Simulator SDK cannot resolve module `CoreAI`; use physical iOS 27 hardware for linked iOS runtime verification.

Plans:

- `phases/01-foundation-macos-inference/01-01-PLAN.md` — platform/dependency/schema + macOS local CoreAI chat proof.

Acceptance:

- App builds for macOS and iOS simulator with deployment targets at 27.0+.
- Template `Item` model/UI is gone.
- `Chat`/`Message` SwiftData schema exists.
- macOS dev script can seed Qwen3 0.6B into App Support cache.
- macOS app streams a real response through CoreAI/FoundationModels from the seeded artifact.
- User and assistant messages persist after relaunch.
- Reasoning, if emitted, is stored separately and displayed collapsibly.
- Prompt-only title generation runs after first response or falls back to first prompt.

## Phase 02 — Manifest, ZIP download, and model cache lifecycle

Status: in progress — manifest ZIP download/cache path implemented against fixture artifacts; production release hosting and model panel still planned

Purpose: implement the first-run model download contract against fixture assets first, then real GitHub Release artifacts. Checkpoint 2026-07-02: `ModelCache` now has manifest validation, atomic install, metadata writing, delete, fixture-launch support, platform release-manifest selection, ZIP extraction, SHA-256 verification, disk-space checks, and a first-run `Download Model` UI wired through the production download/cache code path. Fast linked macOS tests pass on the macOS 27 host under `/Applications/Xcode-beta.app`; the real Qwen3 0.6B UI smoke is gated behind `TINYCHAT_RUN_REAL_MODEL_UI_TEST=1`.

Acceptance:

- Static manifest schema selects the right platform artifact.
- Downloader supports foreground progress, cancel, retry, disk-space check, SHA-256 verification, ZIP extraction, and atomic App Support install.
- First-run gate downloads Qwen3 0.6B base.
- Model panel lists 0.6B and 4B availability, installed/current status, provenance, download/update/delete/switch actions.
- Fast UI tests use localhost fixture manifest and tiny ZIP artifacts while exercising the production download/cache code path.

## Phase 03 — iOS real inference through download path

Status: planned

Purpose: prove iOS real CoreAI inference without sandbox cache hacks, using the app’s download/cache path on physical device.

Acceptance:

- iOS simulator fixture UI tests pass.
- Optional physical-device workflow can download Qwen3 0.6B iOS artifact, load it, stream non-empty output, and persist after relaunch.
- iOS UI adapts the same chat/model panel flows idiomatically.

## Phase 04 — Multi-chat product shell

Status: planned

Purpose: complete the core chat app shape.

Acceptance:

- NavigationSplitView sidebar/detail on macOS/iPad-style layouts; collapsed navigation on iPhone.
- New chat, switch chat, confirmed delete chat.
- Append-only messages.
- Single generation globally.
- Stop preserves partial assistant output.
- Global current model applies to all chats; switching model abandons active cache and rebuilds next send.

## Phase 05 — Qwen3 4B upgrade path

Status: planned

Purpose: make the SLC upgrade model real on both platforms.

Acceptance:

- Release pipeline produces all four artifacts: 0.6B macOS, 0.6B iOS, 4B macOS, 4B iOS.
- App can download, install, switch to, switch back from, and delete 4B.
- Fast fixture UI tests cover 4B upgrade UI.
- Real 4B release-gate tests verify structural generation on macOS and optional physical iOS device.

## Phase 06 — Context pressure and Summarize and continue

Status: planned

Purpose: handle context limits without silently dropping old turns or pretending CoreAI exposes multiple active caches.

Acceptance:

- Token budget warning appears at 80% of model context.
- “Summarize and continue” flow uses non-thinking mode to summarize final user/assistant content only.
- Summary excludes reasoning.
- Summary is editable in chat inspector.
- Summary edits invalidate active cache and rebuild on next send.
- Prompt assembly uses system instruction + summary + recent turns.

## Phase 07 — CI/export/release pipeline

Status: planned

Purpose: make model artifacts and verification repeatable.

Acceptance:

- Self-hosted Mac workflow exports/packages/hashes/uploads GitHub Release artifacts and static manifest.
- Fast default tests use fixtures and deterministic engine.
- Nightly real tests cover 0.6B.
- 4B real tests are release-gate.
- Physical iOS device destination is optional workflow input.

## Phase 08 — SLC polish and cut line

Status: planned

Purpose: finish user-facing recoverability and prevent scope creep.

Acceptance:

- Inline recoverable errors for download/hash/disk/model-load/generation failures.
- Accessibility labels/identifiers and keyboard baseline.
- Local-only/no-telemetry copy is visible.
- Explicitly absent: vision, markdown, editing/regeneration, iCloud, telemetry, long-context overrides, embedded Python runtime.
