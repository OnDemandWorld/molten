# Getting more people to subscribe to Molten, without ads

## Start with the gates you already have

The fastest win doesn't need any new prompts. According to your feature inventory, Molten already has three Plus gates besides the second knowledge base, but users mostly never notice them:

- **The 10-document limit doesn't work on iOS (G1).** It counts indexed documents, and those stay at zero while the iPhone waits for a Mac to process them. Free iOS users can add any number of files and never see the paywall. Count added files instead, and the paywall starts appearing at a moment when the user clearly wants more.
- **OCR is gated, but the gate is invisible.** The indexer's prefilter skips scanned PDFs and images for free users. From the user's side, the document seems to have done nothing. Instead, mark the file row "Needs text recognition · Plus" and let a tap open the paywall. Phrase it so it shows what they're missing: "3 scanned pages couldn't be read."
- **iCloud sync is gated, but nothing in the app tells free users it exists.** The Knowledge screen just behaves as local-only. A small, permanent line there ("On this device only · Sync with Plus") explains the feature without interrupting anything.

All three only appear when the user is trying to do something Plus unlocks. That's the least annoying kind of prompt, and the one most likely to convert. Fix G2 at the same time, so that someone who subscribes from one of these prompts gets sync immediately instead of after a relaunch.

## Make Plus visible without interrupting

These are always visible but never pop up:

- **Show free users their usage.** "7 of 10 documents" in the base header, and a lock icon on "New Base" once the first base exists. People who can see the limit coming aren't surprised by the paywall when they reach it.
- **Add a plan row at the top of Settings.** "Molten Free · See what Plus adds" for free users, and "Plus · Early Supporter ❤︎" for Early Supporters, so they feel recognized instead of upsold.
- **Show the free trial wherever you show Plus.** The 1-week trial is only on the $19.99 yearly plan, so every Plus entry point should lead with "Try Plus free for a week" rather than the monthly price. Low commitment converts best with your kind of audience.
- **Present Plus as supporting the project.** Molten is open source, has no servers and collects no data, and the people who choose it tend to respect that. Copy like "Molten has no ads, no tracking, no investors. Plus keeps it that way" works better with them than feature lists. It's also honest, and it fits the Lifetime option well.

## Add a few well-timed prompts (soft triggers)

PurchasesKit already has this mechanism (`presentSoft`, with a cooldown and a rule against showing in the same session as a limit-hit paywall), so you don't need to invent one. What matters is timing: tie each prompt to a moment when the user has just gotten value from the app, not to a raw count. Your idea of "after N chats" works best as a usage threshold combined with such a moment.

