# Test Apple IDs for CloudKit Sharing

Two dedicated Apple IDs are required to run the two-simulator sharing test
(`scripts/test-sharing.sh`). These must be real Apple IDs with iCloud enabled —
App Store sandbox accounts do **not** work for CloudKit sharing.

## Creating the accounts (one-time)

1. Open a private/incognito browser window.
2. Go to **https://appleid.apple.com** → **Create Your Apple ID**.
3. Use a real email address you control (e.g. Gmail aliases:
   `yourname+adulting-test1@gmail.com` and `yourname+adulting-test2@gmail.com`).
4. Complete verification (email + phone).
5. Sign in at https://icloud.com and accept the iCloud terms — this activates
   the iCloud account and creates the CloudKit user record.
6. Repeat for the second account.

> Apple may enforce a rate limit on new account creation from the same IP.
> Create the accounts a few minutes apart or from different networks if blocked.

## Recommended naming

| Role | Suggested email | Note |
|---|---|---|
| Account 1 (household owner) | `yourname+adulting-owner@gmail.com` | Signs into Simulator A |
| Account 2 (household member) | `yourname+adulting-member@gmail.com` | Signs into Simulator B |

Store these in your password manager. Do not commit credentials to the repo.

## Signing into the simulators (one-time per account)

1. In Xcode → **Window → Devices and Simulators**, confirm both simulators are booted.
2. **Simulator A** (e.g. iPhone 15 Pro):
   - Open **Settings** → scroll to the top → tap **Sign in to your iPhone**.
   - Enter Account 1 credentials.
   - Under **iCloud**, enable **iCloud Drive** — this activates CloudKit for the
     Development container.
3. **Simulator B** (e.g. iPhone 17 Pro):
   - Same steps with Account 2.

Sign-in persists across boots. You only need to repeat this if you erase the
simulator or switch accounts.

## Verifying sign-in

On each simulator, open **Settings → [account name] → iCloud**. You should see
iCloud Drive as "On" and no sign-in error banner. CloudKit sharing will not work
if iCloud Drive is off.

## Simulator assignments

The test script defaults to:

```
Simulator A (owner):    iPhone 15 Pro
Simulator B (recipient): iPhone 17 Pro
```

Override with env vars if your setup differs:

```bash
SIM_A_NAME="iPhone 16 Pro" SIM_B_NAME="iPhone 16" ./scripts/test-sharing.sh
```

## Per-run checklist

Before each test run (after initial setup, these should already be true):

- [ ] Both simulators are booted and visible in Simulator.app
- [ ] Both are signed into iCloud (Settings → account name shows iCloud is on)
- [ ] ADultingHD has CloudKit sharing enabled (`Features.cloudKitSharing = true`)
- [ ] Development CloudKit schema is current (run integration tests first)

## Troubleshooting

**"Get the latest app from the App Store" on Simulator B**

The Development CloudKit schema is missing the `cloudkit.share` system type, or
the Production schema hasn't been deployed. Run the integration tests:

```bash
CLOUDKIT_INTEGRATION_TESTS=1 xcodebuild test \
    -scheme ADultingHD_iOS \
    -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
    -only-testing ADultingHDTests_iOS/CloudKitIntegrationTests
```

The `testShareURL_metadataFetchable` test is the one that would fail here.

**Safari opens instead of the sharing sheet**

The OS hasn't yet associated the installed app with the CloudKit container.
Wait 10–15 seconds and retry `xcrun simctl openurl`. Alternatively, paste the
URL directly into Safari on Simulator B — Safari will hand off to the system
CloudKit handler after loading the page.

**CKContainer trap / crash on launch**

The build is unsigned. Use `xcodebuild … DEVELOPMENT_TEAM=TYQ32QCF6K` (not
`CODE_SIGNING_ALLOWED=NO`) when building for the sharing test. The script
handles this automatically.
