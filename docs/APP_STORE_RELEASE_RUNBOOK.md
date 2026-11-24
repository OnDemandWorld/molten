# App Store Release Runbook — CLI + agent, reusable

**For:** Edward & Jack (and any coding agent working for either of you).
**Proven on:** Molten 2.0.1 build 13, 2026-11-24, Xcode 27.2, macOS. Both
platforms uploaded, attached to the version, and left READY_FOR_REVIEW.

> **GOLDEN RULE — never submit without an explicit human instruction.**
> Everything up to "ready to submit" is automatable. The final `submit`
> step (sending the app to Apple review) happens **only** when Edward or
> Jack explicitly says "submit it". Agents: stop after `prepare` and report.

---

## Part 1 — One-time setup (per person / per machine)

### 1.1 App Store Connect API key

1. https://appstoreconnect.apple.com → **Users and Access → Integrations →
   App Store Connect API → Team Keys → Generate API Key**.
2. Name it (e.g. `jack-release`), Access: **Admin**.
   - Admin (or App Manager) is required to *create versions* and *submit*.
   - **Also enable access to cloud-managed distribution certificates** for
     the key if you want fully unattended exports. Without it, export fails
     with `Cloud signing permission error` — see Part 5 fallback.
3. Download the `.p8` (**downloadable only once**). Note the **Key ID**
   (in the filename and the key list) and the **Issuer ID** (top of the page).
4. Place the key where the tools look for it — repo-local `private_keys/`
   (preferred; keeps everything inside the project folder) or `~/private_keys/`:
   ```bash
   mkdir -p private_keys
   mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 private_keys/
   chmod 600 private_keys/AuthKey_XXXXXXXXXX.p8
   ```
5. **Never commit keys.** `.gitignore` must contain:
   ```
   *.p8
   private_keys/
   ```
6. Identifiers (Key ID / Issuer ID are not secrets, but keep them out of
   committed source anyway — pass via env):
   ```bash
   export ASC_API_KEY=XXXXXXXXXX          # Key ID
   export ASC_API_ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```
   For agents: put these in a **gitignored** `build/session/asc-env.sh` and
   `source` it, or set them in the shell that launches the agent.

### 1.2 Xcode account (export fallback)

Sign into Xcode with the Apple ID that has the team's distribution rights
(Settings → Accounts). This is the fallback that signs exports when the API
key lacks cloud-signing permission — it's how Molten build 13 was exported.

### 1.3 Python helper dependency

```bash
python3 -m pip install cryptography   # for scripts/asc-release.py (JWT signing)
```

### 1.4 Verify the key works (read-only)

```bash
python3 scripts/asc-release.py status \
  --bundle-id com.your.bundleid --version 1.0.0 --build 1
```
Expected: app id + build/version states. `403` → key role too weak (Part 5).

---

## Part 2 — Per-release flow (exact commands)

Variables used below: `SCHEME` (Xcode scheme), `BUILD` (new build number),
`VERSION` (marketing version), `BUNDLE_ID`. Molten example:
`SCHEME=Molten`, `VERSION=2.0.1`, `BUILD=13`,
`BUNDLE_ID=com.ondemandworld.molten`.

### 2.0 Decide: new version or new build?

- **Version not released yet** (still in review / ready for sale but never
  shipped): keep `MARKETING_VERSION`, **bump only the build number**.
- **Version already shipped**: bump `MARKETING_VERSION` *and* build number.
- Build numbers must **always increase** per platform, across all versions.

### 2.1 Bump the build number on ALL targets

App + extensions + test targets must match or ASC validation rejects the
bundle. Edit every `CURRENT_PROJECT_VERSION` in `project.pbxproj`:

```bash
python3 - "$BUILD" <<'EOF'
import re, sys
p = 'Molten.xcodeproj/project.pbxproj'   # ← your project file
s = open(p).read()
s = re.sub(r'CURRENT_PROJECT_VERSION = \d+;',
           f'CURRENT_PROJECT_VERSION = {sys.argv[1]};', s)
open(p, 'w').write(s)
EOF
```

### 2.2 Gate on tests

```bash
xcodebuild test -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' -enableCodeCoverage NO CODE_SIGNING_ALLOWED=NO
```
- `-enableCodeCoverage NO`: default coverage fails linking yyjson
  (`___llvm_profile_runtime`).
