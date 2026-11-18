import AppKit
import IOKit.ps
import ClamcupCore
import Observation
import ServiceManagement

enum HelperState: Equatable, Sendable {
    case checking
    case notInstalled
    /// Установлена служба другой версии
    case outdated
    /// Установлена, но процесс не жив
    case stopped
    case running
}

struct DeviceState: Equatable, Sendable {
    var onAC: Bool
    var lidClosed: Bool
    var sleepDisabled: Bool
    var mode: Mode
    var helper: HelperState
}

/// Главная строка состояния: заголовок панели и значок в строке меню.
enum Headline: Equatable {
    case checking
    case awake
    case onBattery
    case off
    case applying
    case needsHelper
    case helperStopped
}

/// Состояние для интерфейса. Сон переключает служба, приложение пишет режим в файл
/// и показывает, что происходит.
@MainActor
@Observable
final class StatusModel {
    private(set) var device: DeviceState
    private(set) var launchAtLogin: Bool

    let appVersion: String

    @ObservationIgnored private let isPreview: Bool
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var periodicRefresh: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    init(preview: DeviceState? = nil, launchAtLogin: Bool = false) {
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        isPreview = preview != nil
        device = preview ?? DeviceState(onAC: true, lidClosed: false, sleepDisabled: false, mode: .auto, helper: .checking)
        self.launchAtLogin = launchAtLogin
    }

    func start() {
        guard !isPreview else { return }
        watchPowerSource()
        // Раз в 30 с: заметить, что служба упала или кто-то вызвал pmset вручную
        periodicRefresh = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - Производные значения

    var headline: Headline {
        switch device.helper {
        case .checking: return .checking
        case .notInstalled: return .needsHelper
        case .stopped: return .helperStopped
        case .running, .outdated: break
        }
        if device.sleepDisabled { return .awake }
        if device.mode == .off { return .off }
        if !device.onAC { return .onBattery }
        return .applying
    }

    var menuBarSymbol: String {
        switch headline {
        case .awake: "cup.and.heat.waves.fill"
        case .needsHelper, .helperStopped: "exclamationmark.triangle"
        case .checking, .onBattery, .off, .applying: "cup.and.saucer"
        }
    }

    /// Режим можно менять, пока служба на месте: файл режима понимает любая её версия
    var canChangeMode: Bool {
        device.helper == .running || device.helper == .outdated
    }

    var stayAwake: Bool { device.mode == .auto }

    // MARK: - Обновление

    func refresh() {
        guard !isPreview else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let version = appVersion
        Task {
            let state = await Task.detached { Self.readDeviceState(bundledVersion: version) }.value
            // Более свежий запрос уже в пути
            guard generation == refreshGeneration else { return }
            device = state
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func refresh(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.refresh()
        }
    }

    nonisolated static func readDeviceState(bundledVersion: String) -> DeviceState {
        DeviceState(
            onAC: PowerStatus.isOnAC(),
            lidClosed: PowerStatus.isLidClosed(),
            sleepDisabled: PowerStatus.isSleepDisabled(),
            mode: Mode(fileContents: try? String(contentsOfFile: Constants.modeFile, encoding: .utf8)),
            helper: readHelperState(bundledVersion: bundledVersion)
        )
    }

    nonisolated static func readHelperState(bundledVersion: String) -> HelperState {
        let files = FileManager.default
        guard files.fileExists(atPath: Constants.helperPlistPath) else { return .notInstalled }
        guard isProcessAlive(pidFile: Constants.pidFile) else { return .stopped }

        let installed = (try? String(contentsOfFile: Constants.versionFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return installed == bundledVersion ? .running : .outdated
    }

    nonisolated private static func isProcessAlive(pidFile: String) -> Bool {
        guard
            let raw = try? String(contentsOfFile: pidFile, encoding: .utf8),
            let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            pid > 0
        else { return false }
        // Служба работает от root: живой процесс ответит на kill(pid, 0) отказом EPERM
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func watchPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // Источник в главном цикле, колбэк приходит в главном потоке.
            // Служба отрабатывает событие сама, итог читаем чуть позже
            MainActor.assumeIsolated {
                Unmanaged<StatusModel>.fromOpaque(context).takeUnretainedValue().refresh(after: .seconds(1))
            }
        }, context)?.takeRetainedValue()
        guard let source else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    // MARK: - Действия

    func setStayAwake(_ on: Bool) {
        let mode: Mode = on ? .auto : .off
        do {
            // Без atomically: каталог службы принадлежит root, временный файл рядом не создать
            try mode.fileContents.write(toFile: Constants.modeFile, atomically: false, encoding: .utf8)
        } catch {
            showError(String(localized: "Couldn't change the mode"), error.localizedDescription)
            return
        }
        device.mode = mode
        refresh(after: .milliseconds(700))
    }

    func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            showError(String(localized: "Couldn't change the login item"), error.localizedDescription)
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = service.status == .enabled
    }

    func installHelper() {
        guard let script = Bundle.main.url(forResource: "install-helper", withExtension: "sh") else {
            showError(String(localized: "Couldn't install the helper"), "install-helper.sh is missing from the app bundle")
            return
        }
        runPrivileged(
            ["/bin/bash", script.path, NSUserName(), appVersion],
            prompt: String(localized: "Clamcup will install a helper that keeps your Mac awake on power."),
            failureTitle: String(localized: "Couldn't install the helper")
        )
    }

    func uninstallHelper() {
        guard let script = Bundle.main.url(forResource: "uninstall-helper", withExtension: "sh") else {
            showError(String(localized: "Couldn't remove the helper"), "uninstall-helper.sh is missing from the app bundle")
            return
        }
        runPrivileged(
            ["/bin/bash", script.path],
            prompt: String(localized: "Clamcup will remove its helper and restore normal sleep."),
            failureTitle: String(localized: "Couldn't remove the helper")
        )
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Constants.logFile))
    }

    func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: String(localized: "Keeps your Mac awake on power, even with the lid closed.") + "\n",
            attributes: base
        )
        var link = base
        link[.link] = Constants.repositoryURL
        credits.append(NSAttributedString(string: String(localized: "Source code on GitHub"), attributes: link))

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Служебное

    /// Запускает команду от root через стандартный запрос пароля администратора.
    /// Отмену пользователем (ошибка -128) не показываем.
    private func runPrivileged(_ arguments: [String], prompt: String, failureTitle: String) {
        let command = arguments.map(Self.shellQuoted).joined(separator: " ")
        let source = "do shell script \(Self.appleScriptQuoted(command)) "
            + "with prompt \(Self.appleScriptQuoted(prompt)) with administrator privileges"

        NSApp.activate()
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            showError(failureTitle, error[NSAppleScript.errorMessage] as? String ?? "")
        }
        refresh(after: .seconds(1))
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func appleScriptQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
