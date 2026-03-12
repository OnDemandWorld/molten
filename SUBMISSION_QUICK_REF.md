# App Store Submission - Quick Reference

**Version**: 1.0.0  
**Build**: 1  
**Date Prepared**: March 13, 2026

---

## 📦 Files Created

All files are in `/Users/eplt/SCM/molten/`:

### Core Submission Documents

| File | Purpose | Use For |
|------|---------|---------|
| `APP_STORE_SUBMISSION.md` | Main submission guide | Complete walkthrough |
| `PRE_SUBMISSION_CHECKLIST.md` | Step-by-step checklist | Before submitting |
| `RELEASE_NOTES.md` | What's New text | App Store Connect |
| `APP_STORE_DESCRIPTION.md` | Full description | App Store Connect |
| `MARKETING_KEYWORDS.md` | Keywords | App Store Connect |
| `PRIVACY_NUTSHELL.md` | Privacy answers | App Store Connect questionnaire |
| `SUPPORT_URL_CONTENT.md` | Support page | Host on website |
| `PRIVACY_URL_CONTENT.md` | Privacy policy | Host on website |
| `SCREENSHOT_GUIDE.md` | Screenshot requirements | Creating media |

---

## 🚀 Quick Start

### 1. Copy These Texts to App Store Connect

**App Name**: Molten - Local AI Chat  
**Subtitle**: Run LLMs Offline, Private

**Keywords** (copy exactly):
```
local,ai,llm,ollama,private,offline,mac,chat,llama,ml
```

**Description**: Copy from `APP_STORE_DESCRIPTION.md`

**Release Notes**: Copy from `RELEASE_NOTES.md`

### 2. Privacy Questionnaire

In App Store Connect → App Privacy:

- Data Used to Track You: **No**
- Data Linked to You: **No Data Collected**
- Data Not Linked to You: **No Data Collected**

Full answers in `PRIVACY_NUTSHELL.md`

### 3. Upload Screenshots

Required:
- 2 macOS screenshots (1440x900 minimum)
- 2 iOS screenshots (if universal)
- 2 iPadOS screenshots (if universal)

See `SCREENSHOT_GUIDE.md` for sizes and tips

### 4. URLs (Must Be Live)

**Support URL**: Host content from `SUPPORT_URL_CONTENT.md`
- Recommended: GitHub Pages or GitHub wiki
- Must be live before submission

**Privacy Policy URL**: 
- Can use: https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md
- Or host content from `PRIVACY_URL_CONTENT.md`

---

## ✅ Pre-Submission Checklist

Before clicking "Submit":

- [ ] Build uploaded and processed in App Store Connect
- [ ] All metadata complete (description, keywords, release notes)
- [ ] Screenshots uploaded (all required sizes)
- [ ] Privacy questionnaire complete
- [ ] Support URL live and working
- [ ] Privacy Policy URL live and working
- [ ] Pricing set (Free recommended)
- [ ] Banking info complete (required even for free apps)
- [ ] Contact info current in App Store Connect
- [ ] Reviewer notes added

Full checklist: `PRE_SUBMISSION_CHECKLIST.md`

---

## 📝 App Store Connect Fields

### App Information

| Field | Value |
|-------|-------|
| **Name** | Molten - Local AI Chat |
| **Subtitle** | Run LLMs Offline, Private |
| **Primary Category** | Productivity |
| **Secondary Category** | Developer Tools |
| **Age Rating** | 4+ |
| **Version** | 1.0.0 |
| **Copyright** | © 2026 OnDemandWorld |

### Pricing & Availability

| Field | Value |
|-------|-------|
| **Price** | Free (recommended) |
| **Availability** | All countries (or select) |
| **Release Date** | [Your choice] |

### Version Information

| Field | Value |
|-------|-------|
| **Description** | From `APP_STORE_DESCRIPTION.md` |
| **Keywords** | `local,ai,llm,ollama,private,offline,mac,chat,llama,ml` |
| **Release Notes** | From `RELEASE_NOTES.md` |

---

## 🎯 App Review Notes

Copy this to App Store Connect → App Review Information → Notes:

```
Molten is a privacy-first local AI chat application that runs LLMs 
completely offline.

REQUIREMENTS FOR FULL FUNCTIONALITY:
• Users must install Ollama or Swama separately (free, open-source)
• Apple Foundation Models built-in on macOS 26.0+
• App works without these but no models will be available

NETWORK ACCESS:
• Only connects to localhost (Ollama:11434, Swama:28100)
• No external network calls
• ATS exception required for localhost communication

ACCESSIBILITY API:
• Optional feature for text manipulation
• User must grant permission in System Settings
• Not required for core chat functionality

TEST ACCOUNT: Not required - app works fully without account

PRIVACY:
• No data collection of any kind
• All processing happens locally on device
• Open source for audit (Apache License 2.0)
```

---

## 📊 Submission Timeline

### Before Submission (1-2 days)

- [ ] Create support webpage (GitHub Pages recommended)
- [ ] Create privacy policy page (or use GitHub file)
- [ ] Capture and edit screenshots
- [ ] Record App Preview video (optional)
- [ ] Test build on multiple devices

### Submission Day (1 hour)

- [ ] Archive and upload build in Xcode
- [ ] Wait for build to process (~10 min)
- [ ] Complete all metadata in App Store Connect
- [ ] Upload screenshots
- [ ] Fill out privacy questionnaire
- [ ] Select build for review
- [ ] Submit for review

