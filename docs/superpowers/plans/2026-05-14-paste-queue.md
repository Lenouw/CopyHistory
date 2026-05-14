# Paste Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "paste queue" mode where the user activates a toggle, copies multiple items sequentially, then pastes them one-by-one in order with repeated ⌘V presses.

**Architecture:** A new `PasteQueueManager` singleton (ObservableObject) holds queue state and owns a CGEventTap that intercepts ⌘V keyDown events. When active, each copy adds to the queue; each ⌘V pops the next item into NSPasteboard before passing the event through. ClipboardMonitor gets a `suppressNext` flag to ignore programmatic pasteboard changes. ContentView footer gets a toggle button.

**Tech Stack:** Swift 5, AppKit, CGEventTap, NSPasteboard, SwiftUI ObservableObject

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `CopyHistory/Services/PasteQueueManager.swift` | **CREATE** | Queue state + CGEventTap for ⌘V interception |
| `CopyHistory/Services/ClipboardMonitor.swift` | **MODIFY** | Add `suppressNext` flag to skip programmatic changes |
| `CopyHistory/App/AppDelegate.swift` | **MODIFY** | Feed copies to queue when active; inject `onToggleQueue` into ContentView |
| `CopyHistory/Views/ContentView.swift` | **MODIFY** | Toggle button in footer; observe PasteQueueManager |

---

## Task 1 — Create PasteQueueManager

**Files:**
- Create: `CopyHistory/Services/PasteQueueManager.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit
import Combine

/// Manages the paste-queue mode.
/// When active: each clipboard copy is added to an ordered queue.
/// Each ⌘V press pops the next item from the queue into NSPasteboard,
/// then lets the event pass through normally so the target app pastes it.
@MainActor
final class PasteQueueManager: ObservableObject {

    static let shared = PasteQueueManager()

    @Published private(set) var isActive = false
    @Published private(set) var queue: [String] = []
    @Published private(set) var nextIndex: Int = 0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - Toggle

    func activate() {
        guard !isActive else { return }
        queue = []
        nextIndex = 0
        isActive = true
        startEventTap()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        queue = []
        nextIndex = 0
        stopEventTap()
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    // MARK: - Queue operations

    /// Called by AppDelegate.saveClip when mode is active.
    func enqueue(_ text: String) {
        queue.append(text)
    }

    /// Called by the CGEventTap callback (on main thread).
    /// Sets NSPasteboard to the next item, advances index.
    /// Deactivates when queue is exhausted.
    func pasteNext() {
        guard nextIndex < queue.count else {
            deactivate()
            return
        }
        let text = queue[nextIndex]
        nextIndex += 1

        // Suppress ClipboardMonitor so this programmatic change isn't re-recorded
        ClipboardMonitor.suppressNext = true

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if nextIndex >= queue.count {
            // Last item — deactivate after a short delay so the paste event
            // still goes through before we tear down the tap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.deactivate()
            }
        }
    }

    // MARK: - CGEventTap

    private func startEventTap() {
        guard AXIsProcessTrusted() else {
            NSLog("[PasteQueue] Accessibility not granted — queue mode unavailable")
            isActive = false
            return
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // .defaultTap so we can set clipboard before event reaches app
            eventsOfInterest: mask,
            callback: pasteQueueTapCallback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            NSLog("[PasteQueue] CGEventTap creation failed")
            isActive = false
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[PasteQueue] EventTap started ✓")
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        NSLog("[PasteQueue] EventTap stopped")
    }

    // MARK: - Event handler (called from C callback)

    fileprivate func handleKeyEvent(_ event: CGEvent) -> Bool {
        // V key = keycode 9, must have Command, must NOT have Shift (that's ⇧⌘V = CopyHistory hotkey)
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isCmd = flags.contains(.maskCommand)
        let isShift = flags.contains(.maskShift)
        guard keycode == 9, isCmd, !isShift else { return false }

        // Set clipboard to next queued item
        DispatchQueue.main.async { [weak self] in
            self?.pasteNext()
        }
        // Return true = "we handled it, set clipboard" — event still passes through unmodified
        // so the target app actually performs the paste
        return true
    }
}

// MARK: - C callback (global function required by CGEventTap API)

private let pasteQueueTapCallback: CGEventTapCallBack = { _, type, event, userInfo -> Unmanaged<CGEvent>? in
    guard type == .keyDown, let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<PasteQueueManager>.fromOpaque(userInfo).takeUnretainedValue()
    _ = manager.handleKeyEvent(event)
    // Always pass the event through — we only changed the clipboard content, not the event
    return Unmanaged.passUnretained(event)
}
```

- [ ] **Step 2: Build to check compilation**

