# GitHub Release Preparation Guide - v1.0.1

## What to Include vs Exclude

### ✅ INCLUDE in Git (Recommended)

#### Source Code & Project Files
- [x] All Swift source files
- [x] Xcode project file (`.xcodeproj/project.pbxproj`)
- [x] Asset catalogs
- [x] Entitlements and Info.plist

#### User-Facing Documentation
- [x] `README.md` - Main project documentation
- [x] `LICENSE` - License file
- [x] `CONTRIBUTING.md` - Contribution guidelines
- [x] `SUPPORT.md` - Support information
- [x] `PRIVACY.md` - Privacy policy
- [x] `ARCHITECTURE.md` - Technical architecture (useful for contributors)

#### Development Documentation (Recommended for Open Source)
- [x] `CODE_REVIEW_2026_03_13.md` - Shows bug fix history
- [x] `PERFORMANCE_REVIEW_2026_03_13.md` - Shows optimization work
- [x] `RELEASE_NOTES_1.0.1_OPTIONS.md` - Release notes options
- [x] `QWEN.md` - Project context for AI assistants

#### App Store Submission Docs (Optional but Transparent)
These show your professional process and can help other developers:
- [ ] `APP_STORE_SUBMISSION.md` - Submission guide
- [ ] `SUBMISSION_QUICK_REF.md` - Quick reference
- [ ] `PRE_SUBMISSION_CHECKLIST.md` - Checklist
- [ ] `APP_STORE_DESCRIPTION.md` - App Store description
- [ ] `RELEASE_NOTES.md` - Release notes
- [ ] `MARKETING_KEYWORDS.md` - Keywords
- [ ] `PRIVACY_NUTSHELL.md` - Privacy questionnaire
- [ ] `PRIVACY_URL_CONTENT.md` - Privacy policy content
- [ ] `SUPPORT_URL_CONTENT.md` - Support page content
- [ ] `SCREENSHOT_GUIDE.md` - Screenshot guide
- [ ] `APPLICATION_FOR_SUBMISSION.md` - Package index

**My Recommendation**: Include the submission docs. It's transparent, helps other indie developers, and shows professionalism.

---

### ❌ EXCLUDE (Add to .gitignore)

#### Build & Derived Data
- [x] `build/`
- [x] `DerivedData/`
- [x] `*.app/` (built app)
- [x] `Molten.app/` (already in .gitignore)

#### User-Specific Files
- [x] `*.xcuserstate`
- [x] `xcuserdata/`
- [x] `.DS_Store`

#### Sensitive Files (If Any)
- [ ] API keys (none currently)
- [ ] `.env` files
- [ ] Certificates
- [ ] Provisioning profiles

---

## Recommended .gitignore Updates

Add these to `.gitignore` to keep repo clean:

```gitignore
# App Store Submission (optional - exclude if you don't want these public)
# Uncomment to hide submission docs
# APP_STORE_*.md
# SUBMISSION_*.md
# PRE_SUBMISSION_CHECKLIST.md
# SCREENSHOT_GUIDE.md
# PRIVACY_NUTSHELL.md
# *_URL_CONTENT.md
# APPLICATION_FOR_SUBMISSION.md

# Code Review & Performance docs (keep these - they're valuable)
# CODE_REVIEW_*.md
# PERFORMANCE_REVIEW_*.md
```

---

## Git Commands for v1.0.1 Release

### 1. Stage All Changes

```bash
cd /Users/eplt/SCM/molten

# Add all changes
git add .
```

### 2. Review What Will Be Committed

```bash
# See what's staged
git status

# See diff
git diff --cached
```

### 3. Commit with Good Message

```bash
git commit -m "Release v1.0.1 - Bug Fixes & Performance Improvements

Fixed:
- Stop button state issue (now reliably reverts after responses)
- Auto-scroll during streaming (smoother, more responsive)
- Memory leak in SwamaService buffer handling
- O(n²) string concatenation performance issue

Improved:
- MessageSD computed property caching
- ScrollView onChange handlers
- Swift 6 concurrency warnings

Build: 4 (App Store requires build > 3)"
```

### 4. Create Git Tag

```bash
# Create annotated tag
git tag -a v1.0.1 -m "Version 1.0.1 - Bug Fixes & Performance"

# Or lightweight tag
git tag v1.0.1
```

### 5. Push to GitHub

```bash
# Push commits
git push origin main

# Push tags
git push origin v1.0.1

# Or push all tags at once
git push origin --tags
```

### 6. Verify on GitHub

Visit: https://github.com/OnDemandWorld/molten/tags

---

## GitHub Release Notes

When creating the GitHub Release (different from git tag):

### Go to: GitHub → Releases → Create a new release

**Tag version**: v1.0.1  
**Target**: main  
**Title**: Molten v1.0.1 - Bug Fixes & Performance

**Description** (copy this):

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

**Files Modified**: 12 files
- `ConversationStore.swift` - Major refactor of streaming state management
- `SwamaService.swift` - Buffer management fixes
- `MessageSD.swift` - Computed property caching
- `MessageListVIew.swift` - Scroll optimization
- And 8 more files with improvements

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

---

## File Recommendations

### Include These (Already Tracked)
- ✅ All Swift source files
- ✅ Xcode project
- ✅ README.md, LICENSE, etc.
- ✅ ARCHITECTURE.md, CONTRIBUTING.md

### Include These (New - App Store Docs)
These are valuable for transparency and helping other developers:
- ✅ APP_STORE_SUBMISSION.md
- ✅ SUBMISSION_QUICK_REF.md
- ✅ PRE_SUBMISSION_CHECKLIST.md
- ✅ SCREENSHOT_GUIDE.md
- ✅ All other submission docs

**Why include them:**
1. **Transparency** - Shows your professional process
2. **Helps other indie devs** - Many struggle with App Store submission
3. **Good for credibility** - Shows you're serious about the app
4. **Open source spirit** - Share knowledge, not just code

### Include These (Code Review Docs)
- ✅ CODE_REVIEW_2026_03_13.md
- ✅ PERFORMANCE_REVIEW_2026_03_13.md
- ✅ RELEASE_NOTES_1.0.1_OPTIONS.md

**Why:** Shows the evolution of the codebase and documents important fixes.

### Exclude These (Add to .gitignore)
- ❌ QWEN.md (AI assistant context - not useful for users)
- ❌ Any local config files

---

## Quick Commands (Copy & Paste)

```bash
# Navigate to project
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

## After Pushing

1. **Create GitHub Release**:
   - Go to https://github.com/OnDemandWorld/molten/releases
   - Click "Create a new release"
   - Select tag v1.0.1
   - Copy release notes from above
   - Publish

2. **Update README** (Optional):
   - Add badge showing latest version
   - Update installation instructions if needed

3. **Announce** (Optional):
   - Post on Twitter/X
   - Share in relevant communities
   - Update any landing pages

---

## Checklist

- [ ] Review git status
- [ ] Decide which docs to include (recommend: all except QWEN.md)
- [ ] Add files: `git add .`
- [ ] Commit with good message
- [ ] Create tag: `git tag -a v1.0.1`
- [ ] Push: `git push origin main --tags`
- [ ] Create GitHub Release with notes
- [ ] Verify on GitHub
- [ ] Celebrate! 🎉

---

**Good luck with your release!** 🍀
