import Cocoa
import ApplicationServices
import MASShortcut
//import AXSwift

class Keybinding {
    private static let AMKeyCodeInvalid: AMKeyCode = 0xFF

    typealias AMKeyCode = Int

    static func constructKeyCodeMap() -> [String: [AMKeyCode]] {
        
        var stringToKeyCodes: [String: [Int]] = [:]
        
        // Generate unicode character keymapping from keyboard layout data.  We go
        // through all keycodes and create a map of string representations to a list
        // of key codes. It has to map to a list because a string representation
        // canmap to multiple codes (e.g., 1 and numpad 1 both have string
        // representation "1").
        var currentKeyboard = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        var rawLayoutData = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData)
        
        if rawLayoutData == nil {
            currentKeyboard = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeUnretainedValue()
            rawLayoutData = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData)
        }
        
        // Get the layout
        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
        let layout: UnsafePointer<UCKeyboardLayout> = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        
        var keysDown: UInt32 = 0
        var chars: [UniChar] = [0, 0, 0, 0]
        var realLength: Int = 0
        
        for keyCode in (0..<AMKeyCodeInvalid) {
            switch keyCode {
            case kVK_ANSI_Keypad0:
                fallthrough
            case kVK_ANSI_Keypad1:
                fallthrough
            case kVK_ANSI_Keypad2:
                fallthrough
            case kVK_ANSI_Keypad3:
                fallthrough
            case kVK_ANSI_Keypad4:
                fallthrough
            case kVK_ANSI_Keypad5:
                fallthrough
            case kVK_ANSI_Keypad6:
                fallthrough
            case kVK_ANSI_Keypad7:
                fallthrough
            case kVK_ANSI_Keypad8:
                fallthrough
            case kVK_ANSI_Keypad9:
                continue
            default:
                break
            }
            
            UCKeyTranslate(layout,
                           UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay),
                           0,
                           UInt32(LMGetKbdType()),
                           UInt32(kUCKeyTranslateNoDeadKeysBit),
                           &keysDown,
                           chars.count,
                           &realLength,
                           &chars)
            
            let string = CFStringCreateWithCharacters(kCFAllocatorDefault, chars, realLength) as String
            
            if let keyCodes = stringToKeyCodes[string] {
                var mutableKeyCodes = keyCodes
                mutableKeyCodes.append(keyCode)
                stringToKeyCodes[string] = mutableKeyCodes
            } else {
                stringToKeyCodes[string] = [keyCode]
            }
        }
        
        // Add codes for non-printable characters. They are not printable so they
        // are not generated from the keyboard layout data.
        stringToKeyCodes["space"] = [kVK_Space]
        stringToKeyCodes["enter"] = [kVK_Return]
        stringToKeyCodes["up"] = [kVK_UpArrow]
        stringToKeyCodes["right"] = [kVK_RightArrow]
        stringToKeyCodes["down"] = [kVK_DownArrow]
        stringToKeyCodes["left"] = [kVK_LeftArrow]
        
        return stringToKeyCodes
    }
}
