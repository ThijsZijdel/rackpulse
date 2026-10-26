# Releasing Rackpulse

How the owner signs, notarizes, and publishes a release. Contributors do not need this document: `make dev`, `make build`, and `make test` work with no setup.

## The workflow

1. Add a `## <version>` section to `CHANGELOG.md`. `make notarize` copies it next to the disk image, and the update window shows it as the release notes. The build stops if the section is missing.
2. Build and publish:

```bash
echo 0.2.2 > VERSION    # set the new version
make notarize           # build, sign, notarize, staple, write dist/appcast.xml
make publish            # upload the disk images and the feed to R2
```

3. Commit, tag, push, and create the GitHub release with the same notes:

```bash
git commit -am "Release 0.2.2" && git tag -a v0.2.2 -m v0.2.2 && git push origin HEAD v0.2.2
gh release create v0.2.2 dist/Rackpulse-0.2.2/Rackpulse-0.2.2.dmg --title "Rackpulse 0.2.2" --notes-file dist/Rackpulse-0.2.2/Rackpulse-0.2.2.md
```

## Setup, one time

| Item | Where it is | How to set it |
|---|---|---|
| Developer ID Application certificate | Login keychain | Xcode, Settings, Accounts, Manage Certificates |
| Signing identity | `.env`, `SIGN_ID` (git-ignored) | Copy `.env.example` to `.env`. No quotes around values |
| Notary credentials | Login keychain, profile named in `.env` as `NOTARY_PROFILE` | `xcrun notarytool store-credentials <profile>` with the Apple ID, the team ID, and an app-specific password |
| Sparkle update key | Login keychain, account `rackpulse`, with a copy in 1Password | See "Update key" |
| R2 upload credentials | `.env`: `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_TOKEN`, `R2_SECRET` | Cloudflare dashboard, R2, Manage API tokens, with Object Read & Write on the bucket. Copy the token value and the Secret Access Key |
| Tools | Homebrew | `create-dmg`, `rsvg-convert` |

The upload signs requests with the R2 access key pair. The Access Key ID is the token's ID, so `make publish` asks Cloudflare for it with `R2_TOKEN`. To skip that call, set `R2_ACCESS_KEY_ID` as well.

## Update key

Sparkle signs every update with a private key. Installed copies accept only updates signed with the key whose public half is `SUPublicEDKey` in `macos/Info.plist`. Without the private key, installed apps can never update again, so keep the copy in 1Password.

To create it (done once):

```bash
macos/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account rackpulse
```

To restore it on a new Mac from the 1Password copy:

```bash
op read "op://<vault>/<item>/<field>" > /tmp/rackpulse-key
macos/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account rackpulse -f /tmp/rackpulse-key
rm /tmp/rackpulse-key
```

Exported key files are git-ignored by the pattern `*sparkle-key*`. Delete them after you store them.

## What `make notarize` does

1. Stops if `SIGN_ID` is not set.
2. Builds the app with the version from `VERSION`, signed with the Developer ID and the hardened runtime, and the release entitlements (App Sandbox, outgoing network, Sparkle installer).
3. Sends the app to the Apple notary service, waits, and staples the ticket.
4. Builds the disk image, signs it, notarizes it, staples it, and checks it with Gatekeeper.
5. Moves it to `dist/Rackpulse-<version>/Rackpulse-<version>.dmg`.
6. Writes `dist/appcast.xml` from the disk images of all versions, signed with the update key. Sparkle makes delta files from older versions into each version's folder.

The two notary steps take most of the time, usually 2 to 10 minutes each. If a step fails, fix the cause and run `make notarize` again. The version stays the same.

## What goes to R2

Bucket `R2_BUCKET`, prefix `tools/rackpulse`, served at `https://tools-cdn.en3sis.com/tools/rackpulse`.

| Path | Source | Cache |
|---|---|---|
| `appcast.xml` | `dist/appcast.xml` | 5 minutes |
| `download/Rackpulse-<version>.dmg` and `*.delta` | `dist/Rackpulse-<version>/` | 1 year, never changes |
| `download/Rackpulse.dmg` | The newest disk image | 5 minutes |

The app reads `appcast.xml` (`SUFeedURL` in `macos/Info.plist`) one time each day and when the user selects Check for Updates.

Keep the `dist/Rackpulse-<version>/` folders. The feed is built from all of them. `dist/` is git-ignored, and `make clean` does not remove them.

## Agent releases

The Linux agent has its own version in `agent/VERSION` and ships separately from the app.

```bash
echo 0.2.2 > agent/VERSION
make test-agent       # Go tests
make agent            # build both binaries, SHA256SUMS and install.sh into dist/agent/<version>
make publish-agent    # upload to R2 under tools/rackpulse/agent
```

| Path | Cache |
|---|---|
| `agent/install.sh`, `agent/rackpulse-agent-linux-amd64`, `agent/rackpulse-agent-linux-arm64`, `agent/SHA256SUMS` | 5 minutes |
| `agent/<version>/` with the same files | 1 year, never changes |

When an agent release changes the protocol or adds a feature the app relies on, set `AgentStore.latestVersion` in the app to the new version. The app then offers the update command on the agent's setup page.

## Checks after a release

```bash
curl -s https://tools-cdn.en3sis.com/tools/rackpulse/appcast.xml | grep -E "<title>|sparkle:version"
curl -sI https://tools-cdn.en3sis.com/tools/rackpulse/download/Rackpulse.dmg | head -5
```

Then open an installed older version and select Check for Updates.
