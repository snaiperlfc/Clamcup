import Foundation
import IOKit
import IOKit.ps

/// Чтение состояния питания. Работает без root.
public enum PowerStatus {
    public static func isOnAC() -> Bool {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else {
            // Не смогли прочитать — считаем батареей: это безопасная сторона, сон не отключится
            return false
        }
        return (type as String) == kIOPMACPowerKey
    }

    public static func isLidClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }

        let value = IORegistryEntryCreateCFProperty(
            rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return (value as? Bool) ?? false
    }

    /// Отключён ли сон через `pmset disablesleep`. Публичного API для этого флага нет, поэтому читаем `pmset -g`.
    public static func isSleepDisabled() -> Bool {
        guard let output = PMSet.run(["-g"]) else { return false }
        return parseSleepDisabled(pmsetOutput: output)
    }

    /// Пока сон ни разу не отключали, строки `SleepDisabled` в выводе может не быть.
    public static func parseSleepDisabled(pmsetOutput: String) -> Bool {
        pmsetOutput.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count >= 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
        }
    }
}

/// Обёртка над /usr/bin/pmset.
public enum PMSet {
    /// Возвращает stdout или nil, если pmset не запустился или завершился с ошибкой.
    @discardableResult
    public static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
