Release a new build to TestFlight.

## Steps

1. Run `./deploy.sh` from the project root
2. This will:
   - Source `.env` for API credentials
   - Auto-increment the build number in `project.yml`
   - Regenerate the Xcode project via `xcodegen generate`
   - Run tests on iOS simulator
   - Archive the app
   - Export and upload to TestFlight
   - Commit the build number bump
3. Push the commit after successful upload

## Options
- `./deploy.sh --skip-tests` — skip test run
- `./deploy.sh --macos` — build macOS only
- `./deploy.sh --all` — build both iOS and macOS

## Prerequisites
- `.env` file with `APPSTORE_API_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_API_PRIVATE_KEY_PATH`, and `TEAM_ID`
- API key (.p8 file) at the path specified in `.env`
