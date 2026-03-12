# Pre-Submission Checklist

Complete ALL items before submitting to App Store Connect.

---

## ✅ Code & Build

- [ ] **Build succeeds without errors**
  ```bash
  xcodebuild -project Molten.xcodeproj -scheme Molten -configuration Release archive
  ```

- [ ] **No critical warnings** (Swift 6 concurrency warnings are OK)

- [ ] **Version number set**: 1.0.0 (in Xcode → Target → General)

- [ ] **Build number set**: 1 (in Xcode → Target → General)

- [ ] **Minimum OS versions correct**:
  - macOS: 14.0+
  - iOS: 17.0+
  - iPadOS: 17.0+

- [ ] **App icon included** (all required sizes in Assets.xcassets)

- [ ] **Launch screen configured** (or static launch image)

---

## ✅ Metadata Preparation

### Required Files Created
- [ ] `RELEASE_NOTES.md` - What's New text
- [ ] `APP_STORE_DESCRIPTION.md` - Full description
- [ ] `MARKETING_KEYWORDS.md` - Keywords
- [ ] `PRIVACY_NUTSHELL.md` - Privacy questionnaire answers
- [ ] `SUPPORT_URL_CONTENT.md` - Support page content
- [ ] `PRIVACY_URL_CONTENT.md` - Privacy policy content
- [ ] `APP_STORE_SUBMISSION.md` - This guide

### Metadata Ready
- [ ] App Name: "Molten - Local AI Chat"
- [ ] Subtitle: "Run LLMs Offline, Private"
- [ ] Primary Category: Productivity
- [ ] Secondary Category: Developer Tools
- [ ] Age Rating: 4+

---

## ✅ Screenshots

### Required Sizes (Upload to App Store Connect)

**macOS (Required - 2 minimum):**
- [ ] 1280x800 or 1440x900 (13-inch)
- [ ] 1440x900 or 2880x1800 (16-inch)

**iOS (If universal - 2 minimum for one size):**
- [ ] 6.7" (1290x2796) - iPhone 14/15 Pro Max
- [ ] 6.5" (1242x2688) - iPhone 11 Pro Max
- [ ] 5.5" (1242x2208) - iPhone 8 Plus

**iPadOS (If universal - 2 minimum for one size):**
- [ ] 12.9" (2048x2732) - iPad Pro
- [ ] 11" (1668x2388) - iPad Pro

### Screenshot Content
- [ ] Main chat interface (required)
- [ ] Model selector showing multiple providers
- [ ] Dark mode interface
- [ ] Settings panel
- [ ] Conversation history sidebar
- [ ] Analytics display (tokens/sec)

### Screenshot Tips
- Use actual device frames (not simulator bezels)
- Show app in use (not blank screens)
- Highlight key features
- Use high contrast, clear text
- Avoid placeholder text

---

## ✅ URLs

### Required URLs (Must be live before submission)

- [ ] **Support URL**: Live webpage with support content
  - Recommended: GitHub Pages or GitHub wiki
  - Content: See `SUPPORT_URL_CONTENT.md`
  - Test: Opens in browser, no 404

- [ ] **Privacy Policy URL**: Live webpage with privacy policy
  - Can be GitHub file: https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md
  - Or hosted page with content from `PRIVACY_URL_CONTENT.md`
  - Test: Opens in browser, no 404

- [ ] **Marketing URL** (Optional): 
  - GitHub repo: https://github.com/OnDemandWorld/molten

### Update Contact Info
- [ ] Replace `[YOUR_EMAIL_HERE]` in all markdown files
- [ ] Ensure App Store Connect contact email is current

---

## ✅ App Privacy

### Complete App Privacy Questionnaire

In App Store Connect → App Privacy:

- [ ] Data Used to Track You: **No**
- [ ] Data Linked to You: **No Data Collected**
- [ ] Data Not Linked to You: **No Data Collected**
- [ ] Privacy Policy URL: **Live URL**

**Reference**: See `PRIVACY_NUTSHELL.md` for all answers

---

## ✅ App Review Information

### Notes for Reviewer

In App Store Connect → App Review Information → Notes:

```
Molten is a privacy-first local AI chat application.

REQUIREMENTS:
• Users must install Ollama or Swama separately (free)
• Apple Foundation Models built-in on macOS 26.0+
• App works without these but no models will appear

NETWORK ACCESS:
• Only localhost (Ollama:11434, Swama:28100)
• No external network calls
• ATS exception for localhost only

ACCESSIBILITY API:
• Optional for text manipulation
• Not required for core functionality

TEST ACCOUNT: Not required
```

### Contact Info
- [ ] First Name
- [ ] Last Name
- [ ] Email
- [ ] Phone Number

