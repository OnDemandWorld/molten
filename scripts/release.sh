#!/bin/bash

# Molten v1.0.1 GitHub Release Script
# Run this from the project root directory

set -e  # Exit on error

echo "🚀 Molten v1.0.1 GitHub Release Preparation"
echo "==========================================="
echo ""

# Check we're in the right directory
if [ ! -f "Molten.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Please run this script from the molten project root"
    exit 1
fi

# Check git status
echo "📊 Current git status:"
git status --short
echo ""

# Confirm before proceeding
read -p "✅ Ready to commit and tag v1.0.1? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborted"
    exit 0
fi

# Add all changes
echo "📦 Adding files to git..."
git add .
echo "✅ Files added"
echo ""

# Show what will be committed
echo "📋 Files to be committed:"
git status --short
echo ""

# Commit
echo "💾 Creating commit..."
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
- State management in ConversationStore

Build: 4 (App Store)"

echo "✅ Commit created"
echo ""

# Create tag
echo "🏷️  Creating git tag v1.0.1..."
git tag -a v1.0.1 -m "Version 1.0.1 - Bug Fixes & Performance Improvements

This release fixes critical bugs and improves performance:
- Stop button state management
- Auto-scroll during streaming
- Memory leak fixes
- String concatenation optimization (O(n²) → O(n))

See CODE_REVIEW_2026_03_13.md and PERFORMANCE_REVIEW_2026_03_13.md for details."

echo "✅ Tag created"
echo ""

# Show remote
echo "🌐 Remote repositories:"
git remote -v
echo ""

# Push
read -p "🚀 Push to GitHub? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📤 Pushing to GitHub..."
    git push origin main
    git push origin v1.0.1
    echo "✅ Pushed successfully!"
    echo ""
    echo "🎉 Release v1.0.1 is live on GitHub!"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Go to https://github.com/OnDemandWorld/molten/releases"
    echo "   2. Click 'Create a new release' from tag v1.0.1"
    echo "   3. Copy release notes from GITHUB_RELEASE_GUIDE.md"
    echo "   4. Publish release"
    echo ""
else
    echo "⚠️  Changes committed locally but not pushed"
    echo "   Run: git push origin main && git push origin v1.0.1"
    echo ""
fi

echo "✅ Done!"
