# SwiftUI Edge-to-Edge Layout & Safe Area - Comprehensive Research Report

## Executive Summary

Making SwiftUI content truly fill the screen edge-to-edge (behind the Dynamic Island and home indicator) is one of the most consistently misunderstood areas of SwiftUI layout. The core problem is that `ignoresSafeArea()` is a propagation modifier: it only works when the view it is attached to physically touches the safe area boundary. Putting it on a `VStack` inside a `ZStack` that is itself inside a `WindowGroup` often does nothing useful because the layout system has already shrunk the available space before the modifier fires.

There are three reliable layers of fix, in order of increasing invasiveness: (1) correct `ignoresSafeArea()` placement on the right view in the right container, (2) `UIHostingController.safeAreaRegions` to strip the host-level safe area injection (iOS 16.4+), and (3) `UIViewController` flags (`edgesForExtendedLayout`, `extendedLayoutIncludesOpaqueBars`) to instruct UIKit never to apply insets in the first place. For `WKWebView` specifically, `scrollView.contentInsetAdjustmentBehavior = .never` is additionally required to stop the scroll view from re-adding insets on its own.

On iOS 26, Apple shipped a native SwiftUI `WebView` type (part of the WebKit framework) that accepts `.ignoresSafeArea()` directly and is the cleanest long-term solution for web-based content. For the current `WKWebView`/`UIViewRepresentable` approach, the `UIHostingController` route is the most reliable fix.

---

## Table of Contents