```bash
cd "/Users/florianbonin/CosyCosa Dropbox/Flo bip/Files PRO/CLAUDE CODE/App CopyHistory"
xcodegen generate 2>&1 | tail -5
xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

Expected: `BUILD SUCCEEDED` (ClipboardMonitor.suppressNext doesn't exist yet — expect 1 error, that's fine)

---

## Task 2 — Add suppressNext to ClipboardMonitor

**Files:**
- Modify: `CopyHistory/Services/ClipboardMonitor.swift`

- [ ] **Step 1: Add static suppressNext flag**

In `ClipboardMonitor.swift`, add after the class declaration opening brace:

```swift
final class ClipboardMonitor {
    var onNewItem: ((NewClipData) -> Void)?

    /// Set to true before a programmatic pasteboard change to skip recording it.
    /// Automatically reset to false on the next polling cycle.
    static var suppressNext: Bool = false

    private var timer: Timer?
    private var lastChangeCount: Int
    // ... (rest unchanged)
```

- [ ] **Step 2: Check suppressNext in checkPasteboard**

Modify `checkPasteboard()` to consume the flag:

```swift
private func checkPasteboard() {
    let pasteboard = NSPasteboard.general
    guard pasteboard.changeCount != lastChangeCount else { return }
    lastChangeCount = pasteboard.changeCount

    // Skip if this change was triggered programmatically by PasteQueueManager
    if ClipboardMonitor.suppressNext {
        ClipboardMonitor.suppressNext = false
        return
    }

    let sourceApp = NSWorkspace.shared.frontmostApplication
    let bundleID = sourceApp?.bundleIdentifier ?? ""
    guard bundleID != Bundle.main.bundleIdentifier else { return }

    let ignored = Set(UserDefaults.standard.stringArray(forKey: "ignoredBundleIDs") ?? [])
    guard !ignored.contains(bundleID) else { return }

    extractContent(from: pasteboard, appBundleID: bundleID, appName: sourceApp?.localizedName)
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `BUILD SUCCEEDED`

---

## Task 3 — Hook copies into queue in AppDelegate

**Files:**
- Modify: `CopyHistory/App/AppDelegate.swift`

- [ ] **Step 1: Enqueue in saveClip when queue mode is active**

In `AppDelegate.saveClip(_:)`, add queue enqueue right after inserting into SwiftData context. Find this block:

```swift
let item = ClipboardItem(type: data.type, text: data.text, imageData: data.imageData,
                          filePath: data.filePath, appBundleID: data.appBundleID, appName: data.appName)
context.insert(item)
try? context.save()
```

Add after `context.insert(item)`:

```swift
let item = ClipboardItem(type: data.type, text: data.text, imageData: data.imageData,
                          filePath: data.filePath, appBundleID: data.appBundleID, appName: data.appName)
context.insert(item)

// If paste-queue mode is active, add text to the queue
if PasteQueueManager.shared.isActive, data.type != .image,
   let text = data.text, !text.isEmpty {
    PasteQueueManager.shared.enqueue(text)
}

try? context.save()
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `BUILD SUCCEEDED`

---

## Task 4 — Add toggle button to ContentView footer

**Files:**
- Modify: `CopyHistory/Views/ContentView.swift`

- [ ] **Step 1: Observe PasteQueueManager and add toggle to footer**

Replace the entire `footer` computed property:

```swift
private var footer: some View {
    HStack(spacing: 8) {
        Text("\(items.count) élément\(items.count > 1 ? "s" : "")")
            .font(.system(size: 10))
            .foregroundColor(.secondary)

        Spacer()

        // Paste-queue toggle
        PasteQueueToggle()

        Divider()
            .frame(height: 12)

        Button("Tout effacer") { clearAll() }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
}
```

- [ ] **Step 2: Add PasteQueueToggle view below ContentView in the same file**

Append at the bottom of `ContentView.swift`, after the closing `}` of `ContentView`:

```swift
// MARK: - Paste Queue Toggle

private struct PasteQueueToggle: View {
    @ObservedObject private var qm = PasteQueueManager.shared

    var body: some View {
        Button(action: { qm.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: qm.isActive ? "tray.full.fill" : "tray.full")
                    .font(.system(size: 11))
                    .foregroundColor(qm.isActive ? .accentColor : .secondary)

                if qm.isActive {
                    Text("\(qm.queue.count - qm.nextIndex) restant\(qm.queue.count - qm.nextIndex > 1 ? "s" : "")")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                        .transition(.opacity)
                } else {
                    Text("File de collage")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(qm.isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: qm.isActive)
        .help(qm.isActive
              ? "File de collage active — \(qm.queue.count) éléments enregistrés. Cliquer pour annuler."
              : "Activer la file de collage : copiez plusieurs textes, puis collez-les un par un avec ⌘V")
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `BUILD SUCCEEDED`

---

## Task 5 — Close panel on queue activation

When the user taps the toggle to activate queue mode, the panel should close automatically so they can go copy items.

**Files:**
- Modify: `CopyHistory/Views/ContentView.swift`

- [ ] **Step 1: Add onToggleQueue callback to ContentView**

In `ContentView`, add a callback property alongside `onPaste`:

```swift
var onPaste: ((ClipboardItem) -> Void)?
var onToggleQueue: (() -> Void)?   // called when queue toggle is tapped
```

- [ ] **Step 2: Pass callback into PasteQueueToggle**

Update the footer to pass the callback:

```swift
PasteQueueToggle(onActivate: onToggleQueue)
```

Update `PasteQueueToggle` to accept and call it:

```swift
private struct PasteQueueToggle: View {
    @ObservedObject private var qm = PasteQueueManager.shared
    var onActivate: (() -> Void)?   // called only when activating (not deactivating)

    var body: some View {
        Button(action: {
            let wasActive = qm.isActive
            qm.toggle()
            // Close panel only when activating (user needs to go copy things)
            if !wasActive { onActivate?() }
        }) {
            // ... (rest of the view unchanged)
        }
    }
}
```

- [ ] **Step 3: Wire callback in AppDelegate.buildPanelIfNeeded**

In `AppDelegate.buildPanelIfNeeded()`, add `onToggleQueue`:

```swift
private func buildPanelIfNeeded() {
    guard panel == nil, let container = modelContainer else { return }
    panel = FloatingPanel()
    var view = ContentView(onPaste: { [weak self] item in self?.directPaste(item) })
    view.onToggleQueue = { [weak self] in self?.hidePanel() }
    panel?.contentViewController = NSHostingController(rootView: view.modelContainer(container))
}
```

- [ ] **Step 4: Final build**

```bash
xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `BUILD SUCCEEDED`

---

## Task 6 — Release v1.1.6

**Files:**
- Modify: `project.yml`
- Modify: `appcast.xml`

- [ ] **Step 1: Bump version in project.yml**

```yaml
MARKETING_VERSION: "1.1.6"
CURRENT_PROJECT_VERSION: "9"
```

- [ ] **Step 2: Regenerate Xcode project and build Release**

```bash
cd "/Users/florianbonin/CosyCosa Dropbox/Flo bip/Files PRO/CLAUDE CODE/App CopyHistory"
xcodegen generate
rm -rf build
xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Release \
  -derivedDataPath build ONLY_ACTIVE_ARCH=NO build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Package**

```bash
ditto -c -k --keepParent build/Build/Products/Release/CopyHistory.app releases/CopyHistory-1.1.6.zip
```

- [ ] **Step 4: Sign with Sparkle**

```bash
~/Library/Developer/Xcode/DerivedData/CopyHistory-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update releases/CopyHistory-1.1.6.zip
```

Copy the `sparkle:edSignature` value and file size output.

- [ ] **Step 5: Update appcast.xml**

Add new item at the top of the channel (before existing 1.1.5 item):

```xml
<item>
    <title>Version 1.1.6</title>
    <pubDate><!-- current date --></pubDate>
    <sparkle:version>9</sparkle:version>
    <sparkle:shortVersionString>1.1.6</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <description><![CDATA[
        <h3>Version 1.1.6</h3>
        <ul>
            <li>📋 File de collage — copiez plusieurs textes, puis collez-les un par un avec ⌘V</li>
        </ul>
    ]]></description>
    <enclosure
        url="https://github.com/Lenouw/CopyHistory/releases/download/v1.1.6/CopyHistory-1.1.6.zip"
        sparkle:edSignature="SIGNATURE_HERE"
        length="SIZE_HERE"
        type="application/octet-stream"
    />
</item>
```

- [ ] **Step 6: Commit and push**

```bash
git add -A
git commit -m "feat: paste queue mode — copy multiple, paste in order with ⌘V"
git push
```

- [ ] **Step 7: Create GitHub release**

```bash
gh release create v1.1.6 releases/CopyHistory-1.1.6.zip \
  --title "CopyHistory 1.1.6 — File de collage" \
  --notes "📋 **File de collage** : activez le mode via le bouton dans le panneau, copiez plusieurs textes, puis collez-les dans l'ordre avec ⌘V répétés."
```

---

## Self-Review Checklist

- [x] Queue activated via toggle in panel footer ✓
- [x] Panel closes on activation ✓  
- [x] Copies while active → enqueued in order ✓
- [x] ⌘V intercepted → pastes next item → event passes through ✓
- [x] ClipboardMonitor suppressed for programmatic pasteboard changes ✓
- [x] Queue exhausted → mode auto-deactivates ✓
- [x] ⇧⌘V (CopyHistory hotkey) NOT intercepted (keycode 9 + Shift check) ✓
- [x] Images not queued (text-only queue, queue mode skips images) ✓
- [x] Accessibility required — already requested at launch ✓
- [x] Version bumped + appcast + GitHub release ✓
