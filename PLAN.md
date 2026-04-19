# PLAN

## Enable CloudKit household sharing (manual dashboard work)

The code side of cross-device household sharing is ready. The onboarding
flow and the Households screen both show an Invite step that's gated on
`Features.cloudKitSharing`. The flag is currently `false` because flipping
it without the server-side setup will trap the app at launch (the same
crash TestFlight build 20 shipped). To turn this on:

1. **Apple Developer portal** — developer.apple.com/account/resources/identifiers
   - Select App ID `net.shadowpuppet.ADultingHD`
   - Enable iCloud capability → Edit → "Include CloudKit support"
   - Ensure container `iCloud.net.shadowpuppet.ADultingHD` is assigned
   - Save
2. **CloudKit Console** — icloud.developer.apple.com
   - Open the container
   - Confirm Development schema has `HouseholdTask`, `TaskCompletion`,
     `MemberProfile`, `HouseholdRoot` record types (auto-created by
     pushing from a Development build)
   - Click **Deploy Schema to Production** (TestFlight uses Production)
3. **Archive + upload** a new build — automatic signing refreshes the
   provisioning profile with the CloudKit entitlement
4. **Flip `Features.cloudKitSharing` to `true`** in
   `ADultingHD/App/Features.swift`, commit, archive, upload
5. **Verify** on a signed device signed into iCloud: Settings → Households
   → Invite → share URL generates without crashing

## Create test Apple IDs and configure simulators for sharing test

Goal: get two simulators signed into different iCloud accounts so
`scripts/test-sharing.sh` can run end-to-end.

### What can be automated (CDP + Gmail MCP)

- Open appleid.apple.com via CDP browser
- Fill the account creation form (name, email, password, birthday)
- Poll Gmail via Gmail MCP for Apple's verification email and extract the code
- Submit the code to complete email verification
- Accept iCloud terms at icloud.com to activate the CloudKit user record

Suggested Gmail aliases (no new inbox needed):
- Account 1 (owner):    atomantic+adulting-owner@gmail.com
- Account 2 (member):   atomantic+adulting-member@gmail.com

### What requires manual steps

**Phone/SMS verification** — Apple requires a phone number to complete
account creation. CDP cannot receive SMS. Options:
- Use a Google Voice number for Account 2 (Account 1 can reuse your real number)
- Or complete this step manually in the browser after CDP fills the form

**Simulator iCloud sign-in** — CDP controls Chromium; iOS Simulator Settings
is a native UIKit UI. There is no CDP path into it. After accounts are created,
sign in manually:
- Simulator A (iPhone 15 Pro): Settings → [sign in] → use Account 1
- Simulator B (iPhone 17 Pro): Settings → [sign in] → use Account 2

### Session instructions

In the new session, ask Claude to:
1. Use Playwright MCP to open https://appleid.apple.com/account#!&page=create
2. Fill the form for Account 1 (atomantic+adulting-owner@gmail.com)
3. Use Gmail MCP (`search_threads` for "Your Apple ID verification code") to get the email code
4. Complete email verification; pause and prompt for SMS code manually
5. Repeat for Account 2
6. Open https://www.icloud.com on each (via browser) and accept terms
7. Print final checklist: sign into each simulator manually, then run ./scripts/test-sharing.sh

## Smart Scheduling & Task Batching

The schedule view shows tasks by due date but doesn't help users plan their time. Add:
- Estimated time totals per day ("45 min of tasks due today")
- Suggested task batching by room/category ("Kitchen block: 3 tasks, ~25 min")
- Drag-to-reschedule for flexible tasks
- A "power hour" mode that queues up tasks and walks you through them with a timer

## Task assignee picker

`HouseholdTask.defaultAssigneeId` is in the data model; the onboarding flow
doesn't surface a picker because solo households can only have one assignee
(the device user). Once cross-device sharing is live, add:
- Assignee dropdown on `TaskDetailView` and `AddTaskView` (only shown when
  `householdProfiles.count > 1`)
- Filter chip on `TaskListView` for "Mine" / "Unassigned" / "All"
- Completion attribution: pre-fill `TaskCompletion.profileId` from the
  task's `defaultAssigneeId` when the assignee is the current device user
