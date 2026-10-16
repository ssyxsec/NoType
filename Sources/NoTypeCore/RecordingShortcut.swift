import Foundation

public struct RecordingShortcut: Codable, Equatable, Sendable {
    // Carbon modifier masks; stable across keyboard layouts and process restarts.
    public var keyCode: UInt32
    public var modifiers: UInt32
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
    public static let standard = RecordingShortcut(keyCode: 49, modifiers: control | option)
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    public var keyName: String { Self.keys[keyCode] ?? "Key \(keyCode)" }
    public var displayName: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + " " + keyName
    }
    public var validationError: String? {
        let allowed = Self.command | Self.shift | Self.option | Self.control
        guard modifiers & ~allowed == 0, modifiers & (Self.command | Self.option | Self.control) != 0 else {
            return "请至少搭配 Command、Option 或 Control 中的一个修饰键。"
        }
        guard Self.keys[keyCode] != nil else { return "暂不支持这个按键，请使用字母、数字、空格、方向键或功能键。" }
        if modifiers == Self.command && [12, 13, 4, 46, 48, 49].contains(keyCode) {
            return "这个组合常用于系统或应用操作，请换一个快捷键。"
        }
        return nil
    }
    public static let keys: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",
        24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",
        36:"Return",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",
        48:"Tab",49:"Space",50:"`",51:"Delete",76:"Enter",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",
        103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",115:"Home",116:"Page Up",
        117:"Forward Delete",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
    ]
}
