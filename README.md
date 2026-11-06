# Savedd iOS

Lightweight iOS browser MVP using WKWebView with **Savedd** as the default search engine.

Search URL template: `https://savedd.com/?q={searchTerms}`

## Why WKWebView

Apple requires all iOS browsers to use WKWebView (WebKit). A full Firefox/Gecko fork is not possible on iOS for App Store distribution. This shell is the fastest path to an MVP that can be submitted.

## Project Structure

```
Savedd/
  SaveddApp.swift          // App entry
  ContentView.swift        // Main browser UI
  WebView.swift            // WKWebView wrapper
  SearchEngine.swift       // Savedd search helper
```

## App Icon

The 1024×1024 app icon (gold Christian cross inside a magnifying glass on dark burgundy #2C0812) is stored as base64 so it can live in the repo.

To decode it:

```bash
bash Assets/decode_icon.sh
```

This produces `Assets/AppIcon-1024.png`. Drop that file into Xcode → Assets.xcassets → AppIcon → App Store slot. Xcode generates the remaining sizes.

## Building

1. Create a new Xcode project (App, SwiftUI, Swift).
2. Add the files from the `Savedd/` folder.
3. Set the bundle identifier to `com.savedd.browser` (or similar).
4. Add the app icon as described above.
5. Build and run on device or simulator.

## App Store Notes

- Minimum functionality guideline (4.2) is satisfied by a real browser with navigation and search.
- To be set as the system default browser, request the `com.apple.developer.web-browser` entitlement.
- Existing browsers (Firefox, Brave, DuckDuckGo) prove WKWebView-based apps are approved.

## Next Steps

- Wire real back/forward buttons via the WebView coordinator
- Add tab support
- Custom new-tab page pointing at savedd.com
- Privacy policy link
