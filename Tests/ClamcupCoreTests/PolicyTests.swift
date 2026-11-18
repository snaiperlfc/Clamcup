import ClamcupCore
import Testing

@Suite("Решение службы")
struct PolicyTests {
    private func actions(
        _ mode: Mode, onAC: Bool, sleepDisabled: Bool, lidClosed: Bool
    ) -> [PowerAction] {
        plannedActions(for: PowerSnapshot(mode: mode, onAC: onAC, sleepDisabled: sleepDisabled, lidClosed: lidClosed))
    }

    @Test("На зарядке сон отключается")
    func acDisablesSleep() {
        #expect(actions(.auto, onAC: true, sleepDisabled: false, lidClosed: false) == [.setSleepDisabled(true)])
    }

    @Test("На зарядке с уже отключённым сном ничего не делаем")
    func acAlreadyDisabled() {
        #expect(actions(.auto, onAC: true, sleepDisabled: true, lidClosed: true).isEmpty)
    }

    @Test("Сняли с зарядки при открытой крышке: возвращаем сон")
    func batteryLidOpen() {
        #expect(actions(.auto, onAC: false, sleepDisabled: true, lidClosed: false) == [.setSleepDisabled(false)])
    }

    @Test("Сняли с зарядки при закрытой крышке: возвращаем сон и усыпляем")
    func batteryLidClosed() {
        #expect(
            actions(.auto, onAC: false, sleepDisabled: true, lidClosed: true)
                == [.setSleepDisabled(false), .sleepNow]
        )
    }

    @Test("На батарее со включённым сном крышку не трогаем: macOS усыпит сама")
    func batteryAlreadyNormal() {
        #expect(actions(.auto, onAC: false, sleepDisabled: false, lidClosed: true).isEmpty)
    }

    @Test("Режим off на зарядке возвращает сон без принудительного усыпления")
    func offModeOnAC() {
        #expect(actions(.off, onAC: true, sleepDisabled: true, lidClosed: true) == [.setSleepDisabled(false)])
    }

    @Test("Режим off на батарее при закрытой крышке усыпляет")
    func offModeOnBatteryLidClosed() {
        #expect(
            actions(.off, onAC: false, sleepDisabled: true, lidClosed: true)
                == [.setSleepDisabled(false), .sleepNow]
        )
    }
}

@Suite("Файл режима")
struct ModeFileTests {
    @Test(
        "Разбор содержимого",
        arguments: [
            ("off\n", Mode.off),
            ("off", .off),
            ("  off  \n", .off),
            ("auto\n", .auto),
            ("", .auto),
            ("rm -rf /\n", .auto),
            ("OFF\n", .auto),
            ("auto\noff\n", .auto),
        ]
    )
    func parse(contents: String, expected: Mode) {
        #expect(Mode(fileContents: contents) == expected)
    }

    @Test("Нет файла — auto")
    func missingFile() {
        #expect(Mode(fileContents: nil) == .auto)
    }

    @Test("Запись и чтение сходятся")
    func roundTrip() {
        for mode in [Mode.auto, .off] {
            #expect(Mode(fileContents: mode.fileContents) == mode)
        }
    }
}

@Suite("Вывод pmset")
struct PMSetParsingTests {
    @Test("SleepDisabled 1")
    func disabled() {
        let output = """
            System-wide power settings:
             SleepDisabled\t\t1
            Currently in use:
             sleep                0 (sleep prevented by powerd)
            """
        #expect(PowerStatus.parseSleepDisabled(pmsetOutput: output))
    }

    @Test("SleepDisabled 0")
    func enabled() {
        #expect(!PowerStatus.parseSleepDisabled(pmsetOutput: " SleepDisabled\t\t0\n sleep 1\n"))
    }

    @Test("Строки SleepDisabled нет")
    func missingLine() {
        #expect(!PowerStatus.parseSleepDisabled(pmsetOutput: "Currently in use:\n sleep 1\n displaysleep 2\n"))
    }
}
