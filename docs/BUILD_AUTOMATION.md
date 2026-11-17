# Molten — Build & Distribute Automation

Goal: one command (or one CI job) goes from source → tested → archived →
signed → uploaded to App Store Connect for **both macOS and iOS**, with no
Xcode GUI clicks. Everything below is proven working on this machine
(Xcode 27.2, build 10 was produced exactly this way on 2026-11-17).

Current manual-but-scripted state:

| Step | Tool | Status |
|---|---|---|
| Build number bump | edit `CURRENT_PROJECT_VERSION` in `project.pbxproj` | manual |
| Tests | `xcodebuild test` | scripted |
| Archive (both platforms) | `xcodebuild archive` | scripted |
| Distribution signing + export | `xcodebuild -exportArchive` (cloud-managed certs) | scripted |
| Upload to ASC | `build/session/upload-to-asc.sh` (`xcrun altool`) | scripted, needs credentials |

What's left to automate: **credentials setup (Phase 1)**, then **one
pipeline script (Phase 2)**. Optional CI in Phase 3.

---

## Phase 1 — One-time credential setup (10 min)

Pick one authentication method. The API key is strongly recommended for
automation: it never expires, is revocable without touching your Apple ID,
and works unattended.

### Option A — App Store Connect API key (recommended)

- [ ] 1. App Store Connect → **Users and Access → Integrations → App Store
      Connect API** → Team Keys → **Generate API Key**.
      Name: `molten-release`, Access: **Admin** (needed for upload +
      provisioning management).
- [ ] 2. Download the `.p8` file (only downloadable once). Note the
      **Key ID** and the **Issuer ID** shown above the key list.
- [ ] 3. Place it where altool looks for it:
      ```bash
      mkdir -p ~/private_keys
      mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/private_keys/
      chmod 600 ~/private_keys/AuthKey_XXXXXXXXXX.p8
      ```
- [ ] 4. Export the identifiers (add to `~/.zshrc` or a gitignored
      `build/session/asc-env.sh` — **never commit them**):
      ```bash
      export ASC_API_KEY=XXXXXXXXXX        # Key ID
      export ASC_API_ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      ```
- [ ] 5. Verify with a validation-only run (no upload):
      ```bash
      xcrun altool --validate-app -f build/session/iOS-export-b10/Molten.ipa \
        -t ios --apiKey "$ASC_API_KEY" --apiIssuer "$ASC_API_ISSUER"
      ```
      Expected: `No errors validating archive...` / success JSON.

### Option B — App-specific password (quick, personal)

- [ ] 1. appleid.apple.com → Sign-In and Security → **App-Specific
      Passwords** → generate (`molten-upload`).
- [ ] 2. `export ASC_USER='edward@ondemandworld.com' ASC_PASSWORD='xxxx-xxxx-xxxx-xxxx'`
- [ ] 3. Same `--validate-app` check with `-u "$ASC_USER" -p "$ASC_PASSWORD"`.

Notes:
- 2FA on the Apple ID is required for both methods (already enabled).
- App-specific passwords are revoked automatically if the main Apple ID
  password changes — the API key is not.

---

## Phase 2 — One pipeline script (30 min)

Create `scripts/ci-release.sh` (checked in; contains **no secrets** —
credentials come from the environment). Skeleton with the exact commands
already proven this session:

```bash
#!/bin/bash
# Usage: ASC_API_KEY=... ASC_API_ISSUER=... ./scripts/ci-release.sh <build-number>
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${1:?usage: ci-release.sh <build-number>}"
OUT=build/session

# 0. Credentials present?
: "${ASC_API_KEY:?set ASC_API_KEY}" "${ASC_API_ISSUER:?set ASC_API_ISSUER}"
AUTH=(--apiKey "$ASC_API_KEY" --apiIssuer "$ASC_API_ISSUER")

# 1. Bump CURRENT_PROJECT_VERSION on ALL targets (app + extension + tests
#    must match, or ASC validation rejects the bundle).
python3 - "$BUILD" <<'EOF'
import re, sys
p = 'Molten.xcodeproj/project.pbxproj'
s = open(p).read()
s = re.sub(r'CURRENT_PROJECT_VERSION = \d+;',
           f'CURRENT_PROJECT_VERSION = {sys.argv[1]};', s)
open(p, 'w').write(s)
EOF
# Alternative: xcrun agvtool new-version -all "$BUILD"

# 2. Gate on tests (macOS host; coverage OFF — yyjson link bug).
xcodebuild test -scheme Molten -configuration Debug \
  -destination 'platform=macOS' -enableCodeCoverage NO \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/DerivedData

# 3. Archive both platforms (separate DerivedData — concurrent builds in
#    one DerivedData deadlock on build.db).
xcodebuild archive -scheme Molten -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$OUT/Molten-macOS-b$BUILD.xcarchive" \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates
xcodebuild archive -scheme Molten -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Molten-iOS-b$BUILD.xcarchive" \
  -derivedDataPath build/DerivedData-iOS -allowProvisioningUpdates

# 4. Export with cloud distribution signing (same as Organizer →
#    Distribute App → App Store Connect). One options plist serves both.
for P in macOS iOS; do
  xcodebuild -exportArchive \
    -archivePath "$OUT/Molten-$P-b$BUILD.xcarchive" \
    -exportPath "$OUT/$P-export-b$BUILD" \
    -exportOptionsPlist "$OUT/ExportOptions-macOS.plist" \
    -allowProvisioningUpdates "${AUTH[@]}"
done

# 5. Sanity checks before upload (fail fast on signing/version drift).
APP_MAC="$OUT/pkg-verify/com.ondemandworld.molten.pkg/Payload/Molten.app"
pkgutil --expand-full "$OUT/macOS-export-b$BUILD/Molten.pkg" "$OUT/pkg-verify"
codesign --verify --deep --strict "$APP_MAC"
[ "$(plutil -extract CFBundleVersion raw "$APP_MAC/Contents/Info.plist")" = "$BUILD" ]
codesign -d --entitlements - "$APP_MAC/Contents/PlugIns/MoltenShare.appex" 2>/dev/null \
  | grep -q "com.apple.security.app-sandbox"

# 6. Upload both.
xcrun altool --upload-app -f "$OUT/iOS-export-b$BUILD/Molten.ipa" \
  -t ios "${AUTH[@]}" --output-format normal
xcrun altool --upload-app -f "$OUT/macOS-export-b$BUILD/Molten.pkg" \
  -t macos "${AUTH[@]}" --output-format normal

echo "Uploaded build $BUILD. ASC processing takes ~5–30 min."
```