- `CODE_SIGNING_ALLOWED=NO`: the signed macOS host is sandboxed and can't
  write to repo paths; unsigned runs let file-writing tests pass.

### 2.3 Archive both platforms

**Separate `-derivedDataPath` per platform** — concurrent builds sharing one
DerivedData deadlock on `build.db`.

```bash
xcodebuild archive -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "build/session/$SCHEME-macOS-b$BUILD.xcarchive" \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates

xcodebuild archive -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "build/session/$SCHEME-iOS-b$BUILD.xcarchive" \
  -derivedDataPath build/DerivedData-iOS -allowProvisioningUpdates
```

### 2.4 Export with distribution signing

ExportOptions plist (one serves both platforms):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>YOUR_TEAM_ID</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
```

**With an API key that has cloud-signing access** — note the flag names and
that the key path **must be absolute**:
```bash
xcodebuild -exportArchive \
  -archivePath "build/session/$SCHEME-macOS-b$BUILD.xcarchive" \
  -exportPath "build/session/macOS-export-b$BUILD" \
  -exportOptionsPlist build/session/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$PWD/private_keys/AuthKey_$ASC_API_KEY.p8" \
  -authenticationKeyID "$ASC_API_KEY" \
  -authenticationKeyIssuerID "$ASC_API_ISSUER"
```
(`xcodebuild` does **not** accept `--apiKey/--apiIssuer` — those are
`altool` flags. This cost us two failed runs.)

**Fallback (no cloud-signing permission on the key):** omit the three
`-authenticationKey*` flags entirely. Export then uses the logged-in Xcode
account's cloud-managed certificates — same mechanism as Organizer →
Distribute App. This is what worked for Molten build 13.

Repeat for the iOS archive (`-exportPath build/session/iOS-export-b$BUILD`).
Outputs: `Molten.pkg` (macOS) and `Molten.ipa` (iOS).

### 2.5 Sanity checks before upload (fail fast)

```bash
pkgutil --expand-full "build/session/macOS-export-b$BUILD/Molten.pkg" build/session/pkg-verify
APP=build/session/pkg-verify/com.your.bundleid.pkg/Payload/Molten.app
codesign --verify --deep --strict "$APP"
[ "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" = "$BUILD" ]
# embedded extensions must carry their entitlements (e.g. app sandbox):
codesign -d --entitlements - "$APP/Contents/PlugIns/YourShare.appex" 2>/dev/null \
  | grep -q "com.apple.security.app-sandbox"
