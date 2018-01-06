import Foundation
import JavaScriptCore
import AXSwift


@objc protocol PointExport: JSExport {
    var x: Float { get }
    var y: Float { get }
}

class Point: NSObject, PointExport {
    let x: Float
    let y: Float
    init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
    
    static func ofNS(point: NSPoint) -> Point {
        return Point.init(x: Float(point.x), y: Float(point.y))
    }
    
    static func ofNS(size: NSSize) -> Point {
        return Point.init(x: Float(size.width), y: Float(size.height))
    }
    
    static func ofJS(_ point: JSValue) -> Point {
        return Point.init(
            x: Float(point.objectForKeyedSubscript("x").toNumber().floatValue),
            y: Float(point.objectForKeyedSubscript("y").toNumber().floatValue))
    }
}

extension NSPoint {
    static func from(_ point: PointExport) -> NSPoint {
        return NSPoint.init(x: Int(point.x), y: Int(point.y))
    }
}

extension NSSize {
    static func from(_ point: PointExport) -> NSSize {
        return NSSize.init(width: Int(point.x), height: Int(point.y))
    }
}

@objc protocol RectExport: JSExport {
    var pos: PointExport { get set }
    var size: PointExport { get set }
}

class Rect: NSObject, RectExport {
    var pos: PointExport
    var size: PointExport
    init(pos: Point, size: Point) {
        self.pos = pos
        self.size = size
    }
    static func ofNS(_ r: NSRect) -> Rect {
        return Rect.init(pos: Point.ofNS(point: r.origin), size: Point.ofNS(size: r.size))
    }
    static func ofJS(_ r: JSValue) -> Rect {
        let pos: JSValue = r.objectForKeyedSubscript("pos")
        let size: JSValue = r.objectForKeyedSubscript("size")
        return Rect.init(pos: Point.ofJS(pos), size: Point.ofJS(size))
    }
}

extension NSRect {
    static func from(rect: RectExport) -> NSRect {
        return NSRect.init(x: Int(rect.pos.x), y: Int(rect.pos.y), width: Int(rect.size.x), height: Int(rect.size.y))
    }
}

@objc protocol Connectable : JSExport {
    func connect(_ signal: String, _ fn: JSValue)
}

class WindowRef : NSObject {
    let app: NSRunningApplication
    let win: UIElement
    init(app: NSRunningApplication, win: UIElement) {
        self.app = app
        self.win = win
    }
}

@objc protocol SystemExport: JSExport {
    func currentWindow() -> WindowRef?
    func windowRect(_ w: WindowRef) -> RectExport?
    func moveResize(_ win: WindowRef, _ rect: JSValue) -> ()
    func workspaceArea(_ win: WindowRef) -> RectExport?
    func unmaximize(_ win: WindowRef) -> ()
    func maximize(_ win: WindowRef) -> ()
    func getMaximized(_ win: WindowRef) -> Bool
    func visibleWindows() -> [Any] // actually (WindowRef, Array<WindowRef>) but JSExport doesn't allow it
    func minimizedWindows() -> Array<WindowRef>
    func activate(_ win: WindowRef) -> ()
    func minimize(_ win: WindowRef) -> ()
    func unminimize(_ win: WindowRef) -> ()
    func activateLater(_ win: WindowRef) -> ()
    func setWindowHidden(_ win: WindowRef, _ hidden: Bool) -> ()
    func stableSequence(_ win: WindowRef) -> Int
    func windowTitle(_ win: WindowRef) -> String?
    
    var Cairo : CairoExport { get }
    var Clutter : ClutterExport { get }
    
    // pull out constructors as functions, for simpler interface
    func newClutterColor(_ attrs: JSValue) -> ClutterColorExport
    func newClutterActor() -> ActorExport
    func newClutterCanvas() -> ClutterCanvasExport
}

