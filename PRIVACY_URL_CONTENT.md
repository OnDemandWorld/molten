# Privacy Policy - Molten

**Last Updated**: March 13, 2026  
**Version**: 1.0.0

Host this content on a website or link to the GitHub version for your Privacy Policy URL.

---

## Privacy Policy

### Introduction

Molten ("we", "our", or "the app") is committed to protecting your privacy. This Privacy Policy explains how Molten handles your data.

**In short: Molten collects NO data. Period.**

---

## Data Collection

### We Do Not Collect Any Data

Molten does not collect, store, or transmit any of the following:

- ❌ Personal information
- ❌ Usage data
- ❌ Analytics
- ❌ Identifiers (device ID, user ID, etc.)
- ❌ Location data
- ❌ Contact information
- ❌ User content (conversations, prompts, etc.)
- ❌ Diagnostics or crash reports
- ❌ Browsing history
- ❌ Search history

**All data stays on your device.**

---

## Data Storage

### Local Storage Only

Conversations and settings are stored locally on your device using Apple's SwiftData framework.

- **No cloud sync**
- **No backup to external servers**
- **No data transmission** (except to localhost model providers you control)

### Data You Control

You can:
- View all stored data in the app
- Delete conversations anytime
- Clear all data by deleting the app

---

## Network Access

### Localhost Connections Only

Molten communicates with local AI model providers (Ollama, Swama) via localhost:

- **Ollama**: `http://localhost:11434`
- **Swama**: `http://localhost:28100`

**No external network calls are made.**

### Why Network Access is Required

Molten itself does not run AI models. It provides an interface to model providers you install separately (Ollama, Swama, or Apple Foundation Models).

All communication stays on your device (localhost). No data is sent to external servers.

---

## Third-Party Services

### No Third-Party Analytics

Molten does not use:
- Analytics services (Google Analytics, Firebase, etc.)
- Advertising networks
- Tracking SDKs
- Crash reporting services

### Open Source Libraries

Molten uses these open source libraries (none collect data):

- OllamaKit - Ollama API client
- Splash - Syntax highlighting
- MarkdownUI - Markdown rendering
- KeyboardShortcuts - macOS keyboard shortcuts
- ActivityIndicatorView - UI component
- Magnet - Hotkey management
- Vortex - Particle effects
- WrappingHStack - Layout component

All libraries are open source and do not collect data.

---

## Permissions

### Optional Permissions

Molten requests these optional permissions:

**Accessibility API** (macOS)
- **Purpose**: Enable text manipulation features (fix grammar, extend text, custom commands)
- **Required**: No
- **Control**: Can be disabled in System Settings; core app functions without it

**Microphone** (iOS/macOS)
- **Purpose**: Voice input for prompts
- **Required**: No
- **Control**: System permission dialog; use text input instead

**Camera**: Not used
- Image attachments use system file picker, not direct camera access

---

## Children's Privacy

### Age Rating: 4+

Molten is suitable for all ages.

- No data collection from children under 13
- No data collection from any users
- Complies with COPPA (Children's Online Privacy Protection Act)
- Complies with GDPR (General Data Protection Regulation)
- Complies with CCPA (California Consumer Privacy Act)

---

## Your Rights

### Data Rights

Since Molten collects no data, there is no data to:
- Access
- Delete
- Port
- Rectify
- Restrict processing of

### How to Delete Your Data

To delete all Molten data:
1. Delete conversations within the app, or
2. Delete the app from your device

---

## Changes to This Policy

We may update this Privacy Policy as needed. Changes will be:
- Posted on this page
- Dated with new "Last Updated" date
- Significant changes notified via app update notes

---

## Contact Us

### Questions or Concerns?

**GitHub Issues**: https://github.com/OnDemandWorld/molten/issues  
**Email**: [YOUR_EMAIL_HERE]  
**Website**: https://github.com/OnDemandWorld/molten

We respond to privacy inquiries within 48 hours.

---

## Legal Basis for Processing (GDPR)

Since Molten does not process any personal data, no legal basis is required under GDPR Article 6.

---

## Data Protection Officer

Molten does not require a Data Protection Officer (DPO) as we do not process personal data.

---

## International Data Transfers

No data is transferred internationally (or domestically) because no data is collected.

---

## Security

### How We Protect Data

While Molten collects no data, we still prioritize security:

- **Open Source**: Code is auditable by anyone
- **Local Processing**: All computation happens on your device
- **No External Dependencies**: No third-party services that could leak data
- **Regular Updates**: Security patches applied promptly

---

## Consent

By using Molten, you consent to this Privacy Policy.

If you do not agree, please do not use the app.

---

## Additional Information

### For App Store Privacy Labels

Molten's App Store listing shows "No Data Collected" - the best possible privacy rating.

### For Privacy Questions

Contact us at [YOUR_EMAIL_HERE] or via GitHub Issues.

---

## Acknowledgments

Molten is based on the Enchanted project. See https://github.com/gluonfield/enchanted

---

**Molten** - Local AI. On Your Terms. 🍎

**License**: Apache License 2.0  
**Privacy**: No data collection. Ever.
