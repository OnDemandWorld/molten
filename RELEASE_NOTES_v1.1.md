# What's New in Molten 1.1

## UI & Accessibility Polish

✨ **Better accessibility** — VoiceOver labels, improved hit targets, and proper focus management throughout the app

⌨️ **Keyboard improvements** — Drag-to-dismiss keyboard on iOS, fixed hotkey event handling on macOS

🎨 **Respects Reduce Motion** — Animations now honor your Accessibility settings

⚠️ **Dismissible error banner** — Connection errors can now be dismissed instead of blocking the UI

📊 **Clearer analytics** — Performance metrics use more intuitive labels ("input speed" instead of "prompt eval rate")

## Settings & Connection

🔒 **Secure token entry** — Bearer tokens and API keys now use SecureField (password-style masking)

📡 **Better connection indicators** — Status icons in Settings clearly show which providers are reachable

🎙️ **Voice loading fix** — TTS voices now fetch once when Settings opens instead of polling every 5 seconds

## Stability & Data

🛡️ **Data loss prevention** — Fixed SwiftData relationship rules that could delete conversations when removing a model

📈 **Database growth fix** — Model list no longer accumulates duplicates on every refresh

🎤 **Voice input fix** — Speech recognizer now properly updates the UI during transcription

🔊 **Text-to-speech fix** — Audio session now activates correctly on iOS (TTS was silently failing)

⌨️ **Hotkey fix** — Custom keyboard shortcuts now properly consume events instead of triggering system actions too

## Under the Hood

• Privacy hardening and analytics accuracy improvements
• Reproducible builds for verified App Store releases
• Removed dead UI elements (Voice stub, menu bar, header)
• Fixed Shortcuts sheet showing stale information
• Fixed unreachable banner's Settings button behavior
• Numerous concurrency and threading fixes for strict Swift 6 compliance

---

**Requirements**: macOS 26.0+, iOS 26.0+, iPadOS 26.0+  
**Privacy**: Molten collects no data. Ever.

*Thank you for using Molten! 🍎*
