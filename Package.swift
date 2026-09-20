// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ControleTVMacOS",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ControleTVMacOS", targets: ["ControleTVMacOS"])
    ],
    dependencies: [
        .package(path: "Vendor/macOS-TVRemote/Vendor/AndroidTVRemoteControl")
    ],
    targets: [
        .executableTarget(
            name: "ControleTVMacOS",
            dependencies: ["AndroidTVRemoteControl"],
            path: "Sources/ControleTVMacOS"
        )
    ]
)
