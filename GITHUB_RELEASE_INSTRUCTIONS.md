# GitHub Release Instructions - v1.0.1

## Quick Start (Recommended)

### Option 1: Use the Release Script (Easiest)

```bash
cd /Users/eplt/SCM/molten
./scripts/release.sh
```

This script will:
1. ✅ Check you're in the right directory
2. ✅ Show git status
3. ✅ Add all files
4. ✅ Create commit with proper message
5. ✅ Create git tag v1.0.1
6. ✅ Push to GitHub (if you confirm)

### Option 2: Manual Commands

```bash
cd /Users/eplt/SCM/molten

# Add all changes
git add .

# Commit
git commit -m "Release v1.0.1 - Bug Fixes & Performance Improvements

Fixed:
- Stop button state issue
- Auto-scroll during streaming  
- Memory leak in SwamaService
- O(n²) string concatenation

Improved:
- MessageSD caching
- ScrollView handlers
- Swift 6 warnings

Build: 4"

# Tag
git tag -a v1.0.1 -m "Version 1.0.1"

# Push
git push origin main && git push origin v1.0.1
```

---

## What's Included in This Release

### Files Being Committed

**Source Code Changes** (12 files modified):
- `Molten/Stores/ConversationStore.swift` - Major refactor
- `Molten/Services/SwamaService.swift` - Buffer fixes
- `Molten/SwiftData/Models/MessageSD.swift` - Caching
- `Molten/UI/Shared/Chat/Components/MessageListVIew.swift` - Scroll optimization
- `Molten/UI/Shared/Chat/Chat.swift` - Warning fixes
- `Molten/UI/Shared/Sidebar/SidebarView.swift` - Warning fixes
- `Molten/UI/iOS/ChatView_iOS.swift` - Warning fixes
- `Molten/UI/macOS/Chat/Components/InputFields_macOS.swift` - Warning fixes
- `Molten/UI/macOS/Components/PromptPanelView.swift` - Warning fixes
- `Molten/Services/OllamaService.swift` - Warning fixes
- `Molten/Extensions/SplashSyntaxHighlighter+Extension.swift` - Warning fixes
- `Molten.xcodeproj/project.pbxproj` - Build settings

**New Documentation** (15 files added):
- `APPLICATION_FOR_SUBMISSION.md` - Submission package index
- `APP_STORE_DESCRIPTION.md` - App Store description
- `APP_STORE_SUBMISSION.md` - Complete submission guide
- `CODE_REVIEW_2026_03_13.md` - Bug fix documentation
- `GITHUB_RELEASE_GUIDE.md` - This guide
- `MARKETING_KEYWORDS.md` - App Store keywords
- `PERFORMANCE_REVIEW_2026_03_13.md` - Performance optimization docs
- `PRE_SUBMISSION_CHECKLIST.md` - Submission checklist
- `PRIVACY_NUTSHELL.md` - Privacy questionnaire
- `PRIVACY_URL_CONTENT.md` - Privacy policy
- `RELEASE_NOTES.md` - App Store release notes
- `RELEASE_NOTES_1.0.1_OPTIONS.md` - Release notes options
- `SCREENSHOT_GUIDE.md` - Screenshot guide
- `SUBMISSION_QUICK_REF.md` - Quick reference
- `SUPPORT_URL_CONTENT.md` - Support page content

**Excluded** (added to .gitignore):
- `QWEN.md` - AI assistant context (not useful for users)

---

## After Pushing to GitHub

### 1. Create GitHub Release

Go to: https://github.com/OnDemandWorld/molten/releases/new

**Settings:**
- **Tag version**: v1.0.1 (should already exist)
- **Target**: main
- **Title**: Molten v1.0.1 - Bug Fixes & Performance

**Release Notes** (copy this):

```markdown
## 🐛 Bug Fixes

- **Stop Button State**: Fixed issue where stop button would get stuck after response completion. Button now reliably reverts to send button in all scenarios.
- **Auto-Scroll**: Improved scrolling behavior during streaming - now smoother and follows content in real-time.
- **Memory Leak**: Fixed buffer handling in SwamaService that could cause memory growth during long responses.

## ⚡ Performance Improvements

- **String Handling**: Changed from O(n²) string concatenation to O(n) array buffer for streaming responses
- **MessageSD Caching**: Added caching for computed properties (think, hasThink, realContent) to reduce repeated string scanning
- **UI Updates**: Optimized throttling and reduced unnecessary SwiftUI updates

## 🔧 Code Quality

- Fixed Swift 6 concurrency warnings
- Improved error handling in streaming completion
- Better state management in ConversationStore
- Fixed various build warnings

## 📊 Technical Details

**Files Modified**: 12 source files + 15 documentation files  
**Build**: 4  
**Minimum OS**: macOS 14.0+, iOS 17.0+, iPadOS 17.0+

## 🙏 Thanks

Thanks to early users for reporting issues! Your feedback makes Molten better.

## 📥 Installation

Download the latest release or build from source:

```bash
git clone https://github.com/OnDemandWorld/molten.git
cd molten
open Molten.xcodeproj
```

Then build and run (⌘R).

## 📝 Full Changelog

See [CODE_REVIEW_2026_03_13.md](CODE_REVIEW_2026_03_13.md) and [PERFORMANCE_REVIEW_2026_03_13.md](PERFORMANCE_REVIEW_2026_03_13.md) for detailed technical documentation.

---

**Full changelog**: https://github.com/OnDemandWorld/molten/compare/v1.0...v1.0.1
```

### 2. Verify Release

Check these pages:
- https://github.com/OnDemandWorld/molten/tags - Verify tag exists
- https://github.com/OnDemandWorld/molten/releases - Verify release is published
- https://github.com/OnDemandWorld/molten/commits/main - Verify commits

### 3. Update README (Optional)

Add version badge to README.md:

```markdown
![Version](https://img.shields.io/badge/version-1.0.1-blue)
![Build](https://img.shields.io/badge/build-4-green)
```

---

## Checklist

- [ ] Run release script or manual commands
- [ ] Verify push succeeded
- [ ] Create GitHub Release with notes
- [ ] Verify tag exists
- [ ] Check release page
- [ ] Celebrate! 🎉

---

## Troubleshooting

### "Build number must be higher"

If you get an error about build number, update in Xcode:
- Version: 1.0.1
- Build: 4 (must be > 3, the App Store build)

### "Tag already exists"

Delete the tag and recreate:
```bash
git tag -d v1.0.1
git push origin :refs/tags/v1.0.1
git tag -a v1.0.1 -m "Version 1.0.1"
git push origin v1.0.1
```

### "Permission denied"

Make sure you have write access:
```bash
git remote -v
# Should show your GitHub repo
```

If not, add it:
```bash
git remote add origin https://github.com/OnDemandWorld/molten.git
```

---

## What's Next?

After the GitHub release:

1. **App Store**: Submit v1.0.1 to App Store Connect
2. **Announce**: Share on social media
3. **Monitor**: Watch for issues/feedback
4. **Plan**: Start working on v1.1.0 features

---

**Good luck!** 🍀

**Molten** - Local AI. On Your Terms. 🍎
