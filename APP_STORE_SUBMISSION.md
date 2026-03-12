# App Store Submission Package - Molten v1.0

## 📦 Submission Checklist

### Required Files Created
- [x] `RELEASE_NOTES.md` - What's New text for App Store Connect
- [x] `APP_STORE_DESCRIPTION.md` - Full app description for App Store Connect
- [x] `MARKETING_KEYWORDS.md` - Keywords for App Store Connect
- [x] `PRIVACY_NUTSHELL.md` - Privacy details for App Store Connect questionnaire
- [x] `SUPPORT_URL_CONTENT.md` - Content for support webpage
- [x] `PRIVACY_URL_CONTENT.md` - Content for privacy policy webpage

---

## 📝 App Store Connect Information

### App Information

**Primary Category**: Productivity  
**Secondary Category**: Developer Tools  
**Age Rating**: 4+  

**App Name**: Molten - Local AI Chat  
**Subtitle**: Run LLMs Offline, Private  
**Bundle ID**: com.ondemandworld.molten (verify in Xcode)

**Version**: 1.0.0  
**Build**: 1  

---

## 🆕 Release Notes (What's New)

See: `RELEASE_NOTES.md`

**Character Count**: ~450 characters (well under 4000 limit)

---

## 📖 App Description

See: `APP_STORE_DESCRIPTION.md`

**Character Count**: ~2,800 characters (well under 4000 limit)

---

## 🔑 Keywords

See: `MARKETING_KEYWORDS.md`

**Keywords**: `local,ai,llm,ollama,private,offline,mac,chat,llama,ml`  
**Character Count**: 50/100 characters

---

## 🛡️ Privacy & Data Safety

### Data Collection Summary
**Molten collects NO data. Period.**

- ❌ No analytics
- ❌ No tracking
- ❌ No identifiers
- ❌ No usage data
- ❌ No diagnostics
- ❌ No user content collected
- ❌ No third-party data sharing

### App Privacy Details (App Store Connect)

When filling out the App Privacy questionnaire:

**Data Used to Track You**: None  
**Data Linked to You**: None  
**Data Not Linked to You**: None  

**Privacy Policy URL**: https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md  
**Support URL**: https://github.com/OnDemandWorld/molten/blob/main/SUPPORT.md

See `PRIVACY_NUTSHELL.md` for detailed questionnaire answers.

---

## 🖼️ Screenshots & Preview

### Required Screenshots

Upload screenshots for these display sizes:

**macOS (App Store):**
- 1280x800 or 1440x900 (13-inch MacBook Pro)
- 1440x900 or 2880x1800 (16-inch MacBook Pro)

**iOS (if universal):**
- 6.7" display (iPhone 14/15 Pro Max) - 1290x2796
- 6.5" display (iPhone 11 Pro Max) - 1242x2688
- 5.5" display (iPhone 8 Plus) - 1242x2208

**iPadOS (if universal):**
- 12.9" iPad Pro (3rd gen) - 2048x2732
- 11" iPad Pro (3rd gen) - 1668x2388

### Screenshot Recommendations

1. **Main Chat Interface** - Show conversation with streaming response
2. **Model Selector** - Show multiple model providers (Ollama, Swama, Apple)
3. **Settings Panel** - Show configuration options
4. **Dark Mode** - Show elegant dark theme
5. **Analytics Display** - Show performance metrics (tokens/sec)
6. **Sidebar** - Show conversation history

### App Preview Video (Optional but Recommended)

30-second video showing:
1. App launch
2. Selecting a model
3. Typing a prompt
4. Streaming response with analytics
5. Stop button functionality

---

## 🏷️ Build Information

### Version Number
**1.0.0** - Initial public release

### Build Number
**1** - First build

### Minimum OS Requirements

**macOS**: 14.0+ (Sonoma)  
**iOS**: 17.0+  
**iPadOS**: 17.0+

### Supported Devices

- Mac with Apple Silicon (M1, M2, M3, or later)
- iPhone (iOS 17.0+)
- iPad (iPadOS 17.0+)

**Note**: Apple Foundation Models require macOS 26.0+ with Apple Silicon

---

## 🔧 Technical Requirements

### Entitlements & Permissions

