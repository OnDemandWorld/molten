#!/usr/bin/env python3
"""App Store Connect release helper — reusable, self-contained.

Talks only to api.appstoreconnect.apple.com using an ASC API key (ES256 JWT).
Works for any app: everything account/project-specific comes from flags or
environment variables. Requires: python3 + `cryptography` (pip install cryptography).

Commands:
  status    Read-only: app, build processing state, existing version state.
  prepare   Create the version (if needed), attach the processed build, set
            What's New, create a review submission + items.
            *** STOPS BEFORE SUBMITTING — by design. ***
  submit    Submit the prepared review submission(s) to App Review.
            *** ONLY run this when a human explicitly asks to submit. ***

Usage (from the repo root, key in ./private_keys/):
  export ASC_API_KEY=<KeyID> ASC_API_ISSUER=<IssuerID>
  python3 scripts/asc-release.py status  --bundle-id com.example.app --version 1.2.3 --build 42
  python3 scripts/asc-release.py prepare --bundle-id com.example.app --version 1.2.3 --build 42 \
      --whats-new "Bug fixes and improvements."
  # submit ONLY on explicit human instruction:
  python3 scripts/asc-release.py submit  --bundle-id com.example.app --version 1.2.3 --build 42

Key path defaults to ./private_keys/AuthKey_<ASC_API_KEY>.p8; override with
ASC_KEY_PATH (absolute path). What's New can also come from --whats-new-file.
"""
import sys, os, json, time, argparse, urllib.request, urllib.error
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

BASE = "https://api.appstoreconnect.apple.com"
PLATFORMS = {"ios": "IOS", "macos": "MAC_OS"}

# Config (filled in main() from flags/env).
KEY_ID = os.environ.get("ASC_API_KEY", "")
ISSUER = os.environ.get("ASC_API_ISSUER", "")
KEY_PATH = os.environ.get("ASC_KEY_PATH", "")
BUNDLE_ID = ""
VERSION = ""
BUILD = ""
WHATS_NEW = ""


