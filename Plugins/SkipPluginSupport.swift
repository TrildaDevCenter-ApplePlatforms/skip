// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Affero General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

enum SkipBuildCommand : Equatable {
    /// Initialize a Skip peer target for the selected Swift target(s)
    case `init`
    /// Synchronize the gradle build output links in Packages/Skip
    case sync
}

/// The options to use when running the plugin command.
struct SkipCommandOptions : OptionSet {
    let rawValue: Int

    public static let `default`: Self = [project, scaffold, preflight, transpile, targets, inplace, link]

    /// Generate the project output structure
    public static let project = Self(rawValue: 1 << 0)

    /// Create the scaffold of folders and files for Kt targets.
    public static let scaffold = Self(rawValue: 1 << 1)

    /// Adds the preflight plugin to each selected target
    public static let preflight = Self(rawValue: 1 << 2)

    /// Adds the transpile plugin to each of the created targets
    public static let transpile = Self(rawValue: 1 << 3)

    /// Add the Kt targets to the Package.swift
    public static let targets = Self(rawValue: 1 << 4)

    /// Add the Package.swift modification directly to the file rather than the README.md
    public static let inplace = Self(rawValue: 1 << 5)

    /// Link the Gradle outputs intpo the Packages/Skip folder
    public static let link = Self(rawValue: 1 << 6)
}


/// An extension that is shared between multiple plugin targets.
///
/// This file is included in the plugin source folders as a symbolic links.
/// This works around the limitation that SPM plugins cannot depend on a shared library target,
/// and thus is the only way to share code between plugins.
extension CommandPlugin {

