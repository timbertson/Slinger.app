import Foundation
import Cocoa
import Cairo
import CCairo
import JavaScriptCore

@objc protocol CairoExport: JSExport {
    var CLEAR: Int { get }
}

enum CairoOperator: Int {
    case CLEAR = 1
}

class CairoJS : NSObject, CairoExport {
    let CLEAR: Int = CairoOperator.CLEAR.rawValue
    
    static func draw(view: NSView, delegate: (CairoContextExport) throws -> ()) throws -> () {
        guard let graphicsContext : CGContext = NSGraphicsContext.current?.cgContext else {
            NSLog("unable to get graphics context")
            return
        }

        let surface = try Cairo.Surface.Quartz.init(graphicsContext: graphicsContext,
                                                width: Int(view.bounds.size.width),
                                                height: Int(view.bounds.size.height))
        let context = Cairo.Context.init(surface: surface)
        let contextWrapper = CairoContext.init(context)
        try delegate(contextWrapper)
    }
}

@objc protocol CairoContextExport : JSExport {
    func fill() -> ()
    func stroke() -> ()
    func clip() -> ()
    func save() -> ()
    func paint() -> ()
    func restore() -> ()
    func resetClip() -> ()
    func setOperator(_ op: NSNumber) -> ()
    func setLineWidth(_ width: NSNumber) -> ()
    func rectangle(_ x: NSNumber, _ y: NSNumber, _ w: NSNumber, _ h: NSNumber) -> ()
    func arc(_ x: NSNumber, _ y: NSNumber, _ radius: NSNumber, _ start: NSNumber, _ end: NSNumber) -> ()
    func rotate(_ radians: NSNumber) -> ()
    func translate(_ x: NSNumber, _ y: NSNumber) -> ()
    func setSourceRGBA(_ r: NSNumber, _ g: NSNumber, _ b: NSNumber, _ a: NSNumber) -> ()
}

class CairoContext : NSObject, CairoContextExport {
    private let ctx: Cairo.Context
    
    init(_ ctx: Cairo.Context) {
        self.ctx = ctx
    }
    
    func fill() {
        ctx.fill()
    }
    
    func stroke() {
        ctx.stroke()
    }
    
    func clip() {
        ctx.clip()
    }
    
    func save() {
        ctx.save()
    }
    
    func paint() {
        ctx.paint()
    }
    
    func restore() {
        ctx.restore()
    }
    
    func resetClip() {
        ctx.resetClip()
    }
    
    func setOperator(_ op: NSNumber) {
        var cairoOp: cairo_operator_t?
        let opEnum = CairoOperator.init(rawValue: op.intValue)
        if let opEnum = opEnum {
            switch (opEnum) {
                case .CLEAR: cairoOp = CCairo.CAIRO_OPERATOR_CLEAR; break
            }
        }
        if let cairoOp = cairoOp {
            ctx.`operator` = cairoOp
        } else {
            NSLog("Unsupported cairo operator: \(op.intValue) -- \(String(describing: opEnum))")
        }
    }
    
    func setLineWidth(_ width: NSNumber) {
        ctx.lineWidth = width.doubleValue
    }
    
    func rectangle(_ x: NSNumber, _ y: NSNumber, _ w: NSNumber, _ h: NSNumber) {
        ctx.addRectangle(x: x.doubleValue, y: y.doubleValue, width: w.doubleValue, height: h.doubleValue)
    }
    
    func arc(_ x: NSNumber, _ y: NSNumber, _ radius: NSNumber, _ start: NSNumber, _ end: NSNumber) {
        ctx.addArc(center: (x: x.doubleValue, y: y.doubleValue), radius: radius.doubleValue, angle: (start.doubleValue, end.doubleValue))
    }
    
    func rotate(_ radians: NSNumber) {
        ctx.rotate(radians.doubleValue)
    }
    
    func translate(_ x: NSNumber, _ y: NSNumber) {
        ctx.translate(x: x.doubleValue, y: y.doubleValue)
    }
    
    func setSourceRGBA(_ r: NSNumber, _ g: NSNumber, _ b: NSNumber, _ a: NSNumber) {
        ctx.setSource(color: (red: r.doubleValue, green: g.doubleValue, blue: b.doubleValue, alpha: a.doubleValue))
    }
}
