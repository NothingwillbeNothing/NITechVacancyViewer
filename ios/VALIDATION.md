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

Pending the final device-only run after the demo-exit correction:

- iPhone/iPad app compiler/type checking and unsigned IPA packaging.
- Runtime/UI testing after sideloading on a physical device (not run in CI).

Live NITech authentication and Campus Square parsing need MAINS-X or the university VPN and an account. No live credentials were available during this conversion.