    func performBuildCommand(_ command: SkipBuildCommand, _ options: SkipCommandOptions? = nil, context: PluginContext, arguments: [String]) throws {
        let options = options ?? (command == .`init` ? .default : command == .sync ? .link : [])
        Diagnostics.remark("performing build command with options: \(options)")

        var args = ArgumentExtractor(arguments)
        let targetArgs = args.extractOption(named: "target")
        var targets = try context.package.targets(named: targetArgs)
        // when no targets are specified (e.g., when running the CLI `swift package plugin skip-init`), enable all the targets
        if targets.isEmpty {
            targets = context.package.targets
        }

        //let overwrite = args.extractFlag(named: "overwrite") > 0
        let allTargets = targets
            .compactMap { $0 as? SwiftSourceModuleTarget }

        let sourceTargets = allTargets
            .filter { !$0.name.hasSuffix("Kt") && !$0.name.hasSuffix("KtTests") } // ignore any "Kt" targets

        // the marker comment that will be used to delimit the Skip-edited section of the Package.swift
        let packageAdditionMarker = "// MARK: Skip Kotlin Peer Targets"
        var packageAddition = packageAdditionMarker + "\n\n"

        if options.contains(.project) {
            var contents = """
            ███████╗██╗  ██╗██╗██████╗
            ██╔════╝██║ ██╔╝██║██╔══██╗
            ███████╗█████╔╝ ██║██████╔╝
            ╚════██║██╔═██╗ ██║██╔═══╝
            ███████║██║  ██╗██║██║
            ╚══════╝╚═╝  ╚═╝╚═╝╚═╝

            Welcome to Skip!

            The Skip build plugin will transform your Swift package
            targets and tests into Kotlin and generate Gradle build
            files for each of the targets.


            """

            var scaffoldCommands = ""

            // source target ordering seems to be random
            let allSourceTargets = sourceTargets.sorted { $0.name < $1.name }

            for target in allSourceTargets {
                let targetName = target.name

                func addTargetDependencies() {
                    for targetDep in target.dependencies {
                        switch targetDep {
                        case .target(let target):
                            packageAddition += """
                                .target(name: "\(target.name)Kt"),

                            """
                        case .product(let product):
                            packageAddition += """
                                .product(name: "\(product.name)Kt", package: "\(product.id)"),

                            """
                        @unknown default:
                            break
                        }
                    }
                }


                if target.kind == .test {
                    packageAddition += """
                    package.targets += [
                        .testTarget(name: "\(targetName.dropLast("Tests".count))KtTests", dependencies: [

                    """
                    addTargetDependencies()
                    packageAddition += """
                            .product(name: "SkipUnitKt", package: "skiphub"),
                        ],
                        resources: [.copy("Skip")],
                        plugins: [.plugin(name: "transpile", package: "skip")])
                    ]


                    """
                } else {

                    packageAddition += """

                    package.products += [
                        .library(name: "\(targetName)Kt", targets: ["\(targetName)Kt"])
                    ]

                    package.targets += [
                        .target(name: "\(targetName)Kt", dependencies: [
                            .target(name: "\(targetName)"),

                    """
                    addTargetDependencies()
                    packageAddition += """
                            .product(name: "SkipFoundationKt", package: "skiphub"),
                        ],
                        resources: [.copy("Skip")],
                        plugins: [.plugin(name: "transpile", package: "skip")])
                    ]


                    """
                }


                // add advice on how to create the targets manually
                let dirname = target.directory.removingLastComponent().lastComponent + "/" + target.directory.lastComponent
                scaffoldCommands += """
                mkdir -p \(dirname)Kt/skip/ && touch \(dirname)Kt/skip/skip.yml

                """

                if options.contains(.scaffold) {
                    // create the directory and test case stub
                    let targetNameKt = target.kind == .test ? (target.name.dropLast("Tests".count) + "KtTests") : (target.name + "Kt")
                    let targetDirKt = target.directory.removingLastComponent().appending(subpath: targetNameKt)

                    let targetDirKtSkip = targetDirKt.appending(subpath: "Skip")

                    Diagnostics.remark("creating target folder: \(targetDirKtSkip)")
                    try FileManager.default.createDirectory(atPath: targetDirKtSkip.string, withIntermediateDirectories: true)

                    let skipConfig = targetDirKtSkip.appending(subpath: "/skip.yml")
                    if !FileManager.default.fileExists(atPath: skipConfig.string) {
                        try """
                        # Skip configuration file for \(target.name)

                        """.write(toFile: skipConfig.string, atomically: true, encoding: .utf8)
                    }

                    // create a test case stub
                    if target.kind == .test {
                        let testClass = targetNameKt // class name is same as target name
                        let testSource = targetDirKt.appending(subpath: testClass + ".swift")

                        if !FileManager.default.fileExists(atPath: testSource.string) {
                            try """
                            import SkipUnit

                            /// This test case will run the transpiled tests for the \(target.name) module using the `JUnitTestCase.testProjectGradle()` harness.
                            /// New tests should be added to that module; this file does not need to be modified.
                            class \(testClass): JUnitTestCase {
                            }

                            """.write(toFile: testSource.string, atomically: true, encoding: .utf8)
                        }
                    }

                    if target.kind != .test {
                        let moduleClass = target.name + "ModuleKt"
                        let testSource = targetDirKt.appending(subpath: moduleClass + ".swift")

                        if !FileManager.default.fileExists(atPath: testSource.string) {
                            try """
                            import Foundation

                            /// A link to the \(moduleClass) module
                            public extension Bundle {
                                static let \(moduleClass) = Bundle.module
                            }
                            """.write(toFile: testSource.string, atomically: true, encoding: .utf8)
                        }
                    }

                    // include a sample Kotlin file as an extension point for the user
                    if target.kind != .test {
                        let kotlinSource = targetDirKtSkip.appending(subpath: target.name + "KtSupport.kt")
                        if !FileManager.default.fileExists(atPath: kotlinSource.string) {
                            try """
                            // This is free software: you can redistribute and/or modify it
                            // under the terms of the GNU Lesser General Public License 3.0
                            // as published by the Free Software Foundation https://fsf.org

                            // Kotlin included in this file will be included in the transpiled package for \(target.name)
                            // This can be used to provide support functions for any Kotlin-specific Swift

                            """.write(toFile: kotlinSource.string, atomically: true, encoding: .utf8)
                        }
                    }
                }

            }

            // if we do not create the scaffold directly, insert advice on how to create it manually
            do { // if !options.contains(.scaffold) {
                contents += """

                The new targets can be added by appending the following block to
                the bottom of the project's `Package.swift` file:

                ```
                \(packageAdditionMarker)

                \(packageAddition)

                ```
                """


                contents += """

                The files needed for these targets may need to be created by running
                the following shell commands from the project root folder:

                ```
                \(scaffoldCommands)
                ```

                """
            }

            //let outputPath = outputFolder.appending(subpath: "README.md")
            //Diagnostics.remark("saving to \(outputPath.string)")
            //try contents.write(toFile: outputPath.string, atomically: true, encoding: .utf8)
        }

        let packageDir = context.package.directory
        if options.contains(.inplace) && !packageAddition.isEmpty {
            let packageFile = packageDir.appending(subpath: "Package.swift")
            var encoding: String.Encoding = .utf8
            var packageContents = try String(contentsOfFile: packageFile.string, usedEncoding: &encoding)
            // trim off anything after the skip marker
            packageContents = packageContents.components(separatedBy: packageAdditionMarker).first?.description ?? packageContents

            packageContents += packageAddition
            try packageContents.write(toFile: packageFile.string, atomically: true, encoding: encoding)
            Diagnostics.remark("Updated Package.swift with frameworks")
        }

        /// Returns all the subpaths of the given path
        func subpaths(of path: Path) throws -> [Path] {
            try FileManager.default.contentsOfDirectory(atPath: path.string).map {
                path.appending(subpath: $0)
            }
        }

        if options.contains(.link) {
            let outputFolder = packageDir.appending(subpath: "Packages/Skip")
            try FileManager.default.createDirectory(atPath: outputFolder.string, withIntermediateDirectories: true)

            func isDirectory(_ path: Path) -> Bool {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: path.string, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }
            /// Delete all the symbolic links in a given folder
            func clearLinks(in folder: Path) throws {
                // clear out any the links in the Packages/Skip folder for re-creation
                for subpath in try subpaths(of: folder) {
                    if (try? FileManager.default.destinationOfSymbolicLink(atPath: subpath.string)) != nil {
                        Diagnostics.remark("Clearing link \(subpath.string)")
                        try FileManager.default.removeItem(atPath: subpath.string)
                    }
                }
            }

            // clear links in all the output folders, then clear any empty folders that remain
            try clearLinks(in: outputFolder)
            for subpath in try subpaths(of: outputFolder).filter(isDirectory) {
                try clearLinks(in: subpath)
                if try subpaths(of: subpath).isEmpty {
                    try FileManager.default.removeItem(atPath: subpath.string)
                }
            }

            // In the Skip folder, create links to all the output targets that will contain the transpiled Gradle projects
            // e.g. ~/Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/Hello Skip.output/../skip-template.output
            let ext = context.pluginWorkDirectory.extension ?? "output"
            let packageOutput = context.pluginWorkDirectory
                .removingLastComponent()
                .removingLastComponent()
                .appending(subpath: context.package.id + "." + ext)

            for target in allTargets {
                var targetName = target.name
                let isTestTarget = targetName.hasSuffix("Tests")
                if isTestTarget {
                    targetName.removeLast("Tests".count)
                }
                if targetName.hasSuffix("Kt") { // handle Kt targets by merging them into the base
                    targetName.removeLast("Kt".count)
                }
                let kotlinTargetName = targetName + "Kt" + (isTestTarget ? "Tests" : "")

                let destPath = packageOutput.appending(subpath: kotlinTargetName).appending(subpath: "skip-transpiler")
                let linkBasePath = outputFolder.appending(subpath: kotlinTargetName)

                if !isDirectory(destPath) {
                    Diagnostics.remark("Not creating link from \(linkBasePath) to \(destPath) (missing destination)")
                    continue
                }
                Diagnostics.remark("Creating link from \(linkBasePath) to \(destPath)")
                try FileManager.default.createDirectory(atPath: linkBasePath.string, withIntermediateDirectories: true)

                // we link to only two files in the destination: the folder for the project's source, and the settings.gradle.kts file for external editing
                let settingsPath = "settings.gradle.kts"

                try? FileManager.default.removeItem(atPath: linkBasePath.appending(subpath: settingsPath).string) // clear dest in case it exists
                try FileManager.default.createSymbolicLink(atPath: linkBasePath.appending(subpath: settingsPath).string, withDestinationPath: destPath.appending(subpath: settingsPath).string)

                try? FileManager.default.removeItem(atPath: linkBasePath.appending(subpath: targetName).string) // clear dest in case it exists
                try FileManager.default.createSymbolicLink(atPath: linkBasePath.appending(subpath: targetName).string, withDestinationPath: destPath.appending(subpath: targetName).string)

            }
        }
    }
}