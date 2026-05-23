import ProjectDescription

// MARK: - Project

let project = Project(
    name: "Mimo",
    options: .options(
        automaticSchemesOptions: .disabled,
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [
        .remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .upToNextMajor(from: "2.6.0"))
    ],
    settings: .settings(
        configurations: [
            .debug(name: "Debug", xcconfig: "Configs/Project.xcconfig"),
            .release(name: "Release", xcconfig: "Configs/Project.xcconfig"),
        ]
    ),
    targets: [
        .target(
            name: "Mimo",
            destinations: .macOS,
            product: .app,
            bundleId: "$(PRODUCT_BUNDLE_IDENTIFIER)",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PROJECT_NAME)",
                "CFBundleName": "$(PROJECT_NAME)",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSUIElement": true,
                "NSHumanReadableCopyright": "Created by $(PROJECT_CREATOR)",
                "SUFeedURL": "https://raw.githubusercontent.com/sriinnu/Mimo/main/appcast.xml",
                "SUPublicEDKey": "v7i0OlDkub5CPo4ZouKT8NwLrj9ZQL2MqFAFGXUbl1s=",
                "SUEnableAutomaticChecks": true
            ]),
            sources: ["Sources/Mimo/**"],
            resources: ["Resources/**"],
            dependencies: [
                .package(product: "Sparkle")
            ],
            settings: .settings(
                base: [
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                ]
            )
        ),
    ],
    schemes: [
        .scheme(
            name: "Mimo",
            shared: true,
            buildAction: .buildAction(targets: ["Mimo"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Mimo"
            ),
            archiveAction: .archiveAction(configuration: "Release"),
            profileAction: .profileAction(
                configuration: "Release",
                executable: "Mimo"
            ),
            analyzeAction: .analyzeAction(configuration: "Debug")
        ),
    ]
)
