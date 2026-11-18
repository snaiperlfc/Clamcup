// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clamcup",
    platforms: [.macOS(.v14)],
    targets: [
        // Общее для приложения и службы: режим, решение «что делать со сном», чтение состояния питания
        .target(
            name: "ClamcupCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Приложение в строке меню
        .executableTarget(
            name: "Clamcup",
            dependencies: ["ClamcupCore"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        // Служба от root: переключает pmset disablesleep
        .executableTarget(
            name: "ClamcupHelper",
            dependencies: ["ClamcupCore"]
        ),
        .testTarget(
            name: "ClamcupCoreTests",
            dependencies: ["ClamcupCore"]
        ),
    ]
)