```
Also unzip the IPA and check `Payload/*.app/Info.plist` `CFBundleVersion`.

### 2.6 Upload both

`altool` finds `AuthKey_<KeyID>.p8` in `./private_keys/` (run from repo root),
`~/private_keys/`, or `~/.private_keys/`:

```bash
xcrun altool --upload-app -f "build/session/iOS-export-b$BUILD/Molten.ipa" \
  -t ios --apiKey "$ASC_API_KEY" --apiIssuer "$ASC_API_ISSUER" --output-format normal
xcrun altool --upload-app -f "build/session/macOS-export-b$BUILD/Molten.pkg" \
  -t macos --apiKey "$ASC_API_KEY" --apiIssuer "$ASC_API_ISSUER" --output-format normal
```
Expect `UPLOAD SUCCEEDED` + a Delivery UUID. ASC processing takes ~5–30 min
(Molten build 13 was VALID within ~3 minutes).

### 2.7 Create/attach the version — stop before submitting

```bash
python3 scripts/asc-release.py status  --bundle-id "$BUNDLE_ID" --version "$VERSION" --build "$BUILD"
# wait until processingState=VALID, then:
python3 scripts/asc-release.py prepare --bundle-id "$BUNDLE_ID" --version "$VERSION" --build "$BUILD" \
  --whats-new-file build/session/whats-new.txt
```
`prepare` does, per platform: create the version if missing → attach the
processed build → set What's New (en-US) → create a review submission with
the version as an item. It **stops at READY_FOR_REVIEW**.

**STOP HERE.** Report status to the human. Only if they explicitly say
"submit":
```bash
python3 scripts/asc-release.py submit --bundle-id "$BUNDLE_ID" --version "$VERSION" --build "$BUILD"
```

---

## Part 3 — What's New text

Current Molten 2.0.1 (build 13) text, as set on ASC:

> Bug fixes and stability: safer chat stop/delete handling, more reliable
> Knowledge indexing and sync, voice input keeps audio on-device when
> supported, and many smaller fixes. Plus is now easier to discover when
> you reach a free limit.

Writing rules that work for this audience: lead with user-visible fixes,
keep it 2–4 sentences, no internal jargon (no "G1", "epoch guards", file
names), mention new value honestly, don't promise unshipped features.
Store it in `build/session/whats-new.txt` (gitignored) and pass
`--whats-new-file`.

---

## Part 4 — Copy-paste agent instructions

Give this to any coding agent (Claude Code or otherwise) working in the repo:

```text
Help me prepare App Store release <VERSION> build <BUILD> for <APP NAME>
(bundle id <BUNDLE_ID>, scheme <SCHEME>). Follow docs/APP_STORE_RELEASE_RUNBOOK.md.

Do, in order:
1. Bump CURRENT_PROJECT_VERSION to <BUILD> on ALL targets (keep
   MARKETING_VERSION at <VERSION> unless I say otherwise).
2. Run the test suite; stop and report if anything fails.
3. Archive macOS and iOS (Release, separate derivedDataPath per platform).
4. Export both with distribution signing (ExportOptions plist; if the API
   key gets "Cloud signing permission error", retry without the
   -authenticationKey* flags to use the Xcode account).
5. Run the sanity checks (codesign, CFBundleVersion == <BUILD>, embedded
   extension entitlements).
6. Upload both with altool using ASC_API_KEY/ASC_API_ISSUER (key in
   ./private_keys/).
7. Poll `asc-release.py status` until builds are VALID, then run
   `asc-release.py prepare` with the What's New text I provide.
8. STOP. Report READY_FOR_REVIEW status and wait.

HARD RULES:
- NEVER run `asc-release.py submit` or click Submit unless I explicitly
  say "submit it" in this conversation.
- Never commit secrets (*.p8, private_keys/, asc-env.sh).
- Stay inside the project folder; outputs go to build/session/.
- If a step fails twice, stop and show me the exact error.
```

---

## Part 5 — Troubleshooting (all hit for real on build 13)

| Symptom | Cause | Fix |
|---|---|---|
| `xcodebuild: error: invalid option '--apiKey'` | altool flags used on xcodebuild | use `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` |
| `-authenticationKeyPath flag must be an absolute path` | relative path passed | `"$PWD/private_keys/AuthKey_<ID>.p8"` |
| `Cloud signing permission error` / `No signing certificate "Mac App Distribution" found` | API key lacks cloud-managed cert access | export **without** auth flags (Xcode account), or have an Admin grant the key certificate access |
| `403 Forbidden` from asc-release.py | key role too weak for version writes | Admin/App Manager key (ASC → Users and Access → Integrations) |
| Test link error `___llvm_profile_runtime` | code coverage on | `-enableCodeCoverage NO` |
| File-writing tests fail on signed host | macOS sandbox | `CODE_SIGNING_ALLOWED=NO` for tests |
| Concurrent archives hang | shared build.db | separate `-derivedDataPath` per platform |
| ASC rejects bundle | build numbers differ across targets | bump `CURRENT_PROJECT_VERSION` on **all** targets |
| `prepare` says build not ready | still processing | wait, re-run `status` (5–30 min) |
| Upload can't find key | wrong cwd / key location | run from repo root with `./private_keys/AuthKey_<ID>.p8` |

---

## Part 6 — Adapting to a different project (Jack)

1. Copy `scripts/asc-release.py` into your repo (it has **no** account
   values baked in — everything comes from flags/env).
2. Create your own API key (Part 1) — don't share Molten's; keys are
   per-team and revocable per person.
3. Swap: `--bundle-id`, scheme name, project file path in the bump snippet,
   ExportOptions `teamID`, extension/entitlement names in the sanity checks.
4. Single-platform app? Use `--platform ios` (or `macos`) everywhere and
   skip the other archive.
5. Keep the golden rule: prepare ≠ submit.

*Companion docs: `docs/BUILD_AUTOMATION.md` (pipeline design),
`docs/OWNER_TASKS.md` (Molten-specific ASC history).*