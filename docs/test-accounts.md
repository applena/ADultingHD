# Test Apple IDs for CloudKit Sharing

Two real Apple IDs with iCloud enabled are required to run the two-simulator
sharing test (`scripts/test-sharing.sh`). App Store sandbox accounts do **not**
work for CloudKit sharing.

## Accounts to use

Use any two existing Apple IDs — no new accounts needed:

| Role | Account | Simulator |
|---|---|---|
| Account 1 (household owner) | Your Apple ID | Simulator A (iPhone 15 Pro) |
| Account 2 (household member) | A family member's Apple ID | Simulator B (iPhone 17 Pro) |

> The accounts just need to be different Apple IDs, both with iCloud enabled.

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
