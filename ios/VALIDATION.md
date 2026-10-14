# Validation status

Local checks completed on 2026-10-14:

- Five reservation HTML extraction tests passed using jsdom. Coverage includes seven-day extraction, vacant rooms, full descriptions, encoded all-day markers, unknown times, and malformed/empty table rejection.
- All 16 Swift files parsed without syntax errors with the Swift tree-sitter grammar. This is a syntax check, not a Swift compiler/type check.
- The Xcode project parsed as an OpenStep property list. All referenced files and shared-scheme targets resolve.
- Project regeneration produced identical bytes.
- Resource JSON, privacy manifest XML/property list, workflow YAML, JavaScript syntax, shell syntax, and Git whitespace checks passed.

The first macOS GitHub Actions run passed the HTML extraction tests and Swift Foundation unit tests, and compiled the simulator app. Demo navigation worked, but the UI test failed when demo exit attempted Keychain cleanup in the unsigned simulator app. Demo exit has been changed to avoid accessing the credential store or persistent cache. Simulator procedures were removed from CI at the user's request; that UI test has not been rerun.

The first device-only run passed all five HTML extraction tests and all eleven Swift core tests, compiled the device app, validated its IPA package, and uploaded the unsigned IPA successfully:

https://github.com/NothingwillbeNothing/NITechVacancyViewer/actions/runs/38515673701

The demo-exit correction also compiled and passed the device-only workflow:

https://github.com/NothingwillbeNothing/NITechVacancyViewer/actions/runs/38515995932

The user installed version 1.0 and confirmed the app opens and authenticates, but reported a connection failure while fetching reservations on MAINS-X. They supplied the current portal URL, which changed in August. Version 1.1 switches to that URL and interactive university/Microsoft browser authentication, adds URL/redirect and diagnostic tests, and retains the device-only CI workflow.

Version 1.1 (build 3) passed the device-only workflow with five HTML extraction tests and eighteen Swift core tests. Xcode compiled the device app, validated the IPA, and uploaded the package:

https://github.com/NothingwillbeNothing/NITechVacancyViewer/actions/runs/38518072599

The downloaded IPA was independently checked for version 1.1/build 3, an arm64 iPhoneOS executable, iOS 16 minimum, and unsigned packaging.

On 2026-10-14, the user confirmed that version 1.1 (build 3) works as expected after sideloading on their iPhone. Their screenshots show successful live reservation retrieval, building vacancy counts, and today's room reservations through the updated portal.

This is user-confirmed on-device validation. CI does not exercise protected university pages or run UI tests. No live credentials were supplied to the development environment.
