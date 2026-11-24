#!/bin/bash

# Molten GitHub Release Preparation (parameterized — review 2026-11-24:
# this script used to be hard-coded to v1.0.1 and would re-tag a stale
# version on any re-run).
#
# Usage: ./scripts/release.sh <version>   e.g. ./scripts/release.sh 2.0.2
# Run from the project root. App Store builds go through
# docs/BUILD_AUTOMATION.md; this script only handles the git tag + GitHub
# release prep.

set -e  # Exit on error

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "❌ Usage: ./scripts/release.sh <version>   e.g. ./scripts/release.sh 2.0.2"
    exit 1
fi

# Check we're in the right directory
if [ ! -f "Molten.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Please run this script from the molten project root"
    exit 1
fi

# Refuse to re-tag an existing release
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "❌ Tag v$VERSION already exists — nothing to do."
    exit 1
fi

# Check git status
echo "📊 Current git status:"
git status --short
echo ""

# Confirm before proceeding
read -p "✅ Ready to commit and tag v$VERSION? (y/n) " -n 1 -r
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
git commit -m "Release v$VERSION"

echo "✅ Commit created"
echo ""

# Create tag
echo "🏷️  Creating git tag v$VERSION..."
git tag -a "v$VERSION" -m "Version $VERSION

See CHANGELOG / release notes and docs/ for details."

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
    git push origin "v$VERSION"
    echo "✅ Pushed successfully!"
    echo ""
    echo "🎉 Release v$VERSION is live on GitHub!"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Go to https://github.com/OnDemandWorld/molten/releases"
    echo "   2. Click 'Create a new release' from tag v$VERSION"
    echo "   3. Write release notes"
    echo "   4. Publish release"
    echo ""
else
    echo "⚠️  Changes committed locally but not pushed"
    echo "   Run: git push origin main && git push origin v$VERSION"
    echo ""
fi

echo "✅ Done!"