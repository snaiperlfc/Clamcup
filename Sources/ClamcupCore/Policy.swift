import Foundation

/// Режим, который пользователь выбирает в приложении.
public enum Mode: String, Sendable {
    /// Не засыпать, пока Mac на зарядке
    case auto
    /// Обычный сон
    case off

    /// Разбирает содержимое файла режима. Всё, кроме `off` в первой строке, считается `auto`:
    /// файл пишет пользовательский процесс, и мусор в нём не должен ломать службу.
    public init(fileContents: String?) {
        let firstLine = fileContents?
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespaces)
        self = firstLine == "off" ? .off : .auto
    }

    public var fileContents: String { rawValue + "\n" }
}

/// Состояние, по которому служба решает, что делать со сном.
public struct PowerSnapshot: Equatable, Sendable {
    public var mode: Mode
    public var onAC: Bool
    public var sleepDisabled: Bool
    public var lidClosed: Bool

    public init(mode: Mode, onAC: Bool, sleepDisabled: Bool, lidClosed: Bool) {
        self.mode = mode
        self.onAC = onAC
        self.sleepDisabled = sleepDisabled
        self.lidClosed = lidClosed
    }
}

public enum PowerAction: Equatable, Sendable {
    case setSleepDisabled(Bool)
    case sleepNow
}

/// Что сделать, чтобы привести систему к нужному состоянию.
///
/// Сон отключён только в режиме `auto` на зарядке. Отдельный случай: Mac сняли с зарядки,
/// когда крышка уже закрыта (например, сразу убрали в рюкзак). Событие закрытия прошло,
/// и сама macOS его не повторит, поэтому Mac нужно усыпить явно.
public func plannedActions(for snapshot: PowerSnapshot) -> [PowerAction] {
    let wantDisabled = snapshot.mode == .auto && snapshot.onAC
    var actions: [PowerAction] = []

    if snapshot.sleepDisabled != wantDisabled {
        actions.append(.setSleepDisabled(wantDisabled))
    }
    if snapshot.sleepDisabled, !wantDisabled, !snapshot.onAC, snapshot.lidClosed {
        actions.append(.sleepNow)
    }
    return actions
}
