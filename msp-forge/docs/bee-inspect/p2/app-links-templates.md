# Bee-Inspect app link files: templates (not published)

Bee-Inspect P2, 25/09/2026. hsf/BEE-INSPECT-BUILD-PROMPT.md A3; hsf/BUILD-CONTRACT.md 16.4.

The two files below make `https://<site>/claim/{code}` open the Bee-Inspect app on a phone that has it installed (iOS Universal Links and Android App Links). They are **not** in `vercel/.well-known/` on purpose: a file with placeholder ids would be served to Apple and Google as if it were real, and both cache what they fetch. They go live in the same release as the first store build, once the Director has registered the Apple and Google developer accounts and the two open inputs below are known. A node test (`test/api/bee-inspect-pages.test.js`) fails if `vercel/.well-known/` appears before then.

## Open inputs

| Input | Where it comes from | Who |
| --- | --- | --- |
| `{{apple_team_id}}` | Apple Developer account, Membership details, Team ID (10 characters) | Director, once the account exists |
| `{{ios_bundle_id}}` | The bundle identifier chosen for the iOS app in P4 (for example `za.co.carenetconsultants.beeinspect`, to be confirmed) | Builder with the Director, P4 |
| `{{android_package}}` | The Android application id chosen in P4 (normally the same reverse domain name as the bundle id) | Builder with the Director, P4 |
| `{{android_sha256}}` | Google Play Console, App integrity, App signing key certificate, SHA-256 fingerprint (and the upload key fingerprint for internal testing builds) | Director, once the app is in Play Console |

Store publisher: `{{store_publisher}}` (default Care Net Consultants Development House (Pty) Ltd).

## 1. `vercel/.well-known/apple-app-site-association`

No file extension. Served as `application/json`, over HTTPS, with no redirect.

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["{{apple_team_id}}.{{ios_bundle_id}}"],
        "components": [
          { "/": "/claim/*", "comment": "Bee-Inspect claim codes (desktop QR sign in)" }
        ]
      }
    ]
  },
  "webcredentials": {
    "apps": ["{{apple_team_id}}.{{ios_bundle_id}}"]
  }
}
```

## 2. `vercel/.well-known/assetlinks.json`

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "{{android_package}}",
      "sha256_cert_fingerprints": ["{{android_sha256}}"]
    }
  }
]
```

The fingerprint is written as upper case hexadecimal pairs separated by colons, exactly as Play Console shows it. Add the upload key fingerprint as a second entry while internal test builds are signed with it.

## 3. What else changes in that release

1. `vercel/vercel.json`: a header rule so the Apple file is served as JSON, since it has no extension:
   ```json
   { "source": "/.well-known/apple-app-site-association", "headers": [ { "key": "Content-Type", "value": "application/json" } ] }
   ```
   `server/serve.js` serves dot directories as hidden today; add `.well-known` as the one allowed dot directory (with a test) when the files arrive.
2. `vercel/hsf/ads.js` `app`: set `ios_url`, `android_url`, `ios_app_id` and `android_package`, and `stub: false`. `/get-app` then routes phones to their store by itself (js/cnc-bee.js `route`, already tested with store addresses).
3. Store badges: the official App Store and Google Play badge artwork, unaltered, on `/bee-inspect`, `/get-app` and in the File menu area (asset `ga-store-badges` in get-app.html's asset specification).
4. Smart app banner on mobile web: `<meta name="apple-itunes-app" content="app-id={{ios_app_id}}, app-argument=...">` on `/bee-inspect` and `/get-app` only, never inside the builder canvas. Parked until the app id exists.
5. `/claim/{code}`: claim-code-redeem (P3) replaces the shape check in claim.html; the page keeps never writing the code into the page, and keeps noindex and no referrer.
6. Verify with Apple's `https://app-site-association.cdn-apple.com/a/v1/<host>` and Google's Digital Asset Links API (`https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://<host>&relation=delegate_permission/common.handle_all_urls`) after the deploy.