1. [Introduction & Context](#introduction--context)
2. [How the Safe Area Works in SwiftUI](#how-the-safe-area-works-in-swiftui)
3. [Why ignoresSafeArea Fails Silently](#why-ignoressafearea-fails-silently)
4. [Fix Layer 1 — Correct SwiftUI Modifier Placement](#fix-layer-1--correct-swiftui-modifier-placement)
5. [Fix Layer 2 — UIHostingController.safeAreaRegions](#fix-layer-2--uihostingcontrollersafearearegions)
6. [Fix Layer 3 — UIViewController edgesForExtendedLayout](#fix-layer-3--uiviewcontroller-edgesforextendedlayout)
7. [WKWebView-Specific: contentInsetAdjustmentBehavior](#wkwebview-specific-contentinsetadjustmentbehavior)
8. [iOS 26 Native SwiftUI WebView](#ios-26-native-swiftui-webview)
9. [Info.plist Settings](#infoplist-settings)
10. [Applying the Fix to BashMirror](#applying-the-fix-to-bashmirror)
11. [Decision Matrix](#decision-matrix)
12. [Common Mistakes Reference](#common-mistakes-reference)
13. [Appendices](#appendices)

---

## Introduction & Context

The "safe area" is a UIKit concept dating to the iPhone X notch (2017). It defines a rectangle inside the screen where content is never obscured by hardware features (notch, Dynamic Island, home indicator) or system chrome (status bar, navigation bar, tab bar). UIKit enforces this by adjusting `additionalSafeAreaInsets` on the root `UIViewController`, which flows down the responder chain.

SwiftUI runs on top of UIKit. When you present a `WindowGroup`, SwiftUI creates a `UIHostingController` and installs it as the root view controller. That `UIHostingController` respects the safe area by default, propagating insets into the SwiftUI layout engine as "safe area regions." Every SwiftUI view starts with a layout frame that already excludes the safe area. `ignoresSafeArea()` then allows a view to expand back into that excluded space — but only when the conditions for expansion are met.

---

## How the Safe Area Works in SwiftUI

### The propagation model

Safe area information flows top-down through the view tree as an environment value. Each view receives a "proposed safe area" from its parent. When a view has `ignoresSafeArea()` applied, it passes a reduced safe area to its children (shrinking or zeroing the relevant edges), so children see a larger layout frame.

The critical rule: **a view can only ignore safe area edges that it actually touches**. If a view is already inset away from an edge by its parent's layout, `ignoresSafeArea()` on that view has no effect on the edge it does not reach.

### SafeAreaRegions enum

```swift
// The regions parameter (default .all):
SafeAreaRegions.container  // device hardware + status/nav/tab bars
SafeAreaRegions.keyboard   // software keyboard overlay
SafeAreaRegions.all        // union of both
```

Specifying `.container` only affects hardware and system chrome insets, leaving keyboard avoidance intact.

### Edges enum

```swift
Edge.Set.top       // behind Dynamic Island / status bar
Edge.Set.bottom    // behind home indicator / tab bar
Edge.Set.leading   // left edge
Edge.Set.trailing  // right edge
Edge.Set.vertical  // top + bottom
Edge.Set.horizontal // leading + trailing
Edge.Set.all       // all four edges (default)
```

---

## Why ignoresSafeArea Fails Silently

### Problem 1: The view does not touch the safe area boundary

```swift
// BROKEN — VStack is sized to its content, does not reach top/bottom edges
VStack {
    Text("Hello")
}
.ignoresSafeArea() // VStack doesn't touch the edges, so this does nothing
```

### Problem 2: Applied to inner view inside an already-inset container

```swift
// BROKEN — ContentView's ZStack is already within the safe area frame
// provided by UIHostingController. The Color correctly extends,
// but the VStack children still get a safe-area-aware layout frame.
ZStack {
    Color.black.ignoresSafeArea()  // This works for the Color
    VStack {
        TerminalContainerView()
            .ignoresSafeArea()     // TerminalContainerView IS in the ZStack
                                   // frame, which is already inset by
                                   // UIHostingController at the host level
    }
}
```

### Problem 3: GeometryReader interaction

`GeometryReader` reports its own frame dimensions. If placed inside a safe-area-respecting container, `geo.size` will be the safe area frame, not the full screen. `ignoresSafeArea()` applied to the GeometryReader itself makes it fill the screen, but then `geo.safeAreaInsets` returns `.zero`, breaking inset-based calculations.

```swift
// BROKEN — geo.size is the safe-area-shrunk frame
GeometryReader { geo in
    let topInset = geo.safeAreaInsets.top  // non-zero here
    VStack { ... }
}
.ignoresSafeArea() // Now geo fills screen BUT safeAreaInsets become zero
                   // — the insets you read are now wrong
```

The fix is to read safe area insets via a separate reader, not the one you expand:

```swift
// CORRECT — read insets from environment, not from GeometryReader
@Environment(\.safeAreaInsets) private var safeAreaInsets
```

Or use a `.background` GeometryReader trick (see Fix Layer 1).

### Problem 4: UIHostingController injects insets before SwiftUI even starts

`UIHostingController` sets `additionalSafeAreaInsets` and propagates UIKit's safe area into the SwiftUI environment. Even with perfect `ignoresSafeArea()` placement in your SwiftUI tree, the host has already shrunk the root frame. This is the root cause that survives all pure-SwiftUI fixes.

---

## Fix Layer 1 — Correct SwiftUI Modifier Placement

This is the minimum fix for cases where UIHostingController's baseline behavior is acceptable and you just need the background to bleed edge-to-edge.

### Pattern: Color background only

Apply `ignoresSafeArea()` to the background `Color`, not to the content container:

```swift
struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)   // background bleeds to all edges

            VStack(spacing: 0) {
                // content respects safe area automatically
                SessionTabBar()
                TerminalView()
                KeyboardView()
            }
            // NO ignoresSafeArea here — let content stay in safe area
        }
    }
}
```

This makes the background fill the screen while content is still properly inset. This works for scanner/connecting screens but does NOT solve the terminal needing to fill the full frame.

### Pattern: Full-frame container with ignoresSafeArea on ZStack

```swift
struct TerminalContainerView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "1a1a2e")

            VStack(spacing: 0) {
                // Manually pad the top so content clears Dynamic Island
                Color.clear.frame(height: 0) // placeholder; use safeAreaInset
                SessionTabBar()
                TerminalView()
                KeyboardView()
            }
        }
        .ignoresSafeArea(.container, edges: .all)  // ZStack touches all edges
    }
}
```

When `ignoresSafeArea` is applied to a `ZStack` that fills the parent, the ZStack expands to fill the screen. Children of the ZStack still receive the full-screen frame proposal. However, child SwiftUI views will not automatically re-apply safe area insets — you must handle insets manually.

### Pattern: safeAreaInset modifier (iOS 15+, additive approach)

Instead of ignoring safe area and re-adding manual spacing, you can keep safe area active and push specific views to fill certain edges:

```swift
VStack(spacing: 0) {
    SessionTabBar()
    TerminalView()
    KeyboardView()
}
.safeAreaInset(edge: .bottom, spacing: 0) {
    Color.clear.frame(height: 0) // reserves nothing extra but satisfies layout
}
```

This is better suited for adding footers at the bottom edge. For a terminal that should fill everything, it is less useful.

### Reading safe area insets correctly

To manually position content while ignoring the safe area frame, read insets from the environment or a dedicated background reader:

```swift
// Option A: environment key (requires custom environment key or iOS 15+ safeAreaInsets)
struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: 0)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: TopInsetKey.self,
                                            value: geo.safeAreaInsets.top)
                        }
                    )
                // rest of content
            }
        }
    }
}

// Option B: Place GeometryReader as a ZStack background (does not affect layout)
ZStack {
    GeometryReader { proxy in
        // proxy.safeAreaInsets are the TRUE device insets because
        // this GeometryReader is behind the .ignoresSafeArea() boundary
        Color.clear.onAppear {
            topInset = proxy.safeAreaInsets.top
            bottomInset = proxy.safeAreaInsets.bottom
        }
    }
    .ignoresSafeArea()  // This reader fills the screen; reads real insets

    // Foreground content laid out normally
    VStack(spacing: 0) {
        Color.clear.frame(height: topInset)   // spacer for Dynamic Island
        SessionTabBar()
        TerminalView()
        Color.clear.frame(height: bottomInset) // spacer for home indicator
    }
}
```

---

## Fix Layer 2 — UIHostingController.safeAreaRegions

**Available since iOS 16.4. This is the recommended authoritative fix.**

`UIHostingController.safeAreaRegions` controls which safe area regions the hosting controller injects into the SwiftUI view tree. Removing `.container` stops UIKit from shrinking the SwiftUI root frame around hardware/system chrome insets.

### Using a custom App entry point

Replace the `@main` App struct's `WindowGroup` with a custom `UIApplicationDelegate` or `UIWindowSceneDelegate`:

```swift
// AppDelegate.swift
import UIKit
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let rootView = ContentView()
            .environmentObject(ConnectionManager())

        let hostingController = UIHostingController(rootView: rootView)

        // Remove container safe area injection entirely.
        // SwiftUI's ignoresSafeArea() will now work from a full-screen frame.
        hostingController.safeAreaRegions = []                    // remove ALL regions
        // OR: hostingController.safeAreaRegions.remove(.container) // keep keyboard avoidance

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = hostingController
        window?.makeKeyAndVisible()
        return true
    }
}
```

With `safeAreaRegions = []` (or `.remove(.container)`), the SwiftUI tree now receives a full-screen frame. The `ignoresSafeArea()` modifiers you have on `Color` backgrounds will work correctly, and the `VStack` will also fill the full frame.

### Keeping the App struct but wrapping with UIHostingController

If you want to keep the `App` struct approach, you can intercept via `UIWindowSceneDelegate`:

```swift
// In BashMirrorApp.swift
@main
struct BashMirrorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ConnectionManager())
                .preferredColorScheme(.dark)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Find the UIHostingController SwiftUI created and fix its safeAreaRegions
        DispatchQueue.main.async {
            if let hostingVC = windowScene.windows.first?.rootViewController as? UIHostingController<AnyView> {
                hostingVC.safeAreaRegions.remove(.container)
            }
        }
    }
}
```

Note: The `DispatchQueue.main.async` is needed because `UIHostingController` is installed by SwiftUI after the scene delegate fires. A cleaner approach is the full `UIApplicationDelegate` takeover above.

---

## Fix Layer 3 — UIViewController edgesForExtendedLayout

This is the UIKit-level flag that predates safe areas (it was the mechanism for "extend content under nav bar" behavior). It remains effective:

```swift
hostingController.edgesForExtendedLayout = .all
hostingController.extendedLayoutIncludesOpaqueBars = true
```

These flags tell UIKit: "let this view controller's view extend under translucent and opaque bars." Combined with `safeAreaRegions.remove(.container)`, they ensure both UIKit's layout system and SwiftUI's safe area environment are fully cleared.

For completeness in the `UIApplicationDelegate` approach:

```swift
let hostingController = UIHostingController(rootView: rootView)
hostingController.safeAreaRegions.remove(.container)
hostingController.edgesForExtendedLayout = .all
hostingController.extendedLayoutIncludesOpaqueBars = true
```

---

## WKWebView-Specific: contentInsetAdjustmentBehavior

`WKWebView` contains a `UIScrollView`. By default, `UIScrollView` automatically adjusts `contentInset` based on safe area insets (`contentInsetAdjustmentBehavior = .automatic`). This means even after fixing the SwiftUI/UIKit layer, the scroll view inside `WKWebView` will re-add padding on its own.

Fix this in `makeUIView`:

```swift
func makeUIView(context: Context) -> NoKeyboardWebView {
    // ... existing setup ...
    let webView = NoKeyboardWebView(frame: .zero, configuration: config)

    // Disable scroll view safe area adjustment
    webView.scrollView.contentInsetAdjustmentBehavior = .never

    // These you already have:
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false

    return webView
}
```

With `contentInsetAdjustmentBehavior = .never`, the scroll view ignores all safe area insets and the web content fills the view frame exactly.

---

## iOS 26 Native SwiftUI WebView

iOS 26 (shipped with Xcode 26) adds a native `WebView` type to the WebKit framework that is a first-class SwiftUI view. It eliminates the need for `UIViewRepresentable` entirely:

```swift
import WebKit
import SwiftUI

struct TerminalView: View {
    @State private var page = WebPage()

    var body: some View {
        WebView(page)
            .ignoresSafeArea()   // works correctly on the native type
    }
}
```

Key differences from the `WKWebView` wrapper approach:
- `ignoresSafeArea()` works directly on `WebView` without any UIHostingController intervention.
- No `contentInsetAdjustmentBehavior` fix is needed; the SwiftUI layout system handles it.
- `WebPage` is `Observable`, replacing the `WKNavigationDelegate`/`WKScriptMessageHandler` pattern.
- Custom URL scheme handlers are supported via `URLSchemeHandler`.

For BashMirror's use case (loading a local `terminal.html` with `WKUserContentController` message handlers), the migration path would be to use `WebPage` with a custom `URLSchemeHandler` for the local HTML and JavaScript message handlers. This is a larger refactor but is the correct long-term direction for iOS 26+ targets.

---

## Info.plist Settings

No `Info.plist` keys directly control edge-to-edge safe area behavior. However, two keys are relevant:

### UIStatusBarStyle

```xml
<key>UIStatusBarStyle</key>
<string>UIStatusBarStyleLightContent</string>
```

Setting a light or dark status bar style ensures the status bar text is readable when content bleeds behind it. Does not affect layout.

### UIViewControllerBasedStatusBarAppearance

```xml
<key>UIViewControllerBasedStatusBarAppearance</key>
<true/>
```

With this set to `true` (the default), each view controller can declare its own `preferredStatusBarStyle`. This is needed if you want the status bar to appear correctly over dark terminal content without a navigation bar covering it.

### UIRequiresFullScreen

```xml
<key>UIRequiresFullScreen</key>
<true/>
```

Relevant for iPad multitasking — forces the app to full screen. Does not affect iPhone safe area behavior.

There is no `Info.plist` key to disable safe areas globally.

---

## Applying the Fix to BashMirror

### Diagnosis of the current code

Looking at the existing `TerminalContainerView`:

```swift
GeometryReader { geo in
    let topInset = geo.safeAreaInsets.top
    let bottomInset = geo.safeAreaInsets.bottom

    VStack(spacing: 0) {
        Color(hex: "1a1a2e").frame(height: topInset)
        SessionTabBar()
        TerminalView()
        if showKeyboard {
            FullKeyboardView { ... }
            Color(UIColor.systemGray6).frame(height: bottomInset)
        }
    }
    .ignoresSafeArea()
}
```

Two problems:
1. `geo.safeAreaInsets` returns non-zero insets because the `GeometryReader` is still within the safe-area frame provided by `UIHostingController`. The `.ignoresSafeArea()` on the `VStack` fires but the `VStack` doesn't physically touch the edges (the `GeometryReader` and `UIHostingController` have already contracted the available space).
2. Even if the `VStack` expansion worked, `geo.safeAreaInsets` after expansion would return `.zero` because `ignoresSafeArea` zeroes out the insets for its children.

### Minimal fix: TerminalView.swift — add contentInsetAdjustmentBehavior

This is required regardless of which layout fix you pick:

```swift
// In makeUIView, add this line:
webView.scrollView.contentInsetAdjustmentBehavior = .never
```

### Full fix option A: UIHostingController safeAreaRegions (recommended)

Replace `BashMirrorApp.swift` entry point with a `UIApplicationDelegate`-based setup:

```swift
import UIKit
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let connectionManager = ConnectionManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let rootView = ContentView()
            .environmentObject(connectionManager)
            .preferredColorScheme(.dark)

        let hosting = UIHostingController(rootView: rootView)
        hosting.safeAreaRegions.remove(.container)

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = hosting
        window?.makeKeyAndVisible()
        return true
    }
}
```

Then simplify `TerminalContainerView` — the GeometryReader inset-reading workaround is no longer needed:

```swift
struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showKeyboard = true

    var body: some View {
        VStack(spacing: 0) {
            if connectionManager.sessions.count > 0 {
                SessionTabBar(showKeyboard: $showKeyboard)
            }

            if let activeSession = connectionManager.activeSessionId {
                TerminalView(sessionId: activeSession)
                    .id(activeSession)
            } else {
                Color(hex: "1a1a2e")
                    .overlay(
                        Text("No active session")
                            .foregroundColor(.gray)
                            .font(.system(.body, design: .monospaced))
                    )
            }

            if showKeyboard {
                FullKeyboardView { key in
                    if let session = connectionManager.activeSessionId {
                        connectionManager.sendInput(session: session, data: key)
                    }
                }
            }
        }
        // Background fills behind Dynamic Island and home indicator
        .background(Color(hex: "1a1a2e").ignoresSafeArea())
        // The VStack content will still respect safe area by default.
        // If you want the tab bar behind the Dynamic Island, add:
        // .ignoresSafeArea(.container, edges: .top)
    }
}
```

After `safeAreaRegions.remove(.container)`, the SwiftUI tree starts with the full-screen frame. `Color(...).ignoresSafeArea()` in the background fills edge-to-edge. The `VStack` content remains in the safe area (which is now provided by SwiftUI's own layout engine reading device insets, not UIHostingController's injection).

### Full fix option B: Pure SwiftUI with correct ZStack placement

If you cannot change the `App` entry point, you need to ensure `ignoresSafeArea()` is applied to a view that actually reaches the screen edges. The outermost `ZStack` in `ContentView` is the candidate:

```swift
struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        ZStack {
            Color(hex: "1a1a2e")   // background applied separately

            switch connectionManager.state {
            case .disconnected:
                ScannerContainerView()
            case .connecting:
                ProgressView("Connecting...").foregroundColor(.white)
            case .connected:
                TerminalContainerView()
            }
        }
        .ignoresSafeArea(.container, edges: .all)  // ZStack fills to edges
        // Now TerminalContainerView receives a full-screen frame proposal
    }
}
```

And in `TerminalContainerView`, read insets via a background `GeometryReader` that ignores the safe area (so it reports real insets):

```swift
struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showKeyboard = true
    @State private var topInset: CGFloat = 59    // fallback for Dynamic Island
    @State private var bottomInset: CGFloat = 34  // fallback for home indicator

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)  // spacer for Dynamic Island

            if connectionManager.sessions.count > 0 {
                SessionTabBar(showKeyboard: $showKeyboard)
            }

            if let activeSession = connectionManager.activeSessionId {
                TerminalView(sessionId: activeSession)
                    .id(activeSession)
            } else {
                Color(hex: "1a1a2e")
                    .overlay(Text("No active session").foregroundColor(.gray))
            }

            if showKeyboard {
                FullKeyboardView { key in
                    if let session = connectionManager.activeSessionId {
                        connectionManager.sendInput(session: session, data: key)
                    }
                }
                Color(hex: "1a1a2e").frame(height: bottomInset)
            }
        }
        .background(
            // This GeometryReader fills to screen edges (ignores safe area)
            // so it reads the TRUE device insets, not zero.
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        topInset = proxy.safeAreaInsets.top
                        bottomInset = proxy.safeAreaInsets.bottom
                    }
            }
            .ignoresSafeArea()
        )
    }
}
```

This is more fragile than option A because it depends on modifier ordering in the ZStack hierarchy. Option A is cleaner.

---

## Decision Matrix

| Scenario | Recommended Fix |
|---|---|
| Background color bleeds, content respects safe area | `Color.ignoresSafeArea()` only (pure SwiftUI) |
| Full frame fill needed, WKWebView | `UIHostingController.safeAreaRegions.remove(.container)` + `scrollView.contentInsetAdjustmentBehavior = .never` |
| iOS 26+ new project | Native `WebView` (WebKit) + `.ignoresSafeArea()` |
| Cannot change App entry point | ZStack `.ignoresSafeArea()` + background GeometryReader for insets |
| Need to preserve keyboard avoidance | `.remove(.container)` only, leave `.keyboard` in `safeAreaRegions` |

---

## Common Mistakes Reference

| Mistake | Why It Fails | Fix |
|---|---|---|
| `.ignoresSafeArea()` on inner VStack | VStack doesn't touch screen edges | Apply to outermost full-frame container |
| Reading `geo.safeAreaInsets` after `.ignoresSafeArea()` on same reader | Insets become zero after expansion | Use a separate background GeometryReader with its own `.ignoresSafeArea()` |
| Fixing SwiftUI but not WKWebView scroll view | `UIScrollView` re-adds insets independently | Set `contentInsetAdjustmentBehavior = .never` |
| Removing all `safeAreaRegions` but wanting keyboard avoidance | `.all` removes keyboard region too | Use `.remove(.container)` not `.safeAreaRegions = []` |
| Expecting `Info.plist` to disable safe areas | No such key exists | Use code-level fixes |

---

## Appendices

### A. Glossary

- **Safe area**: The screen rectangle unobstructed by hardware features and system chrome.
- **Dynamic Island**: The pill-shaped cutout on iPhone 14 Pro+ that replaces the notch.
- **Home indicator**: The horizontal swipe bar at the bottom of notch/island devices.
- **safeAreaRegions**: `UIHostingController` property (iOS 16.4+) controlling which safe area regions are injected into the SwiftUI tree.
- **contentInsetAdjustmentBehavior**: `UIScrollView` property controlling whether the scroll view automatically adjusts its content inset based on safe area insets.
- **edgesForExtendedLayout**: `UIViewController` property (UIKit) controlling whether the view extends under translucent or opaque bars.

### B. Key API References

- `View.ignoresSafeArea(_:edges:)` — [Apple Docs](https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:))
- `UIHostingController.safeAreaRegions` — [Apple Docs](https://developer.apple.com/documentation/swiftui/uihostingcontroller/safearearegions)
- `UIScrollView.contentInsetAdjustmentBehavior` — UIKit docs
- `WebView` (iOS 26) — [WWDC 2025 Session 231](https://developer.apple.com/videos/play/wwdc2025/231/)
- [SwiftUI Field Guide: Safe Area](https://www.swiftuifieldguide.com/layout/safe-area/)
- [Mastering Safe Area in SwiftUI — fatbobman](https://fatbobman.com/en/posts/safearea/)
- [AppCoda: SwiftUI WebView in iOS 26](https://www.appcoda.com/swiftui-webview/)
- [InfoQ: SwiftUI for iOS 26 WebView](https://www.infoq.com/news/2025/06/swiftui-ios26-liquid-glass/)

### C. References & Citations

1. Apple Developer Documentation — `ignoresSafeArea(_:edges:)` — https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:)
2. Apple Developer Documentation — `UIHostingController.safeAreaRegions` — https://developer.apple.com/documentation/swiftui/uihostingcontroller/safearearegions
3. Apple Developer Documentation — `UIHostingController` — https://developer.apple.com/documentation/swiftui/uihostingcontroller
4. SwiftUI Field Guide — Safe Area — https://www.swiftuifieldguide.com/layout/safe-area/
5. fatbobman — Mastering Safe Area in SwiftUI — https://fatbobman.com/en/posts/safearea/
6. Martin Lasek — UIHostingController + SafeArea — https://www.martinlasek.com/articles/uihostingcontroller-and-safearea
7. Apple Developer Forums — Additional safe area insets in SwiftUI — https://developer.apple.com/forums/thread/678463
8. OpenRadar FB8176223 — UIHostingController unable to disable safe area — https://openradar.appspot.com/FB8176223
9. AppCoda — Exploring WebView and WebPage in SwiftUI for iOS 26 — https://www.appcoda.com/swiftui-webview/
10. InfoQ — SwiftUI for iOS 26 Embraces Liquid Glass, Introduces WebView — https://www.infoq.com/news/2025/06/swiftui-ios26-liquid-glass/
11. Apple WWDC 2025 — Meet WebKit for SwiftUI — https://developer.apple.com/videos/play/wwdc2025/231/
12. Hacking with Swift — How to place content outside the safe area — https://www.hackingwithswift.com/quick-start/swiftui/how-to-place-content-outside-the-safe-area
13. Swift with Majid — Managing safe area in SwiftUI — https://swiftwithmajid.com/2021/11/03/managing-safe-area-in-swiftui/

---

## Conclusion

The reliable, production-grade fix for edge-to-edge layout with `WKWebView` in SwiftUI is a two-part change:

1. In the `UIHostingController` setup, call `hostingController.safeAreaRegions.remove(.container)`. This requires switching from a `Scene`-based `@main` to a `UIApplicationDelegate`-based entry point, or intercepting via `UIWindowSceneDelegate`. This removes the root-level safe area injection so SwiftUI views receive a full-screen frame.

2. In `TerminalView.makeUIView`, add `webView.scrollView.contentInsetAdjustmentBehavior = .never`. This prevents `UIScrollView` inside `WKWebView` from independently re-adding safe area padding.

After these two changes, the existing `Color(hex:...).ignoresSafeArea()` backgrounds in `ContentView` and `TerminalContainerView` will correctly bleed to all edges, and the `WKWebView` frame will fill exactly the space SwiftUI assigns it.

For iOS 26+ long-term: migrate to the native `WebView` (WebKit), which is a proper SwiftUI view and handles `.ignoresSafeArea()` without any UIKit scaffolding.

---

_Research conducted on 2026-03-20 | Sources: 13 authoritative references_