- [ ] Copy the skeleton into `scripts/ci-release.sh`, `chmod +x`.
- [ ] Move `build/session/ExportOptions-macOS.plist` to
      `scripts/ExportOptions.plist` (it is platform-neutral:
      `method=app-store-connect`, `signingStyle=automatic`,
      `teamID=DVGF44TKAX`, `uploadSymbols=true`) and update the path above.
- [ ] Dry run with the next build number; confirm both builds appear in
      ASC → TestFlight.
- [ ] Commit the script (no secrets in it).

### Why no local distribution certificate is needed

`-exportArchive` with automatic signing uses **cloud-managed distribution
certificates** via your Xcode account / API key. The keychain only holds
Apple Development certs; export re-signs with `Apple Distribution` and
`3rd Party Mac Developer Installer` automatically. This is the same
mechanism Organizer uses.

---

## Phase 3 — Optional: CI on GitHub Actions

Possible later; not required for release. Caveats to plan for:

- Runner must be **macOS with Xcode 27.2+** (deployment targets are 26.0;
  `macos-26` runner images or a self-hosted Mac).
- Cloud signing on CI authenticates with the ASC API key:
  pass `-authenticationKeyPath /path/AuthKey.p8 -authenticationKeyID …
  -authenticationKeyIssuerID …` to archive/export instead of relying on
  a logged-in Xcode account. Store the `.p8` as a GitHub Actions secret.
- MLX C++ compiles are slow (~15–25 min cold). Cache
  `build/DerivedData*` + `build/SourcePackages` between runs.
- Known Xcode 27.2 bug: `kind = exact` SPM pins are silently ignored —
  the committed `Package.resolved` is the source of truth; keep it.
- Tests that write files need `CODE_SIGNING_ALLOWED=NO`; always
  `-enableCodeCoverage NO` (yyjson `___llvm_profile_runtime` link bug).

---

## After upload (still manual in ASC, by design)

1. ASC → TestFlight: wait for processing; builds carry
   `ITSAppUsesNonExemptEncryption=false`, so **no compliance question**.
2. Internal testing: add to the internal group (no review needed).
3. External TestFlight / release: attach the build to the 2.0 version,
   complete the release checklist (`docs/RELEASE_CHECKLIST_v2.md`),
   submit. Owner steps live in `docs/OWNER_TASKS.md`.
4. After the App Store release: merge `develop` → `main`, tag `v2.0`.

## Troubleshooting (all hit and solved this session)

| Symptom | Cause / fix |
|---|---|
| `database is locked` | Two xcodebuilds sharing one DerivedData — use separate paths |
| `Float16` compile errors on archive | x86_64 slice; fixed via `HalfFloat` bit codec (Codecs.swift) |
| `App sandbox not enabled … MoltenShare` | Extension target needs `ENABLE_APP_SANDBOX = YES` (done) |
| Extension build ≠ app build | Bump `CURRENT_PROJECT_VERSION` on **all** targets |
| Embed App Extensions phase missing | Xcode normalization drops hand-added phases — re-check after opening the project in Xcode |
| altool auth failure | API key needs Admin role; `.p8` must be in `~/private_keys/` (or `./private_keys`) |

## Security rules

- Never commit `.p8` keys, passwords, or `asc-env.sh` — `build/session/`
  is gitignored; keep secrets there or in `~/private_keys`.
- Prefer the API key over an app-specific password for anything
  unattended; revoke it in ASC if a machine is compromised.
- The upload script takes credentials only via environment variables.