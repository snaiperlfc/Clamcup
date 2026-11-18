// Служба Clamcup. Запускается launchd от root и держит `pmset disablesleep` в нужном состоянии:
// сон отключён, только пока Mac на зарядке и выбран режим auto.
//
// Реагирует сразу на смену источника питания (уведомления IOKit) и на запись в файл режима
// (kqueue). Раз в минуту сверяется на случай ручного pmset или пропущенного события.
//
// Для проверки без root: CLAMCUP_SUPPORT_DIR задаёт каталог с файлом режима,
// CLAMCUP_DRY_RUN=1 пишет в журнал вместо вызова pmset.

import Foundation
import IOKit.ps
import ClamcupCore

setlinebuf(stdout)

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("\(formatter.string(from: Date())) \(message)")
}

@MainActor
final class Helper {
    private let resyncInterval: DispatchTimeInterval = .seconds(60)
    private let modeFile: String
    private let pidFile: String
    private let dryRun: Bool

    private var mode: Mode = .auto
    private var powerSource: CFRunLoopSource?
    private var modeWatch: DispatchSourceFileSystemObject?
    private var resyncTimer: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []

    init(environment: [String: String]) {
        let supportDir = environment["CLAMCUP_SUPPORT_DIR"] ?? Constants.supportDir
        modeFile = supportDir + "/mode"
        pidFile = supportDir + "/helper.pid"
        dryRun = environment["CLAMCUP_DRY_RUN"] == "1"
    }

    func start() {
        try? "\(getpid())\n".write(toFile: pidFile, atomically: true, encoding: .utf8)
        mode = readMode()
        log("started, mode \(mode.rawValue)\(dryRun ? ", dry run" : "")")
        apply()

        watchPowerSource()
        watchModeFile()
        startResyncTimer()
        handleTermination()
    }

    // MARK: - Состояние

    private func readMode() -> Mode {
        Mode(fileContents: try? String(contentsOfFile: modeFile, encoding: .utf8))
    }

    /// Перечитывает режим. Возвращает true, если он изменился.
    @discardableResult
    private func updateMode() -> Bool {
        let newMode = readMode()
        guard newMode != mode else { return false }
        mode = newMode
        log("mode \(mode.rawValue)")
        return true
    }

    private func apply() {
        let snapshot = PowerSnapshot(
            mode: mode,
            onAC: PowerStatus.isOnAC(),
            sleepDisabled: PowerStatus.isSleepDisabled(),
            lidClosed: PowerStatus.isLidClosed()
        )
        for action in plannedActions(for: snapshot) {
            perform(action)
        }
    }

    private func perform(_ action: PowerAction) {
        switch action {
        case .setSleepDisabled(let disabled):
            pmset(["-a", "disablesleep", disabled ? "1" : "0"])
        case .sleepNow:
            log("on battery with the lid closed: sleeping now")
            pmset(["sleepnow"])
        }
    }

    private func pmset(_ arguments: [String]) {
        let command = "pmset " + arguments.joined(separator: " ")
        if dryRun {
            log("dry run: \(command)")
        } else if PMSet.run(arguments) != nil {
            log(command)
        } else {
            log("error: \(command) failed")
        }
    }

    // MARK: - Источники событий

    private func watchPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // Источник добавлен в главный цикл, колбэк приходит в главном потоке
            MainActor.assumeIsolated {
                Unmanaged<Helper>.fromOpaque(context).takeUnretainedValue().apply()
            }
        }, context)?.takeRetainedValue()
        guard let source else {
            log("error: cannot subscribe to power source changes, relying on periodic checks")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    /// Следит за файлом режима. Если файл удалили или подменили, наблюдение
    /// ставится заново сразу или при следующей сверке.
    private func watchModeFile() {
        guard modeWatch == nil else { return }
        let fd = open(modeFile, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let watch = self.modeWatch else { return }
                if !watch.data.isDisjoint(with: [.delete, .rename]) {
                    watch.cancel()
                    self.modeWatch = nil
                    self.watchModeFile()
                }
                if self.updateMode() {
                    self.apply()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        modeWatch = source
    }

    private func startResyncTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + resyncInterval, repeating: resyncInterval)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.watchModeFile()
                self.updateMode()
                self.apply()
            }
        }
        timer.resume()
        resyncTimer = timer
    }

    /// При остановке (удаление, обновление, выключение) возвращаем обычный сон.
    private func handleTermination() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { exit(0) }
                    if PowerStatus.isSleepDisabled() {
                        self.pmset(["-a", "disablesleep", "0"])
                    }
                    try? FileManager.default.removeItem(atPath: self.pidFile)
                    log("stopped")
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

MainActor.assumeIsolated {
    let helper = Helper(environment: ProcessInfo.processInfo.environment)
    helper.start()
    withExtendedLifetime(helper) {
        RunLoop.main.run()
    }
}
