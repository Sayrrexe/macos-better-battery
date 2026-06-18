// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Battary",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Battary", targets: ["Battary"])
    ],
    targets: [
        .executableTarget(
            name: "Battary",
            resources: [
                .copy("Resources/Mascots")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
    ]
)
