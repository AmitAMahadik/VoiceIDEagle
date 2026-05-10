import Foundation

/// Loads `.env` style files at runtime so secrets are never hardcoded.
///
/// The `.env` file is expected to live in the app bundle's `Resources` group.
/// See README.md for instructions on adding `.env` to the Xcode target as a
/// resource (Build Phases → Copy Bundle Resources).
final class EnvironmentLoader {
    static let shared = EnvironmentLoader()

    private let values: [String: String]

    private init() {
        self.values = EnvironmentLoader.loadAll()
    }

    var picovoiceAccessKey: String? {
        let trimmed = values["PICOVOICE_ACCESS_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = trimmed, !value.isEmpty, value != "your_access_key_here" else {
            return nil
        }
        return value
    }

    func value(for key: String) -> String? {
        values[key]
    }

    // MARK: - Loading

    private static func loadAll() -> [String: String] {
        var merged: [String: String] = [:]

        // Highest priority: process environment (useful for CI / Xcode scheme env vars).
        if let env = ProcessInfo.processInfo.environment["PICOVOICE_ACCESS_KEY"], !env.isEmpty {
            merged["PICOVOICE_ACCESS_KEY"] = env
        }

        // Look for `.env` files in the app bundle. Multiple search names
        // are tried because Xcode sometimes strips the leading dot.
        let candidateNames = [".env", "env", "dotenv"]
        for name in candidateNames {
            if let url = Bundle.main.url(forResource: name, withExtension: nil),
               let contents = try? String(contentsOf: url, encoding: .utf8) {
                for (key, value) in parse(contents) where merged[key] == nil {
                    merged[key] = value
                }
            }
        }

        // Fallback: a developer building locally may drop a `.env` file
        // alongside the working directory.
        let cwd = FileManager.default.currentDirectoryPath
        let cwdEnv = (cwd as NSString).appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: cwdEnv),
           let contents = try? String(contentsOfFile: cwdEnv, encoding: .utf8) {
            for (key, value) in parse(contents) where merged[key] == nil {
                merged[key] = value
            }
        }

        return merged
    }

    private static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)

            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }
}