def make_token():
    path = KEY_PATH or os.path.join(os.getcwd(), "private_keys", f"AuthKey_{KEY_ID}.p8")
    with open(path, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    now = int(time.time())

    def b64(b):
        import base64
        return base64.urlsafe_b64encode(b).rstrip(b"=")

    header = b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    payload = b64(json.dumps({"iss": ISSUER, "iat": now, "exp": now + 1200,
                              "aud": "appstoreconnect-v1"}).encode())
    signing_input = header + b"." + payload
    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return (signing_input + b"." + b64(sig)).decode()


TOKEN = ""


def api(method, path, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        print(f"  HTTP {e.code} {method} {path}\n  {err}")
        raise


def get_app():
    r = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    apps = r.get("data", [])
    if not apps:
        sys.exit(f"No app found for bundle id {BUNDLE_ID}")
    return apps[0]["id"]


def find_builds(app_id):
    """Return {platform: [builds]} for build number BUILD. Platform comes from
    the included preReleaseVersion (the builds endpoint has no platform filter)."""
    r = api("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}"
                   f"&include=preReleaseVersion&limit=50&sort=-uploadedDate")
    plat_by_prv = {inc["id"]: inc["attributes"].get("platform")
                   for inc in r.get("included", []) if inc["type"] == "preReleaseVersions"}
    out = {"IOS": [], "MAC_OS": []}
    for b in r.get("data", []):
        prv = b.get("relationships", {}).get("preReleaseVersion", {}).get("data", {})
        plat = plat_by_prv.get(prv.get("id"))
        if plat in out:
            out[plat].append(b)
    return out


def find_version(app_id, platform):
    r = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]={platform}&limit=50")
    for v in r.get("data", []):
        if v["attributes"]["versionString"] == VERSION:
            return v
    return None


def cmd_status(app_id, plats):
    print(f"App id: {app_id}  (bundle {BUNDLE_ID})")
    builds_by_plat = find_builds(app_id)
    for p in plats:
        print(f"\n[{p}]")
        builds = builds_by_plat[PLATFORMS[p]]
        if not builds:
            print(f"  build {BUILD}: NOT FOUND (still uploading/processing?)")
        for b in builds:
            a = b["attributes"]
            print(f"  build {BUILD}: id={b['id']} state={a.get('processingState')} "
                  f"expired={a.get('expired')} uploaded={a.get('uploadedDate')}")
        v = find_version(app_id, PLATFORMS[p])
        if v:
            print(f"  version {VERSION}: id={v['id']} state={v['attributes'].get('appStoreState')}")
        else:
            print(f"  version {VERSION}: does not exist yet")


def ensure_version(app_id, platform):
    v = find_version(app_id, platform)
    if v:
        print(f"  version {VERSION} exists ({v['attributes'].get('appStoreState')})")
        return v["id"]
    r = api("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": platform, "versionString": VERSION},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    vid = r["data"]["id"]
    print(f"  created version {VERSION}: {vid}")
    return vid


def attach_build(vid, bid):
    api("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
        {"data": {"type": "builds", "id": bid}})
    print(f"  attached build {bid} to version {vid}")


def set_whats_new(vid):
    if not WHATS_NEW:
        print("  no --whats-new provided; skipping What's New")
        return
    r = api("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    locs = r.get("data", [])
    target = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if not target and locs:
        target = locs[0]
    if not target:
        print("  no localization found; skipping What's New")
        return
    api("PATCH", f"/v1/appStoreVersionLocalizations/{target['id']}",
        {"data": {"type": "appStoreVersionLocalizations", "id": target["id"],
                  "attributes": {"whatsNew": WHATS_NEW}}})
    print(f"  set What's New on {target['attributes'].get('locale')}")


def ensure_submission(app_id, platform, vid):
    r = api("GET", f"/v1/apps/{app_id}/reviewSubmissions?filter[platform]={platform}&limit=20")
    for s in r.get("data", []):
        if s["attributes"].get("state") in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"):
            print(f"  review submission already exists: {s['id']} ({s['attributes'].get('state')})")
            return s["id"]
    r = api("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions",
        "attributes": {"platform": platform},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    sid = r["data"]["id"]
    print(f"  created review submission: {sid}")
    api("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    print(f"  added version {vid} to submission")
    return sid


def cmd_prepare(app_id, plats):
    builds_by_plat = find_builds(app_id)
    for p in plats:
        platform = PLATFORMS[p]
        print(f"\n[{p}] preparing {VERSION}...")
        builds = builds_by_plat[platform]
        ready = [b for b in builds if b["attributes"].get("processingState") == "VALID"
                 and not b["attributes"].get("expired")]
        if not ready:
            states = [b["attributes"].get("processingState") for b in builds]
            print(f"  SKIP: build {BUILD} not ready (states={states}). Wait for processing.")
            continue
        bid = ready[0]["id"]
        vid = ensure_version(app_id, platform)
        attach_build(vid, bid)
        set_whats_new(vid)
        ensure_submission(app_id, platform, vid)
    print("\nPrepared — READY FOR REVIEW, NOT SUBMITTED.")
    print("A human must review in App Store Connect and explicitly request 'submit'.")


def cmd_submit(app_id, plats):
    for p in plats:
        platform = PLATFORMS[p]
        r = api("GET", f"/v1/apps/{app_id}/reviewSubmissions?filter[platform]={platform}&limit=20")
        subs = [s for s in r.get("data", [])
                if s["attributes"].get("state") == "READY_FOR_REVIEW"]
        if not subs:
            print(f"[{p}] no READY_FOR_REVIEW submission found; run 'prepare' first.")
            continue
        sid = subs[0]["id"]
        api("PATCH", f"/v1/reviewSubmissions/{sid}",
            {"data": {"type": "reviewSubmissions", "id": sid,
                      "attributes": {"submitted": True}}})
        print(f"[{p}] submitted {sid} to App Review.")


def main():
    global KEY_ID, ISSUER, KEY_PATH, BUNDLE_ID, VERSION, BUILD, WHATS_NEW, TOKEN
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["status", "prepare", "submit"])
    ap.add_argument("--platform", choices=["ios", "macos", "both"], default="both")
    ap.add_argument("--bundle-id", default=os.environ.get("ASC_BUNDLE_ID", ""), required=False)
    ap.add_argument("--version", required=True, help="marketing version, e.g. 1.2.3")
    ap.add_argument("--build", required=True, help="build number (CFBundleVersion), e.g. 42")
    ap.add_argument("--key-id", default=KEY_ID, help="ASC API Key ID (or env ASC_API_KEY)")
    ap.add_argument("--issuer", default=ISSUER, help="ASC API Issuer ID (or env ASC_API_ISSUER)")
    ap.add_argument("--key-path", default=KEY_PATH, help="absolute .p8 path (or env ASC_KEY_PATH)")
    ap.add_argument("--whats-new", default="", help="What's New text (en-US)")
    ap.add_argument("--whats-new-file", default="", help="read What's New from a file instead")
    args = ap.parse_args()

    KEY_ID, ISSUER, KEY_PATH = args.key_id, args.issuer, args.key_path
    BUNDLE_ID, VERSION, BUILD = args.bundle_id, args.version, args.build
    WHATS_NEW = args.whats_new
    if args.whats_new_file:
        with open(args.whats_new_file) as f:
            WHATS_NEW = f.read().strip()
    if not (KEY_ID and ISSUER and BUNDLE_ID):
        sys.exit("Need ASC_API_KEY + ASC_API_ISSUER (env or flags) and --bundle-id.")
    if args.command == "submit":
        print("NOTE: 'submit' sends the app to Apple review. "
              "Only proceed because a human explicitly invoked this command.")
    TOKEN = make_token()

    plats = ["ios", "macos"] if args.platform == "both" else [args.platform]
    try:
        app_id = get_app()
        {"status": cmd_status, "prepare": cmd_prepare, "submit": cmd_submit}[args.command](app_id, plats)
    except urllib.error.HTTPError as e:
        if e.code == 403:
            print("\n403 Forbidden: the API key's role lacks permission for this write.")
            print("Creating versions / submitting for review needs an App Manager or Admin key.")
            print("Fix: ASC > Users and Access > Integrations > App Store Connect API >")
            print("     edit this key's Access to Admin (or generate a new Admin key).")
        sys.exit(1)


if __name__ == "__main__":
    main()