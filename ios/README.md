# NITechSearch for iOS

A native SwiftUI port of [Punyo/NITechVacancyViewer](https://github.com/Punyo/NITechVacancyViewer), based on upstream commit `2c77f383ac800c5e115f1809daf69c3240aba44a`.

Requires iOS 16 or later. Works on iPhone and iPad. No third-party runtime dependencies. Version 1.1 uses the current portal URL supplied by the user:

https://aprkyomu-nitechict.msappproxy.net/campusweb/campusportal.do?page=main&tabId=kh

## Features

- The original seven buildings and their lecture rooms, with the original building photos and icon.
- Current vacancy, current reservations, next reservation time, and room reservation details.
- A searchable room list with an optional vacant-only filter.
- Interactive sign-in on the university's own portal, including its university/Microsoft authentication redirects and MFA prompts.
- An authenticated `WKWebView` that follows the Campus Square portal, facility flow, and week view. Old absolute campus links are translated to the new proxy host.
- A protected local reservation cache, pull-to-refresh, and vacancy recalculation every 60 seconds while active.
- Optional browser-session persistence, system/light/dark themes, and logout cleanup.
- A clearly marked demo using the original bundled sample data. Tap **デモを試す**.

No university credentials are included. The app does not collect or save a password in its native form. Live access follows the university's current portal and access policies. Live authentication and reservation retrieval must be verified on the user's device; CI tests parsing, date/time behavior, allowed authentication hosts, URL rewriting, and network-error handling.

## Open in Xcode

Open `ios/NITechVacancyViewer.xcodeproj` and select the **NITechVacancyViewer** scheme. The project is checked in and can be regenerated with:

```sh
python3 ios/scripts/generate_project.py
```

For an actual iPhone, select your Apple development team in **Signing & Capabilities**, use a bundle identifier belonging to your account if necessary, and build with Xcode. TestFlight/App Store distribution also requires the appropriate Apple account, signing certificate, and provisioning profile.

## GitHub Actions build

The **iOS Build** workflow runs on a macOS runner on pushes to `feat/ios-*`, `dev`, `main`, or `master`, on pull requests touching iOS files, and on manual dispatch. Forks may need Actions enabled once in the repository's **Actions** tab.

It runs the HTML extractor tests and Foundation unit tests on macOS, then compiles only the iPhone/iPad device app. It does not prepare, build, or run a simulator.

The **NITechSearch-iOS** artifact contains `NITechSearch-unsigned.ipa`. This is a device build for your sideloading tool to sign using an Apple account or certificate and provisioning profile. It cannot be installed directly while unsigned.

The **iOS-TestResults** artifact contains parser and Swift core test logs. CI does not run UI tests or verify live university access. Builds do not publish to the App Store or TestFlight.

To build locally on macOS:

```sh
bash ios/scripts/build.sh
cd ios
swift test
```

After sideloading, open NITechSearch on your device and tap **デモを試す** to check building navigation, room details, search, themes, and logout. Then tap **大学アカウントでログイン** and complete the university's authentication screen. If the portal menu changed, open **施設利用状況参照** in that screen; the app returns to its native interface after reading the reservation tables.

## Port details

Time and date calculations use `Asia/Tokyo` even if the phone's time zone differs. Reservations include their start minute and exclude their end minute. Unknown or malformed reservation times stay **不明**, and missing rooms are never counted as vacant. The full reservation description is retained.

The reservation extractor uses the upstream HTML selectors (`kyuko-shisetsu-nofixed`, `kyuko-shi-shisetsunm`, and `kyuko-shi-jugyo`). If the page supplies a `data-date`, that date is used. Otherwise each of the seven tables is assigned today plus its offset, matching the Android implementation's assumption. The live university page's week ordering should be checked before relying on the app.

Reservation fetch timestamps show when data was actually fetched. The 60-second update recalculates status from the cached schedule; it does not claim a new network fetch. Pull-to-refresh fetches a fresh reservation table. Automatic iOS background polling is not used.

Login occurs in the university's actual browser pages over HTTPS. The native OpenAM username/password API used by version 1.0 has been removed; its token is not forwarded to the new application-proxy host. The app permits the configured campus host and known university/Microsoft authentication hosts, displays the current login hostname, and waits for the real authentication redirects. When **この端末でログイン状態を保持** is enabled, the app uses its persistent WebKit cookie store; otherwise it uses an in-memory store for the current session. Logout clears the app's browser data and reservation cache. Legacy version-1.0 Keychain credentials are removed where the device's signing configuration permits. The reservation cache is file-protected and excluded from backups. No analytics or advertising SDKs are included.

The loading WebView is attached to the app's window even when invisible. Cancelled or superseded navigation is ignored, while actual failures report the request stage, framework error code, and hostname without exposing URL queries or authentication data. TLS certificate validation remains enabled.

The linked original terms/privacy pages are retained for attribution; an independent distribution should provide policies appropriate to its own operation. The upstream repository has no license file at the referenced commit; this port does not assign a license to upstream code or assets.
