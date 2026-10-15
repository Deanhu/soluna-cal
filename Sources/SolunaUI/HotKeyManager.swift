import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey：无需辅助功能权限，纯监听场景足够）
public final class HotKeyManager {
    public static let shared = HotKeyManager()
    private init() {}

    /// 按键组合（Carbon keyCode + modifier 位）
    public struct Combo: Codable, Equatable {
        public var keyCode: UInt32
        public var carbonModifiers: UInt32
        /// 默认 ⌥C
        public static let `default` = Combo(keyCode: UInt32(kVK_ANSI_C),
                                            carbonModifiers: UInt32(optionKey))
        /// 展示用（如 ⌥C）
        public var display: String {
            var s = ""
            if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            s += KeyCodes.name(of: keyCode)
            return s
        }
    }

    public var onTrigger: () -> Void = {}
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// 注册全局热键；返回是否成功（冲突/非法返回 false，调用方提示换键）
    @discardableResult
    public func register(_ combo: Combo) -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onTrigger() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef) == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x534C4E31), id: 1)  // 'SLN1'
        return RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                   GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    public func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
    }

    /// 从 NSEvent 按键生成 Combo（必须含至少一个修饰键，否则拒绝）
    public static func combo(from event: NSEvent) -> Combo? {
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        guard mods != 0 else { return nil }
        return Combo(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
    }

    /// 持久化
    public static var saved: Combo {
        get {
            let ud = UserDefaults.standard
            guard ud.object(forKey: "hotKey.keyCode") != nil else { return .default }
            return Combo(keyCode: UInt32(ud.integer(forKey: "hotKey.keyCode")),
                         carbonModifiers: UInt32(ud.integer(forKey: "hotKey.mods")))
        }
        set {
            UserDefaults.standard.set(Int(newValue.keyCode), forKey: "hotKey.keyCode")
            UserDefaults.standard.set(Int(newValue.carbonModifiers), forKey: "hotKey.mods")
        }
    }
}

/// keyCode → 键名（常用键覆盖，未收录显示「键n」）
enum KeyCodes {
    static func name(of code: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L", UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X", UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "空格", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        ]
        return map[code] ?? "键\(code)"
    }
}