### After Submission

- **24-48 hours**: App review completes
- **Pending Developer Release**: Click release (or auto-release on date)
- **Ready for Sale**: Live on App Store!

---

## 🔧 Build Information

### Xcode Settings

**Target → General → Identity**:
- Bundle ID: `com.ondemandworld.molten` (verify)
- Version: 1.0.0
- Build: 1

**Target → General → Deployment Info**:
- macOS: 14.0
- iOS: 17.0
- iPadOS: 17.0

**Target → Info**:
- App Transport Security: Allows arbitrary loads (for localhost)
- Accessibility usage description: "Molten can perform operations on selected text..."

### Archive & Upload

1. **Product** → **Archive**
2. Wait for archive to complete
3. Click **Distribute App**
4. Select **App Store Connect**
5. Follow prompts to upload

---

## 📞 Support & Contact

### Developer Information

**Name**: OnDemandWorld  
**Email**: [YOUR_EMAIL_HERE]  
**Website**: https://github.com/OnDemandWorld/molten

### Update Before Submission

Replace `[YOUR_EMAIL_HERE]` in:
- `SUPPORT_URL_CONTENT.md`
- `PRIVACY_URL_CONTENT.md`
- `PRIVACY_NUTSHELL.md`
- This file

---

## 📄 Required URLs

Make these live BEFORE submission:

### Support Page

**URL**: https://github.com/OnDemandWorld/molten/wiki/Support  
**Content**: Copy from `SUPPORT_URL_CONTENT.md`

Or create GitHub Pages site:
1. Create `docs/support.md` with content
2. Enable GitHub Pages in repo settings
3. URL: https://ondemandworld.github.io/molten/support

### Privacy Policy

**Option 1**: Use GitHub file (easiest)
- URL: https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md
- Already exists, just verify it's accessible

**Option 2**: Host as webpage
- Use content from `PRIVACY_URL_CONTENT.md`
- Similar process as support page

---

## 🎨 Screenshot Requirements

### Minimum Required

- **macOS**: 2 screenshots (1280x800 or larger)
- **iOS**: 2 screenshots for one size (if universal)
- **iPadOS**: 2 screenshots for one size (if universal)

### Recommended Content

1. Main chat interface (required)
2. Model selector showing providers
3. Dark mode with code highlighting
4. Settings panel
5. Conversation history
6. Analytics display

See `SCREENSHOT_GUIDE.md` for detailed instructions

---

## 🛡️ Privacy Summary

**Molten collects NO data.**

When filling out App Privacy:
- Data Used to Track You: **No**
- Data Linked to You: **No Data Collected**
- Data Not Linked to You: **No Data Collected**

This is the best possible privacy rating on the App Store.

Full questionnaire answers: `PRIVACY_NUTSHELL.md`

---

## ⚠️ Common Issues

### Build Rejected

**Issue**: "App is incomplete"  
**Fix**: Ensure all features work, no placeholder buttons

**Issue**: "Privacy policy missing"  
**Fix**: Make sure privacy URL is live and accessible

**Issue**: "App crashes on launch"  
**Fix**: Test on clean device, check entitlements

### Metadata Rejected

**Issue**: "Misleading description"  
**Fix**: Be clear about Ollama/Swama requirements

**Issue**: "Screenshots don't match app"  
**Fix**: Use current app UI, not mockups

See `PRE_SUBMISSION_CHECKLIST.md` for complete troubleshooting

---

## 📈 Post-Submission

### Monitor Status

Check App Store Connect → Molten → Activity

Statuses:
- **Waiting for Review**: In queue
- **In Review**: Being reviewed (24-48 hrs)
- **Pending Developer Release**: Approved
- **Ready for Sale**: Live!

### If Approved

1. Click "Release this version" (if manual)
2. Share on social media
3. Monitor reviews
4. Track downloads in Sales and Trends

### If Rejected

1. Read rejection reason carefully
2. Fix issues
3. Increment build number (1 → 2)
4. Upload new build
5. Respond in Resolution Center
6. Resubmit

---

## 📚 Documentation Index

All documentation is in `/Users/eplt/SCM/molten/`:

### For App Store
- `APP_STORE_SUBMISSION.md` - Main guide
- `PRE_SUBMISSION_CHECKLIST.md` - Checklist
- `RELEASE_NOTES.md` - What's New
- `APP_STORE_DESCRIPTION.md` - Description
- `MARKETING_KEYWORDS.md` - Keywords
- `SCREENSHOT_GUIDE.md` - Screenshots

### For Privacy
- `PRIVACY_NUTSHELL.md` - Questionnaire answers
- `PRIVACY_URL_CONTENT.md` - Privacy policy
- `SUPPORT_URL_CONTENT.md` - Support page

### Existing Documentation
- `README.md` - User guide
- `ARCHITECTURE.md` - Technical details
- `CONTRIBUTING.md` - How to contribute
- `PRIVACY.md` - Privacy policy (GitHub version)
- `SUPPORT.md` - Support info
- `LICENSE` - License file

---

## 🎉 Ready to Submit!

You have everything you need. Follow the checklist in `PRE_SUBMISSION_CHECKLIST.md` and good luck with your submission!

**Questions?** Review the documentation or contact yourself at [YOUR_EMAIL_HERE]

---

**Molten** - Local AI. On Your Terms. 🍎
