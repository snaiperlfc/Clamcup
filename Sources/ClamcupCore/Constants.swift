import Foundation

/// Идентификаторы и пути, общие для приложения, службы и скриптов установки.
/// Пути продублированы в Resources/install-helper.sh и uninstall-helper.sh — менять вместе.
public enum Constants {
    public static let bundleID = "io.github.snaiperlfc.Clamcup"
    public static let helperLabel = bundleID + ".helper"
    public static let helperPath = "/Library/PrivilegedHelperTools/" + helperLabel
    public static let helperPlistPath = "/Library/LaunchDaemons/" + helperLabel + ".plist"

    public static let supportDir = "/Library/Application Support/Clamcup"
    /// Режим работы. Файл принадлежит пользователю, его пишет приложение, читает служба
    public static let modeFile = supportDir + "/mode"
    public static let pidFile = supportDir + "/helper.pid"
    /// Версия установленной службы, её записывает install-helper.sh
    public static let versionFile = supportDir + "/helper-version"
    public static let logFile = "/var/log/clamcup.log"

    public static let repositoryURL = URL(string: "https://github.com/snaiperlfc/Clamcup")!
}