**Required Entitlements:**
- Network client access (for Ollama/Swama communication)
- App Sandbox (enabled)

**Required Permissions:**
- **Accessibility** (Optional): For text manipulation features
  - Usage: "Molten can perform operations on selected text such as fixing grammar, extending texts as well as custom commands."

**Network Access:**
- Localhost connections (Ollama: port 11434, Swama: port 28100)
- No external network calls (all processing is local)

### ATS Configuration

App Transport Security allows arbitrary loads (required for localhost connections to Ollama/Swama).

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

**Justification**: Required for local AI model communication (localhost). No external insecure connections are made.

---

## 📄 Required URLs

### Support URL
**Recommended**: https://github.com/OnDemandWorld/molten/issues  
**Alternative**: Create simple GitHub Pages site

See `SUPPORT_URL_CONTENT.md` for page content.

### Privacy Policy URL
**URL**: https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md

See `PRIVACY_URL_CONTENT.md` for hosted page content.

### Marketing URL (Optional)
**URL**: https://github.com/OnDemandWorld/molten

---

## 🎯 App Review Information

### Notes for App Review

**Important**: Add these notes in App Store Connect under "App Review Information" → "Notes"

```
Molten is a privacy-first local AI chat application that runs LLMs completely offline.

KEY FEATURES:
• Runs local LLMs (Ollama, Swama, Apple Foundation Models)
• 100% offline processing - no data leaves the device
• No data collection, analytics, or tracking
• Native SwiftUI app (not a web wrapper)

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
```

### Demo Account
**Not Required** - App functions without user account

### Contact Information
Ensure your contact email is current in App Store Connect for reviewer questions.

---

## 🚀 Submission Steps

### 1. Pre-Submission Checklist

- [ ] Update version number in Xcode (Info.plist)
- [ ] Set build number
- [ ] Archive build in Xcode (Product → Archive)
- [ ] Upload to App Store Connect
- [ ] Verify build appears in App Store Connect (takes ~10 min)
- [ ] Complete App Store Connect metadata (use files in this package)
- [ ] Upload screenshots (minimum 3 required)
- [ ] Submit for review

### 2. App Store Connect Metadata

Fill out these sections in App Store Connect:

1. **App Information**
   - Name, Subtitle, Category, Age Rating

2. **Pricing and Availability**
   - Price tier (Free recommended for launch)
   - Availability date

3. **App Privacy**
   - Complete privacy questionnaire (see PRIVACY_NUTSHELL.md)

4. **Version Information**
   - Description, Keywords, Release Notes
   - Screenshots, App Preview (optional)

5. **Build**
   - Select uploaded build
   - Provide review notes if needed

### 3. Final Review

- [ ] All metadata complete
- [ ] Screenshots uploaded for all required sizes
- [ ] Privacy questionnaire complete
- [ ] Build selected
- [ ] Pricing set
- [ ] Contact info current

### 4. Submit for Review

Click "Add for Review" → "Submit to App Review"

**Typical Review Time**: 24-48 hours

---

## 📊 Post-Submission

### Monitor Status

Check App Store Connect regularly:

1. **Waiting for Review** → Normal queue position
2. **In Review** → Being reviewed (24-48 hrs)
3. **Pending Developer Release** → Approved, ready to release
4. **Ready for Sale** → Live on App Store

### If Rejected

1. Read rejection reason carefully
2. Fix issues
3. Increment build number
4. Resubmit with response to rejection

### Common Rejection Reasons (and How We Avoid Them)

✅ **Guideline 2.1 - App Completeness**: App is fully functional  
✅ **Guideline 4.0 - Design**: Native SwiftUI, not web wrapper  
✅ **Guideline 5.1 - Privacy**: No data collection, clear privacy policy  
✅ **Guideline 5.2 - Legal**: All third-party libs properly licensed (Apache 2.0)  

---

## 📞 Support Contact

**Developer**: OnDemandWorld  
**Email**: [YOUR_EMAIL_HERE]  
**Website**: https://github.com/OnDemandWorld/molten

Update this with your actual contact information before submission.

---

## 📄 License

Apache License 2.0 - See LICENSE file

---

**Good luck with your submission! 🍀**
