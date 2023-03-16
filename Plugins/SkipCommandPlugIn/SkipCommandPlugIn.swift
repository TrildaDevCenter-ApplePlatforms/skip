// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

/// Command plugin to invoke our transpilation runner.
///
///     swift package --disable-sandbox --allow-writing-to-package-directory plugin skip [options] <file>+
///
/// - Note: The location of your Command Line Tools must be set in Xcode->Settings->Locations
@main struct SkipCommand: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let runner = try context.tool(named: "skiptool")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: runner.path.string)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
    }
}