### Demo Account
- [ ] **Not Required** - App works without account

### Third-Party Services
- [ ] List: OllamaKit, Splash, MarkdownUI, etc. (all open source, no data collection)

---

## ✅ Pricing & Availability

### App Store Connect → Pricing and Availability

- [ ] **Price Tier**: Select (Free recommended for launch)
- [ ] **Availability Date**: [DATE]
- [ ] **Countries/Regions**: Select all (or specific markets)

### App Store Connect → Agreements, Tax, and Banking

- [ ] **Paid Applications Agreement**: Signed (even for free apps)
- [ ] **Banking**: Set up (required even for free apps)
- [ ] **Tax**: Completed (if applicable)

---

## ✅ Version Information

### App Store Connect → iOS App / Version

- [ ] **Version Number**: 1.0.0
- [ ] **Copyright**: © 2026 OnDemandWorld
- [ ] **Description**: From `APP_STORE_DESCRIPTION.md`
- [ ] **Keywords**: From `MARKETING_KEYWORDS.md`
- [ ] **Release Notes**: From `RELEASE_NOTES.md`

### Screenshots & Preview
- [ ] Upload screenshots (all required sizes)
- [ ] App Preview video (optional but recommended)
- [ ] Verify all media displays correctly

---

## ✅ Build

### Upload Build

1. **Archive in Xcode**:
   ```
   Product → Archive
   ```

2. **Upload to App Store Connect**:
   - Click "Distribute App"
   - Select "App Store Connect"
   - Follow prompts

3. **Wait for Processing** (~10-15 minutes)

4. **Verify Build Appears**:
   - App Store Connect → Molten → Activity tab
   - Build number should appear

5. **Select Build**:
   - App Store Connect → Molten → Version 1.0.0
   - Click "Select a build"
   - Choose uploaded build

---

## ✅ Final Review

### Pre-Submission Review

- [ ] All metadata complete
- [ ] All screenshots uploaded
- [ ] Privacy questionnaire complete
- [ ] Build selected
- [ ] Pricing set
- [ ] URLs live and working
- [ ] Contact info current
- [ ] Reviewer notes added

### Test Flight (Optional but Recommended)

- [ ] Create TestFlight build
- [ ] Add internal testers
- [ ] Test on actual devices
- [ ] Verify all features work

---

## 🚀 Submit for Review

### Final Steps

1. **Save** all changes in App Store Connect
2. **Click "Add for Review"** (top right)
3. **Click "Submit to App Review"**
4. **Confirm** submission

### After Submission

- [ ] Note submission date/time
- [ ] Monitor email for App Review updates
- [ ] Check App Store Connect status regularly

### Typical Timeline

- **Waiting for Review**: Queue position (varies)
- **In Review**: 24-48 hours
- **Pending Developer Release**: Approved, ready
- **Ready for Sale**: Live on App Store

---

## 📞 If Rejected

### Don't Panic!

1. **Read rejection reason carefully**
2. **Fix the issues**
3. **Increment build number** (e.g., 1 → 2)
4. **Upload new build**
5. **Respond to rejection** in Resolution Center
6. **Resubmit**

### Common Issues & Fixes

**Guideline 2.1 - App Completeness**
- Ensure app is fully functional
- No placeholder features
- All buttons work

**Guideline 4.0 - Design**
- Native UI (✓ we use SwiftUI)
- Not a web wrapper (✓ we're native)

**Guideline 5.1 - Privacy**
- Clear privacy policy (✓ provided)
- No hidden data collection (✓ we collect none)

**Guideline 5.2 - Legal**
- Proper licenses for dependencies (✓ Apache 2.0)
- No trademark infringement

---

## 📊 Post-Approval

### Release

- [ ] Click "Release this version" (if manual release)
- [ ] Or wait for automatic release date

### Monitor

- [ ] App Store Connect → Sales and Trends
- [ ] Monitor reviews and ratings
- [ ] Respond to user reviews
- [ ] Track crashes (if any)

### Plan Updates

- [ ] Collect user feedback
- [ ] Monitor GitHub issues
- [ ] Plan v1.1.0 features

---

## 🎉 Good Luck!

**You're ready to submit!**

Questions? Review the documentation:
- `APP_STORE_SUBMISSION.md` - Main guide
- `RELEASE_NOTES.md` - What's New
- `APP_STORE_DESCRIPTION.md` - Description
- `MARKETING_KEYWORDS.md` - Keywords
- `PRIVACY_NUTSHELL.md` - Privacy answers

**Contact**: [YOUR_EMAIL_HERE]

---

**Molten** - Local AI. On Your Terms. 🍎