class CocoaSystem: NSObject, SystemExport {
    let Clutter: ClutterExport = ClutterJS.init()
    let Cairo: CairoExport = CairoJS.init()
    var screen: NSScreen!
    private var jsError: JSValue?
    private let ctx: JSContext
    private var previousSizeCache: [(pid: pid_t, frame: NSRect)] // TODO: track per workspace?
    private let previousSizeCacheMax = 10
    private let ec: DispatchQueue
    
    init(_ ctx: JSContext) {
        self.ctx = ctx
        self.previousSizeCache = []
        self.ec = DispatchQueue.global(qos: .userInteractive)
        super.init()
        ctx.exceptionHandler = { context, exception in
            self.jsError = exception
            //            NSLog("JS Error: \(exception?.description ?? "unknown error")")
        }
    }
    
    private func captureJSError(_ result: JSValue?) throws -> JSValue {
        if let error = jsError {
            jsError = nil
            var desc = String(describing: error)
            if let stack = error.forProperty("stack") {
                desc += "\n" + String(describing: stack)
            }
            throw RuntimeError.init(desc)
        }
        return result ?? JSValue.init(undefinedIn: ctx)
    }
    
    @discardableResult
    func callJS(_ fn: JSValue, arguments: [Any]!) throws -> JSValue {
        return try captureJSError(fn.call(withArguments: arguments))
    }
    
    @discardableResult
    func callJSMethod(_ obj: JSValue, fn: String, arguments: [Any]!) throws -> JSValue {
        return try captureJSError(obj.invokeMethod(fn, withArguments: arguments))
    }
    
    func moveResize(_ win: WindowRef, _ jsrect: JSValue) {
        let rect = Rect.ofJS(jsrect)
        moveResizeNS(win, pos: NSPoint.from(rect.pos), size: NSSize.from(rect.size))
    }
    
    func moveResizeNS(_ win: WindowRef, pos: NSPoint, size: NSSize) {
        ec.async { logException(desc: "moveResize") {
            try win.win.setAttribute(.size, value: size)
            try win.win.setAttribute(.position, value: pos)
            try win.win.setAttribute(.size, value: size)
        }}
    }
    
    func workspaceArea(_ win: WindowRef) -> RectExport? {
        if let frame = workspaceAreaNS() {
            return Rect.ofNS(frame)
        }
        return nil
    }
    
    func workspaceAreaNS() -> NSRect? {
        return NSScreen.main?.visibleFrame
    }
    
    private func pushPreviousSize(_ win: WindowRef) -> Void {
        previousSizeCache = previousSizeCache.filter { ps in ps.pid != win.app.processIdentifier }
        while(previousSizeCache.count > previousSizeCacheMax) {
            previousSizeCache.removeFirst()
        }
        if let frame = windowRectNS(win) {
            previousSizeCache.append((pid: win.app.processIdentifier, frame: frame))
        }
    }
    
    private func popPreviousSize(_ win: WindowRef) -> NSRect? {
        if let idx = previousSizeCache.index(where: { pair in pair.pid == win.app.processIdentifier }) {
            let result = previousSizeCache[idx]
            previousSizeCache.remove(at: idx)
            return result.frame
        } else {
            NSLog("Can't find previous frame for \(win.app) in \(previousSizeCache)")
            return nil
        }
    }
    
    func maximize(_ win: WindowRef) {
        // not a real maximize, but nobody likes that anyway
        if let rect = workspaceAreaNS() {
            pushPreviousSize(win)
            moveResizeNS(win, pos: rect.origin, size: rect.size)
        }
    }
    
    func unmaximize(_ win: WindowRef) {
        logException(desc: "unmaximize") {
            try win.win.setAttribute(.fullScreen, value: false)
        }
        if let frame = popPreviousSize(win) {
            NSLog("Restoring previous frame: \(frame)")
            moveResizeNS(win, pos: frame.origin, size: frame.size)
        }
    }
    
