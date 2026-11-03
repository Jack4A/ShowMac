// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThermalScope",
    platforms: [.macOS(.v11)],
    products: [
        .library(name:"WidgetShared",type:.static,targets:["WidgetShared"]),
        .library(name:"WidgetUI",type:.static,targets:["WidgetUI"]),
        .executable(name: "ThermalScope", targets: ["ThermalScope"]),
        .executable(name: "ThermalScopeHelper", targets: ["ThermalScopeHelper"])
    ],
    targets: [
        .target(name:"WidgetShared",path:"WidgetSupport/Shared"),
        .target(name:"WidgetUI",dependencies:["WidgetShared"],path:"WidgetSupport/UI"),
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("Security")]),
        .target(name: "ThermalCore", dependencies: ["CSMC"]),
        .executableTarget(name: "ThermalScope", dependencies: ["ThermalCore","WidgetShared","WidgetUI"]),
        .executableTarget(name: "ThermalScopeHelper", dependencies: ["ThermalCore", "CSMC"]),
        .executableTarget(name: "ThermalCoreChecks", dependencies: ["ThermalCore", "CSMC","WidgetShared"], path: "Tests/ThermalCoreTests")
    ]
)
