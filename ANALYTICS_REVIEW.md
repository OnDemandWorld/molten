# Molten — Analytics Accuracy Review

**Date:** 2026-08-02 · **Scope:** the per-message performance footer (prompt eval rate, eval rate, overall throughput, total tokens, total time) — full chain: provider responses → mapping → `ConversationStore` computation → `AnalyticsFooterView` display · **Mode:** review; implementation status appended at the end.

## How each number is produced

| Footer metric | Formula (in code) | Where inputs come from | Accurate per chat? |
|---|---|---|---|
| prompt eval rate | `promptTokens / promptEvalTime` | tokens: Swama `usage` (real) · Ollama/Apple: **chars÷4 estimate** · time: client `Date()`, requestStart → **first chunk** | Swama: close (real tokens, client-side time). Ollama/Apple: **no** — estimated tokens |
| eval rate | `completionTokens / evalTime` | tokens: `usage` or chars÷4 of `realContent` (think-blocks excluded — good) · time: first chunk → completion (client) | same as above |
| overall | `totalTokens / totalTime` | `usage.total_tokens` or prompt+completion | same |
| total tokens | `usage.total_tokens`, else prompt+completion | **Swama: real server counts** · Ollama/Apple: estimates (±25–40% English, worse for code/CJK, blind to images) | provider-dependent |
| total time | `Date()` at complete − `requestStart` | client clock | ✓ as perceived latency; ≠ server generation time |

The plumbing is sound: timing partition is internally consistent (`promptEvalTime + evalTime == totalTime`), `requestStart` is captured *after* setup + the ≤2 s reachability probe, state resets between chats (no cross-message leakage), footer guards all zero/nil denominators, and analytics persist via `updateMessage` on completion. **The inputs are the problem.**

## Findings

**AN-1 · P1 — Ollama's real statistics are thrown away.** `OllamaService` maps every chunk with `usage: nil` (mapping site in `chatStream`), yet `OKChatResponse` exposes everything Ollama reports on the final chunk: `promptEvalCount`, `promptEvalDuration`, `evalCount`, `evalDuration`, `totalDuration` (nanoseconds). Every Ollama chat shows fabricated token counts instead of the server's authoritative numbers — the single biggest accuracy gap, and it's a mapping omission, not a hard problem.

**AN-2 · P2 — Swama sends more truth than the app captures.** Live testing showed Swama's final-chunk `usage` includes `total_duration` and `response_token/s`; the `Usage` struct declares only the three token counts, so `Codable` silently drops the server-side duration/rate. Token counts are real (good); displayed rates are client-timed — fine on localhost, increasingly wrong over LAN/remote.

**AN-3 · P2 — "first token" is actually "first chunk".** `hasReceivedFirstToken` fires on the first `handleReceive`, but Swama's first SSE chunk is `delta: {role: assistant}` with **no content**. So `promptEvalTime` ends at a content-less frame → prompt eval rate understated, eval time slightly inflated. Fix: stamp first-token on the first chunk with non-empty content.

**AN-4 · P2 — prompt-token estimate scope is timing-dependent and image-blind.** When `usage` is absent, prompt tokens = chars÷4 over `previousMessages = filter { createdAt < lastMessage.createdAt }`. The user message and assistant placeholder are created in the same `Date.now` window, so the filter often **excludes the very prompt just sent**; base64 image payloads (real prompt tokens server-side) are never counted — vision chats drastically undercount. (Image tokenization is model-specific; counting text only and labeling estimates is the honest fix.)

**AN-5 · P2 (cross-ref) — F-19 corrupts prompt accounting.** The unfixed double-send means the server processes the last user message **twice**. Once real stats are wired (AN-1/AN-2), reported prompt tokens/durations will include the duplicate — analytics will actively *expose* F-19. Honest prompt metrics are gated on fixing F-19 first.

**AN-6 · P3 — Apple-provider metrics are theater.** No `usage` ever; chunks are simulated with 10 ms sleeps, so the "eval rate" measures the app's own sleep loop, not the model. The footer presents it as model performance. Needs provider attribution (suppress rates or label "estimated" when `conversation.model.modelProvider == .appleFoundation`).

**AN-7 · P3 — stopped generations get no analytics.** `stopGenerate → finalizeMessage` sets `done = true` but computes nothing → the footer renders (it only checks `done`) as empty padding. Record partial stats (tokens so far, elapsed) instead.

**AN-8 · P3 — `totalTokens` fallback split is arbitrary** (`promptTokens = total/3` when only a total exists) — effectively dead (Swama sends all three; others send no totals).

## Recommended fix batch

1. **Fix F-19 first** (prerequisite for truthful prompt counts).
2. Extend `Usage` with optional server durations (seconds as `Double`); `OllamaService` maps the `done` chunk's `promptEvalCount/evalCount/promptEvalDuration/evalDuration` (ns→s) into `usage`; Swama's `total_duration`/`response_token/s` decode naturally once declared.
3. `handleComplete` prefers server-reported counts/durations when present, falls back to client timing + estimates otherwise; computation extracted as a pure, unit-testable function.
4. First-token stamping on first **non-empty content** chunk.
5. Estimate scope fix: include the current user turn (same-`Date.now` safe); images documented as not tokenized (estimate labeled).
6. Apple-provider footer labeling; partial stats for stopped generations.
7. **Tests:** pure unit tests for the computation (server-preferred path, fallback path, ns→s conversion), Ollama done-chunk mapping test, Swama usage decoding test, first-content-chunk behavior, prompt-char-count scope.

**Bottom line:** timing measurement and display math are correct; *tokens are real only for Swama*, and even there the server's own duration/rate is discarded. Ollama and Apple chats currently show estimates presented as measurements. The highest-value fix (AN-1) is a small mapping change.

---

## Implementation status

_(appended during implementation — see commits on `audit/ios-review` following this document)_
