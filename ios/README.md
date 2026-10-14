# NITechSearch for iOS

A native SwiftUI port of [Punyo/NITechVacancyViewer](https://github.com/Punyo/NITechVacancyViewer), based on upstream commit `2c77f383ac800c5e115f1809daf69c3240aba44a`.

Requires iOS 16 or later. Works on iPhone and iPad. No third-party runtime dependencies.

## Features

- The original seven buildings and their lecture rooms, with the original building photos and icon.
- Current vacancy, current reservations, next reservation time, and room reservation details.
- A searchable room list with an optional vacant-only filter.
- NITech foundation ID sign-in through the same OpenAM endpoint as Android, including time for the university MFA prompt.
- An authenticated `WKWebView` that follows the Campus Square main menu, facility flow, and week view.
- A protected local reservation cache, pull-to-refresh, and vacancy recalculation every 60 seconds while active.
- Optional credential saving in the iOS Keychain, system/light/dark themes, and logout cleanup.
- A clearly marked demo using the original bundled sample data. Tap **デモを試す** or use `demoMode` for both ID and password.

Live access needs MAINS-X or the university VPN. No university credentials are included. Live authentication and reservation retrieval must be verified on that network; CI exercises the offline demo and parser logic.

## Open in Xcode

Open `ios/NITechVacancyViewer.xcodeproj`, select the **NITechVacancyViewer** scheme, and run on an iPhone simulator. The project is checked in and can be regenerated with:

```sh
python3 ios/scripts/generate_project.py
```

For an actual iPhone, select your Apple development team in **Signing & Capabilities**, use a bundle identifier belonging to your account if necessary, and build with Xcode. TestFlight/App Store distribution also requires the appropriate Apple account, signing certificate, and provisioning profile.

## GitHub Actions build

The **iOS Build** workflow runs on a macOS runner on pushes to `feat/ios-*`, `dev`, `main`, or `master`, on pull requests touching iOS files, and on manual dispatch. Forks may need Actions enabled once in the repository's **Actions** tab.

It tests the HTML extractor and Foundation models, builds and tests the iOS app on an available iPhone simulator, and creates two packages in the **NITechSearch-iOS** artifact:

| File | Use |
| --- | --- |
| `NITechSearch-iOS-Simulator.zip` | Unzip and install the `.app` in a Mac's iOS simulator. |
| `NITechSearch-unsigned.ipa` | Device build for signing with your own Apple certificate/profile or compatible signing tool. It cannot be installed directly while unsigned. |

The **iOS-TestResults** artifact contains XCTest results and an offline demo screenshot. Builds do not publish to the App Store or TestFlight.

To build locally on macOS:

```sh
bash ios/scripts/build.sh
cd ios
swift test
```

To install the simulator build on a booted simulator:

```sh
xcrun simctl install booted NITechVacancyViewer.app
xcrun simctl launch booted jp.nothingwillbenothing.nitechsearch
```

## Port details

Time and date calculations use `Asia/Tokyo` even if the phone's time zone differs. Reservations include their start minute and exclude their end minute. Unknown or malformed reservation times stay **不明**, and missing rooms are never counted as vacant. The full reservation description is retained.

The reservation extractor uses the upstream HTML selectors (`kyuko-shisetsu-nofixed`, `kyuko-shi-shisetsunm`, and `kyuko-shi-jugyo`). If the page supplies a `data-date`, that date is used. Otherwise each of the seven tables is assigned today plus its offset, matching the Android implementation's assumption. The live university page's week ordering should be checked before relying on the app.

Reservation fetch timestamps show when data was actually fetched. The 60-second update recalculates status from the cached schedule; it does not claim a new network fetch. Pull-to-refresh fetches a fresh reservation table. Automatic iOS background polling is not used.

Credentials go only to the university authentication host over HTTPS. Authentication redirects are rejected to avoid forwarding credential headers. The SSO token remains in memory, and Campus Square uses a nonpersistent cookie store. The optional password is stored in a device-only, unlocked-only Keychain item; the reservation cache is file-protected and excluded from backups. No analytics or advertising SDKs are included.

The linked original terms/privacy pages are retained for attribution; an independent distribution should provide policies appropriate to its own operation. The upstream repository has no license file at the referenced commit; this port does not assign a license to upstream code or assets.