    func getMaximized(_ win: WindowRef) -> Bool {
        let fullscreen = logExceptionOpt(desc: "getMaximized") { try win.win.attribute(.fullScreen) as Bool? }
        if (fullscreen == true) {
            return true
        }
        
        guard let workspaceRect = workspaceAreaNS() else { return false }
        guard let windowRect = windowRectNS(win) else { return false }
        
        // this is a bit loose, but mostly works
        func area(_ s: NSSize) -> Int {
            return Int(s.width) * Int(s.height)
        }
        let workspaceArea = area(workspaceRect.size)
        let windowArea = area(windowRect.size)
        let tolerance = Int(0.05 * Double(workspaceArea))
        let difference = abs(workspaceArea - windowArea)
        
        let isMaximized = difference < tolerance
        NSLog("isMaximized: \(isMaximized) ( diff = \(difference), tolerance = \(tolerance) )")
        return isMaximized
    }
    
    private func allApplications() -> Array<NSRunningApplication> {
        return NSWorkspace.shared.runningApplications
    }
    
    private func isNormalWindow(_ win: UIElement) -> Bool {
        do {
            if let subrole = try win.attribute(.subrole) as String? {
                return subrole == kAXStandardWindowSubrole
            }
            // no subrole attribute: assume normal
            return true
        } catch {
            return false
        }
    }
    
    private func windowsFromApp(_ app: Application, runningApp: NSRunningApplication) throws -> [WindowRef]? {
        if let windows = try app.windows() {
            return windows
                .filter(isNormalWindow)
                .map { win in WindowRef.init(app: runningApp, win: win) }
        } else {
            return nil
        }
    }
    
    private func windowsFromVisibleApps() -> Array<WindowRef> {
        var result: Array<WindowRef> = []
        allApplications().forEach { runningApp in
            if !runningApp.isHidden {
                swallowException {
                    if let app = Application.init(runningApp) {
                        if let windows = try windowsFromApp(app, runningApp: runningApp) {
                            result.append(contentsOf: windows)
                        }
                    }
                }
            }
        }
        // NSLog("retrieved \(result.count) windows")
        return result
    }
    
    private func isMinimized(_ win: WindowRef) throws -> Bool {
        return try win.win.attribute(.minimized) as Bool? ?? false
    }
    
