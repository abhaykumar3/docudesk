// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DocuDesk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DocuDesk", targets: ["DocuDesk"]),
    ],
    targets: [
        .target(
            name: "DocuDeskCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "DocuDesk",
            dependencies: ["DocuDeskCore"]
        ),
        // Command Line Tools ship without XCTest/Testing, so checks run as a plain executable.
        // Seeds a workspace with sample data: swift run DocuDeskDemo <folder>
        .executableTarget(
            name: "DocuDeskDemo",
            dependencies: ["DocuDeskCore"],
            path: "Demo"
        ),
        .executableTarget(
            name: "DocuDeskChecks",
            dependencies: ["DocuDeskCore"],
            path: "Checks"
        ),
    ]
)
