import Foundation
import Cocoa
import JavaScriptCore

@objc protocol ActorExport : Connectable, JSExport {
    var view: ClutterView { get }
    func set_position(_ x: NSNumber, _ y: NSNumber) -> ()
    func set_size(_ x: NSNumber, _ y: NSNumber) -> ()
    func set_opacity(n: NSNumber) -> ()
    func set_reactive(_ x: Bool) -> ()
    func add_actor(_ a: ActorExport) -> ()
    func remove_child(_ a: ActorExport) -> ()
    func set_background_color(_ c: ClutterColorExport) -> ()
    func insert_child_above(_ a: ActorExport, _ target: ActorExport?) -> ()
    func set_content(_ canvas: ClutterCanvasExport) -> ()
    func grab_key_focus() -> ()
    func hide() -> ()
    func show() -> ()
}

class ClutterView : NSView {
    var motionHandler: ((NSEvent) -> ())?
    var keyDownHandler: ((ClutterKeyEvent) -> ())?
    var keyUpHandler: ((ClutterKeyEvent) -> ())?
    var buttonHandler: ((NSEvent) -> ())?
    var backgroundColor: NSColor?
    private var currentFlags: NSEvent.ModifierFlags = NSEvent.ModifierFlags.init(rawValue: 0)
    
    override var acceptsFirstResponder: Bool { get { return true } }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override var isFlipped: Bool {
        get { return true }
    }
    
    private func invokeHandler(_ fn: ((NSEvent) -> ())?, _ event: NSEvent) -> Bool {
        // NSLog("invoking handler \(String(describing: fn)) for event \(event)")
        if let handler = fn {
            handler(event)
            return true
        }
        return false
    }
    