    func visibleWindowsTyped() -> (WindowRef?, [WindowRef]) {
        return logException(desc: "visibleWindows") {
            let visible = try windowsFromVisibleApps().filter { win in try !isMinimized(win) }
            
            var current: WindowRef? = nil
            if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                current = visible.first(where: { win in
                    win.app == frontmostApp && isMain(window: win.win)
                })
            }
            return (current, visible)
        } ?? (nil, [])
    }
    
    func visibleWindows() -> [Any] {
        let (current, all) = visibleWindowsTyped()
        return [current as Any, all]
    }
    
    func minimizedWindows() -> Array<WindowRef> {
        return logException(desc: "minimizedWindows") {
            try windowsFromVisibleApps().filter { win in try isMinimized(win) }
        } ?? []
    }
    
    func stableSequence(_ win: WindowRef) -> Int {
        // Cocoa doesn't give us one without stupid amounts of effort.
        // Currently only used to differentiate windows with identical frames,
        // so pid+titleHash should be good enough

        let title = windowTitle(win)
        NSLog("getting stableSequence for window \(String(describing: title))")
        return Int(win.app.processIdentifier) + (title?.hashValue ?? 0)
    }
    
    func windowTitle(_ win: WindowRef) -> String? {
        return logExceptionOpt(desc: "windowTitle") {
            return try win.win.attribute(.title) as String?
        }
    }
    
    func activate(_ win: WindowRef) {
        ec.async { logException(desc: "activate") {
            let pid = try win.win.pid()
            guard let app: NSRunningApplication = NSRunningApplication.init(processIdentifier: pid) else {
                NSLog("Unable to get app \(pid)")
                return
            }
            
            let success = app.activate(options: [.activateAllWindows,.activateIgnoringOtherApps])
            if (!success) {
                NSLog("NSRunningApplication.activate() failed")
                return
            }
            
            NSLog("Activating window of app \(win.app)")
            try win.win.setAttribute(Attribute.main, value: true)
        }}
    }
    
    func minimize(_ win: WindowRef) {
        logException(desc: "minimize") {
            try win.win.setAttribute(.minimized, value: true)
        }
    }
    
    func unminimize(_ win: WindowRef) {
        logException(desc: "unminimize") {
            try win.win.setAttribute(.minimized, value: false)
        }
    }
    
    func activateLater(_ win: WindowRef) {
        activate(win)
    }
    
    func setWindowHidden(_ win: WindowRef, _ hidden: Bool) {
        ec.async { logException(desc: "setWindowHidden") {
            try win.win.setAttribute(.hidden, value: hidden)
        }}
    }
    
    private func isMain(window: UIElement) -> Bool {
        return logExceptionOpt(desc: "isMain") { try window.attribute(.main) } ?? false
    }

    func currentWindow() -> WindowRef? {
        if let application = NSWorkspace.shared.frontmostApplication {
            let uiApp = Application(application)!
            if let wins = logExceptionOpt(desc: "uiApp.windows()", { try uiApp.windows() }) {
                let frontmostOpt = wins.first(where: { win in isMain(window: win) })
                if let frontmost = frontmostOpt {
                    return WindowRef.init(app: application, win: frontmost)
                }
            }

            // XXX .focusedWindow or mainWindow ought to do it, but returns an unknown type which isn't an AXUIElement:
            
            //            if let win: AXUIElement = try! uiApp.attribute(.mainWindow) {
            //                print(try! UIElement.init(win).attribute(.role) ?? "(no role)")
            //                return WindowRef.init(UIElement.init(win))
            //            }

            //            if let win: AXUIElement = try! uiApp.attribute(.focusedWindow) {
            //                print(try! UIElement.init(win).attribute(.role) ?? "(no role)")
            //                return WindowRef.init(UIElement.init(win))
            //            }
        }
        return nil
    }
    
    private func windowRectNS(_ w: WindowRef) -> NSRect? {
        return logExceptionOpt(desc: "frame") {
            // NSLog("Getting frame attribute from \(w.win)")
            return try (w.win.attribute(.frame) as NSValue?)?.rectValue
        }
    }
    
    func windowRect(_ w: WindowRef) -> RectExport? {
        return windowRectNS(w).map(Rect.ofNS)
    }
    
    func newClutterColor(_ attrs: JSValue) -> ClutterColorExport {
        func component(_ name: String) -> Int {
            return attrs.objectForKeyedSubscript(name)?.toNumber()?.intValue ?? 0
        }
        return ClutterColor.init(
            red: component("red"),
            green: component("green"),
            blue: component("blue"),
            alpha: component("alpha")
        )
    }
    
    func newClutterActor() -> ActorExport {
        return Actor.init(Sys: self)
    }
    
    func newClutterCanvas() -> ClutterCanvasExport {
        return ClutterCanvas.init(Sys: self)
    }
    
}

extension JSExport {
    func nonNull() -> Self? {
        if let _ = self as? NSNull {
            return nil
        }
        return self
    }
}

extension JSValue {
    func nonNull() -> Self? {
        if (self.isNull || self.isUndefined) {
            return nil
        }
        return self
    }
}

extension NSScreen {
    func invertYAxis(point: NSPoint) -> NSPoint {
        return NSPoint.init(x: Int(point.x), y: invertYAxis(y: Int(point.y)))
    }
    
    func invertYAxis(y: Int) -> Int {
        let frame = visibleFrame
        let screenHeight = Int(frame.size.height)
        let inverted = (y - Int(screenHeight)) * -1
//        NSLog("point's y = \(y), in bounds \(screenHeight) at offset \(screenOffset) -> \(inverted)")
        return inverted
    }
}
