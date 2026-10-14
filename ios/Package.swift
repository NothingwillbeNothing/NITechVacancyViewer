// swift-tools-version: 5.9
import PackageDescription

// The Foundation-only domain model can also be tested without an iOS SDK.
let package = Package(
    name: "NITechVacancyCore",
    products: [.library(name: "NITechVacancyCore", targets: ["NITechVacancyCore"])],
    targets: [
        .target(name: "NITechVacancyCore", path: "NITechVacancyViewer/Core"),
        .testTarget(name: "NITechVacancyCoreTests", dependencies: ["NITechVacancyCore"], path: "NITechVacancyViewerTests")
    ]
)