    override func mouseMoved(with event: NSEvent) {
        if !invokeHandler(motionHandler, event) {
            super.mouseMoved(with: event)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if let handler = keyDownHandler {
            let clutterEvent = ClutterKeyEvent.fromNS(event: event)
            handler(clutterEvent)
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        let prevFlags = self.currentFlags
        let currentFlags = event.modifierFlags
        self.currentFlags = currentFlags
        
        func handle(_ flags: NSEvent.ModifierFlags, isPress: Bool) -> Bool {
            if let event = ClutterKeyEvent.fromNS(flags: flags) {
                if let handler = isPress ? keyDownHandler : keyUpHandler {
                    handler(event)
                    return true
                }
            }
            return false
        }
        
        if handle(currentFlags.subtracting(prevFlags), isPress: true) {
            return
        }
        if handle(prevFlags.subtracting(currentFlags), isPress: false) {
            return
        }
        super.flagsChanged(with: event)
    }
    
    override func mouseDown(with event: NSEvent) {
        if !invokeHandler(buttonHandler, event) {
            super.mouseDown(with: event)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // NSLog("drawing ClutterView dirtyRect: \(dirtyRect) of \(self)")
        if let bg = self.backgroundColor {
            bg.setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }
    
    func invalidate() {
        // NSLog("invalidating canvas of \(self)")
        self.needsDisplay = true
    }
}

class Actor: NSObject, ActorExport {
    let Sys: CocoaSystem
    let view: ClutterView
    private var explicitSize: NSSize?
    private var trackingArea: NSTrackingArea?
    
    init(Sys: CocoaSystem, view: ClutterView) {
        self.Sys = Sys
        self.view = view
        super.init()
    }
    
    convenience init(Sys: CocoaSystem) {
        self.init(Sys: Sys, view: ClutterView.init())
    }
    
    func autosizeToParent() {
        if explicitSize == nil {
            if let parent = view.superview {
                view.setFrameSize(parent.frame.size)
            }
        }
    }
    
    func connect(_ signal: String, _ fn: JSValue) {
        switch(signal) {
        case "motion-event":
            if self.trackingArea == nil {
                let trackingArea = NSTrackingArea.init(
                    rect: view.bounds,
                    options: [.mouseMoved, .activeAlways],
                    owner: view, userInfo: nil)
                view.addTrackingArea(trackingArea)
                self.trackingArea = trackingArea
                func onMotionEvent(_ event: NSEvent) {
                    let clutterEvent = ClutterMouseEvent.fromNS(screen: Sys.screen!, event)
                    logException(desc: "onMotionEvent") {
                        try Sys.callJS(fn, arguments: [self as ActorExport, clutterEvent])
                    }
                }
                view.motionHandler = onMotionEvent
            }
            break
        case "button-press-event":
            func onButtonPress(_ event: NSEvent) {
                logException(desc: "onButtonPressEvent") {
                    try Sys.callJS(fn, arguments: [self as ActorExport])
                }
            }
            view.buttonHandler = onButtonPress
            break
        case "key-press-event":
            func onKeyDown(_ event: ClutterKeyEvent) {
                logException(desc: "onKeyPressEvent") {
                    try Sys.callJS(fn, arguments: [self as ActorExport, event])
                }
            }
            view.keyDownHandler = onKeyDown
            break
            
        case "key-release-event":
            func onKeyUp(_ event: ClutterKeyEvent) {
                logException(desc: "onKeyReleaseEvent") {
                    try Sys.callJS(fn, arguments: [self as ActorExport, event])
                }
            }
            view.keyUpHandler = onKeyUp
            break
        default:
            NSLog("Error: Unknown signal: \(signal) for \(self)")
        }
    }
    
    func set_position(_ x: NSNumber, _ y: NSNumber) {
        let point = NSPoint.init(x: x.intValue, y: y.intValue)
        debug("set position \(point) of \(view)")
        view.setFrameOrigin(point)
        view.invalidate()
    }
    
    func set_size(_ x: NSNumber, _ y: NSNumber) {
        let size = NSSize.init(width: x.intValue, height: y.intValue)
        explicitSize = size
        debug("set size \(size) of \(view)")
        view.setFrameSize(size)
        view.invalidate()
    }
    
    func add_actor(_ a: ActorExport) {
        debug("adding view \(a.view) to \(view)")
        view.addSubview(a.view)
        (a as! Actor).autosizeToParent()
    }
    
    func insert_child_above(_ a: ActorExport, _ targetNullable: ActorExport?) {
        let targetView = targetNullable?.nonNull()?.view
        debug("adding view \(a.view) above \(String(describing: targetView)) on \(view)")
        view.addSubview(a.view, positioned: .above, relativeTo: targetView)
        (a as! Actor).autosizeToParent()
    }
    
    func remove_child(_ a: ActorExport) {
        if let win = a.view.window {
            if (a.view.superview == win.contentView) {
                debug("removing toplevel view; closing window")
                win.close()
                return
            }
        }
        a.view.removeFromSuperview()
    }
    
    func hide() {
        view.isHidden = true
    }
    
    func show() {
        view.isHidden = false
    }
    
    func grab_key_focus() {
        guard let win = view.window else {
            NSLog("grab_key_focus(): no window")
            return
        }
        if (!win.makeFirstResponder(view)) {
            NSLog("view \(view) refused firstResponder")
        }
    }
    
    func set_opacity(n: NSNumber) {
        view.alphaValue = CGFloat.init(n.floatValue / 255.0)
    }
    
    func set_reactive(_ x: Bool) {
        // all cocoa views are reactive
    }
    
    func set_background_color(_ c: ClutterColorExport) {
        func component(_ v: Int) -> CGFloat { return CGFloat.init(v) / 255 }
        view.backgroundColor = NSColor.init(
            red: component(c.red),
            green: component(c.green),
            blue: component(c.blue),
            alpha: component(c.alpha)
        )
        view.invalidate()
    }
    
    func set_content(_ canvas: ClutterCanvasExport) {
        add_actor(canvas as! ClutterCanvas)
    }
}

@objc protocol ClutterCanvasExport : JSExport {
    func set_size(_ x: NSNumber, _ y: NSNumber) -> ()
    func invalidate() -> ()
}

class CairoView : ClutterView {
    var onDraw: ((_: CairoContextExport) throws -> ())?
    override var isOpaque: Bool {
        get { return false }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // NSLog("drawing CairoView dirtyRect: \(dirtyRect)")
        super.draw(dirtyRect)
        if let delegate = self.onDraw {
            try! CairoJS.draw(view: self, delegate: delegate)
        }
    }
}

class ClutterCanvas : Actor, ClutterCanvasExport {
    init(Sys: CocoaSystem) {
        let view = CairoView.init()
        // disabled for now, seems to cause SIGABRT consistently on mouseMove handler
//        view.wantsLayer = true // enables this view to have transparency overlayed on parent views
        super.init(Sys: Sys, view: view)
    }
    
    func invalidate() {
        view.invalidate()
    }
    
    override func connect(_ signal: String, _ fn: JSValue) {
        switch(signal) {
        case "draw":
            func draw(ctx: CairoContextExport) throws -> () {
                try Sys.callJS(fn, arguments: [self as ClutterCanvasExport, ctx])
            }
            (self.view as! CairoView).onDraw = draw
            break
        default:
            super.connect(signal, fn)
        }
    }
}

@objc protocol ClutterColorExport : JSExport {
    var red: Int { get }
    var green: Int { get }
    var blue: Int { get }
    var alpha: Int { get }
}

class ClutterColor : NSObject, ClutterColorExport {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int
    
    init(red: Int, green: Int, blue: Int, alpha: Int) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

@objc protocol ClutterMouseEventExport : JSExport {
    func get_coords() -> Array<Int>
}

class ClutterMouseEvent : NSObject, ClutterMouseEventExport {
    private let x: Int
    private let y: Int
    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
    
    convenience init(point: GPoint<Gnome,Workspace>) {
        self.init(x: Int(point.ns.x), y: Int(point.ns.y))
    }
    
    static func fromNS(screen: NSScreen, _ event: NSEvent) -> ClutterMouseEvent {
        let eventPoint: GPoint<Cocoa,Workspace> = GPoint(ns: event.locationInWindow)
        return ClutterMouseEvent.init(point: eventPoint.invert(from: screen.workspaceSize().cocoa))
    }

    func get_coords() -> Array<Int> {
        return [x, y]
    }
}

@objc protocol ClutterKeyEventExport : JSExport {
    func get_key_code() -> Int
    func get_state() -> Int
}

class ClutterKeyEvent : NSObject, ClutterKeyEventExport {
    private let code: Int
    private let state: Int
    init(code: Int, state: Int) {
        self.code = code
        self.state = state
    }
    
    static func stateOf(flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if (flags.contains(.shift)) {
            result = ClutterJS.SHIFT_MASK
        }
        NSLog("stateOf(\(flags): \(result) . also shift = \(NSEvent.ModifierFlags.shift)")
        return result
    }
    
    static func codeOf(flags: NSEvent.ModifierFlags) -> Int? {
        if flags.contains(.shift) { return 50 }
        if flags.contains(.command) { return 64 } // treat cmd as ctrl
        if flags.contains(.option) { return 133 }
        return nil
    }
    
    static func codeOf(nsKeyCode code: UInt16) -> Int {
        // emulate linux / clutter keycodes
        switch (code) {
            case Keycode.escape: return 9
            case Keycode.shift: return 50
            case Keycode.space: return 65
            case Keycode.control: return 64
            // case Keycode.alt: return 133 // XXX ALT?
            case Keycode.tab: return 23
            case Keycode.u: return 30
            case Keycode.i: return 31
            case Keycode.o: return 32
            case Keycode.a: return 38
            case Keycode.h: return 43
            case Keycode.j: return 44
            case Keycode.k: return 45
            case Keycode.l: return 46
            case Keycode.upArrow: return 111
            case Keycode.downArrow: return 116
            case Keycode.leftArrow: return 113
            case Keycode.rightArrow: return 114
            case Keycode.minus: return 20
            case Keycode.equals: return 21
            case Keycode.returnKey: return 36
            default:
                NSLog("uninterpreted key: \(code)")
                return 0
        }
    }
    
    static func fromNS(event: NSEvent) -> ClutterKeyEvent {
        NSLog("event: \(event) w/ flags \(event.modifierFlags) and code \(event.keyCode)")
        return ClutterKeyEvent.init(
            code: codeOf(nsKeyCode: event.keyCode),
            state: stateOf(flags: event.modifierFlags)
        )
    }
    
    static func fromNS(flags: NSEvent.ModifierFlags) -> ClutterKeyEvent? {
        if let code = codeOf(flags: flags) {
            return ClutterKeyEvent.init(code: code, state: 0)
        }
        return nil
        
    }
    
    func get_key_code() -> Int { return code }
    func get_state() -> Int { return state }
}

@objc protocol ClutterExport : JSExport {
    var EVENT_STOP: NSNumber { get }
    var SHIFT_MASK: Int { get }
    func grab_pointer() -> ()
    func grab_keyboard() -> ()
    func ungrab_pointer() -> ()
    func ungrab_keyboard() -> ()
}

class ClutterJS : NSObject, ClutterExport {
    let EVENT_STOP: NSNumber = NSNumber.init(value: true)
    static let SHIFT_MASK = 1
    let SHIFT_MASK: Int = ClutterJS.SHIFT_MASK
    func grab_pointer() -> () {}
    func grab_keyboard() -> () {}
    func ungrab_pointer() -> () {}
    func ungrab_keyboard() -> () {}
}
