# App Privacy Questionnaire Answers

## App Store Connect Privacy Details

Complete these sections in App Store Connect under "App Privacy".

---

## Data Used to Track You

**Answer**: NO

**Explanation**: Molten does not track users across apps or websites owned by other companies.

---

## Data Linked to You

**Answer**: NO DATA COLLECTED

Molten does not collect any data that is linked to your identity.

### Breakdown by Category

**Contact Info**: None collected  
**Contacts**: None collected  
**User Content**: None collected (all content stays on device)  
**Search History**: None collected  
**Browsing History**: None collected  
**Identifiers**: None collected  
**Purchases**: None collected  
**Usage Data**: None collected  
**Diagnostics**: None collected  
**Other Data**: None collected  

---

## Data Not Linked to You

**Answer**: NO DATA COLLECTED

Molten does not collect any data, even anonymously.

---

## Data Collection Details

### Does your app collect data?
**Answer**: No

### Do you embed third-party SDKs?
**Answer**: No

### Do you use analytics services?
**Answer**: No

### Do you use advertising networks?
**Answer**: No

### Do you share data with third parties?
**Answer**: No

---

## Privacy Policy

**Privacy Policy URL**: https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md

**Required**: Yes (for apps that don't collect data, still need a policy stating this)

---

## Privacy Labels Summary

When complete, your App Store listing will show:

```
Privacy Details
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
No Data Collected

The developer does not collect any data from this app.

Learn More
```

---

## Privacy Nutrition Label

**Category**: No Data Collected

This is the best possible privacy rating on the App Store.

---

## Additional Privacy Information

### Data Deletion

**Can users request data deletion?**  
N/A - No data is collected

### Data Retention

**How long is data retained?**  
N/A - No data is collected

### Children's Privacy

**Is your app directed at children under 13?**  
**Answer**: No

**Age Rating**: 4+ (no objectionable content)

### COPPA Compliance

**Does your app comply with COPPA?**  
**Answer**: Yes (no data collection from any users)

### GDPR Compliance

**Does your app comply with GDPR?**  
**Answer**: Yes (no personal data processing)

### CCPA Compliance

**Does your app comply with CCPA?**  
**Answer**: Yes (no sale of personal information)

---

## Third-Party Services

### Included Libraries

| Library | Purpose | Data Collection |
|---------|---------|-----------------|
| OllamaKit | Ollama API client | No |
| Splash | Syntax highlighting | No |
| MarkdownUI | Markdown rendering | No |
| KeyboardShortcuts | macOS shortcuts | No |
| ActivityIndicatorView | UI component | No |
| Magnet | Hotkey management | No |
| Vortex | Particle effects | No |
| WrappingHStack | Layout component | No |

**All libraries are open source and do not collect data.**

---

## Network Access

### Does your app access the network?
**Answer**: Yes (local network only)

### What network access is required?
- **Localhost connections** (Ollama: port 11434, Swama: port 28100)
- **No external network calls**

### Justification for ATS Exception
App Transport Security allows arbitrary loads to enable localhost communication with local AI model providers (Ollama, Swama). No insecure external connections are made.

---

## Permissions

### Accessibility API
**Required**: Optional  
**Purpose**: Text manipulation features  
**User Control**: Can be disabled, core app functions without it

### Microphone
**Required**: Optional (for voice input)  
**User Control**: System permission dialog

### Camera
**Required**: No  
**Note**: Image attachment uses file picker, not direct camera access

---

## Reviewer Notes

Add these notes for App Review team:

```
PRIVACY:
- Molten collects NO data of any kind
- All processing happens locally on device
- No analytics, tracking, or identifiers
- No third-party SDKs that collect data
- Network access is localhost only (Ollama/Swama)

PERMISSIONS:
- Accessibility API is optional (for text features)
- Microphone is optional (for voice input)
- Core chat functionality works without permissions

DATA STORAGE:
- Conversations stored locally via SwiftData
- No cloud sync or backup
- User can delete conversations anytime
```

---

## Privacy Policy Content

See `PRIVACY_URL_CONTENT.md` for full privacy policy text to host on website or link to GitHub.

---

**Last Updated**: March 13, 2026  
**Version**: 1.0.0