| Moment | When it fires | Prompt |
|---|---|---|
| First grounded answer | The first time a reply includes citations from their own documents | Small card under the reply: "Your documents, answered with citations. Plus adds unlimited bases, scanned-PDF reading and sync across devices." Not a full-screen paywall. |
| Settled-in user | 3 or more separate days of use **and** 30 or more messages, no earlier than day 5 after install | One-time "What you get with Plus" sheet, leading with the trial |
| Second device | The user has Molten on iPhone and Mac (detectable through a tiny flag in the user's own iCloud key-value store, with no content sent) | "You use Molten on two devices. Process documents once on your Mac and read them anywhere with Plus." This is your strongest sync pitch. |
| End of first-base onboarding | After the existing privacy disclosure | One line plus "Try free for a week" next to "Not now". Never blocking. |
| Mac power use | After the 20th use of the floating panel or a completion | Supporter-style message only. Don't gate these features, since chat and the panel are in your "free forever" promise. This is just a thank-you that mentions Plus. |
| Subscription ended | First launch after a subscription expires | "Sync is paused. Your documents are all still here." Plus a resubscribe button. This also fixes G4's confusing behavior. |

## Rules that keep this from becoming annoying

I'd write these into the coordinator as code, not leave them as guidelines:

- **Limit how often prompts appear.** At most one soft prompt every 14 days, and at most 4 in total. After that, only prompts tied to a limit the user just hit.
- **Never interrupt:** no prompts at launch, during streaming, in the floating panel's quick flow, from the share extension, or in the same session as a hard paywall.
- **Make closing easy:** the close button is visible immediately, and the first prompt the user dismisses offers "Don't show tips like this again." Respecting that builds the trust your audience pays for.
- **Paying users and Early Supporters never see prompts.** Gate everything on `EntitlementManager`'s tier, which already includes Early Supporters.
- **Prefer inline cards to full-screen covers** for soft triggers. Full-screen covers should only appear when the user hits a real limit.

## How to build it

Add a small `UpsellCoordinator` that keeps only local counters in UserDefaults: install date, active days, messages sent, grounded answers, panel uses, last prompt date, prompt count and opt-out. Each trigger becomes one `noteEvent(.groundedAnswer)` call from the send path or the panel. The coordinator decides, and it reuses your existing `PaywallView` or a lightweight card. Nothing leaves the device, so your no-telemetry promise still holds.

To measure results without analytics, use App Store Connect: trial starts, conversion and retention. Release one trigger per version so you can tell which one helped. Apple also offers **win-back offers** for lapsed subscribers and **offer codes**, both configured in App Store Connect. Both fit well with the "subscription ended" card.

## What I'd build first

1. Fix G1, show the OCR gate on the file row, add the "local only · sync with Plus" line, and fix G2. These are the gates you already have, so it's the cheapest work with the biggest impact.
2. Add the usage indicators, the Settings plan row and trial-first wording.
3. Add `UpsellCoordinator` with the first-grounded-answer and settled-in triggers.
4. Add the second-device and subscription-ended triggers.
5. Later, in version 2.2, a Pro tier for tools and MCP, and possibly `macAssist`, gives power users something new to pay for. That works better than putting limits on what's free today.

Steps 1 and 2 alone probably more than double how often people actually see the paywall, and they never interrupt anyone who hasn't just tried to use a Plus feature. That's my estimate, not something I've measured. It's the main reason to do them before adding any prompts.
---

## Implementation status (2026-11-24, branch `fix/review-2026-11-24-highs`)

**Implemented and tested** (53 XCTest + 131 Swift Testing pass; macOS + iOS builds clean):

- **Step 1** — G1/G2/G4 were already fixed earlier on this branch. New: OCR
  gate visible on file rows ("Needs text recognition · Plus — N scanned
  pages unread", tap → paywall; text-layer check off-main), permanent
  "On this device only · Sync with Plus" line in the Knowledge sidebar.
- **Step 2** — "N of 10 documents" usage for Free (counts files present),
  lock icon on New Base at the limit, Settings plan row copy ("Free · See
  what Plus adds", "Early Supporter ❤︎" — the row already existed as the
  first Settings section), trial-first paywall headline, supporter copy
  ("no ads, no tracking, no investors"), non-blocking trial line at the end
  of first-base onboarding.
- **Steps 3–4** — `UpsellCoordinator` (Molten/Entitlements/) with local-only
  counters in a dedicated UserDefaults suite (`molten.upsell`), all rules
  encoded: 14-day cooldown, max 4 prompts, tier/opt-out gate, no prompts
  during streaming / while the panel is key / in a hard-paywall session,
  one prompt per session, opt-out offered on first dismiss. Triggers wired:
  first grounded answer (inline card under the cited reply), settled-in
  (3 active days + 30 messages + install ≥ 5 days), subscription lapse
  ("Sync is paused. Your documents are all still here."), panel supporter
  thank-you at 20 uses. `UpsellCoordinator.enabledTriggers` is the
  per-release dial for the "one trigger per version" measurement advice.
  12 unit tests cover the rules.

**Corrections to the original text:**

- *PurchasesKit does not exist in this codebase* — there is no `presentSoft`
  mechanism to reuse; the coordinator above is built from scratch as the
  "How to build it" section describes.
- *Second-device trigger deferred*: `NSUbiquitousKeyValueStore` needs the
  `com.apple.developer.ubiquity-kvstore-identifier` entitlement, which the
  app does not have (iCloud services = CloudDocuments only). Adding it is
  an owner/provisioning task (see docs/OWNER_TASKS.md); the trigger can
  then be added to the coordinator without other changes.
- The Settings plan row and Early Supporter recognition already existed;
  only the copy was adjusted.

**Not implemented (owner decisions):** win-back offers / offer codes
(App Store Connect configuration, no code needed), Pro tier (2.2 roadmap).
