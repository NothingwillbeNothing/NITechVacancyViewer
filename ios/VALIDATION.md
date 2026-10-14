# Validation status

Local checks completed on 2026-10-14:

- Five reservation HTML extraction tests passed using jsdom. Coverage includes seven-day extraction, vacant rooms, full descriptions, encoded all-day markers, unknown times, and malformed/empty table rejection.
- All 16 Swift files parsed without syntax errors with the Swift tree-sitter grammar. This is a syntax check, not a Swift compiler/type check.
- The Xcode project parsed as an OpenStep property list. All referenced files and shared-scheme targets resolve.
- Project regeneration produced identical bytes.
- Resource JSON, privacy manifest XML/property list, workflow YAML, JavaScript syntax, shell syntax, and Git whitespace checks passed.

Pending the macOS GitHub Actions run:

- Swift compiler/type checking and Foundation XCTest execution.
- iOS simulator build, XCTest/UI test execution, and screenshot inspection.
- iPhone device compilation and unsigned IPA packaging.

Live NITech authentication and Campus Square parsing need MAINS-X or the university VPN and an account. No live credentials were available during this conversion.
