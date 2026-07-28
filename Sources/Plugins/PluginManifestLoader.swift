import Foundation

enum PluginManifestError: LocalizedError, Equatable {
    case missingManifest
    case invalidManifest(String)
    case incompatibleManifest(Int)
    case incompatibleHostAPI(Int)
    case invalidPluginID
    case invalidEntrypoint
    case missingEntrypoint

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "plugin.json is missing"
        case let .invalidManifest(message):
            return "Invalid plugin.json: \(message)"
        case let .incompatibleManifest(version):
            return "Unsupported manifest version \(version)"
        case let .incompatibleHostAPI(major):
            return "Unsupported Host API major version \(major)"
        case .invalidPluginID:
            return "Plugin id must use reverse-domain style characters"
        case .invalidEntrypoint:
            return "Plugin entrypoint must stay inside its bundle"
        case .missingEntrypoint:
            return "Plugin entrypoint does not exist"
        }
    }
}

struct LoadedPluginManifest {
    let manifest: PluginManifest
    let bundleURL: URL
    let entrypointURL: URL
}

struct PluginManifestLoader {
    static func load(bundleURL: URL, architecture: String = PluginPlatform.architecture) throws -> LoadedPluginManifest {
        let manifestURL = bundleURL.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginManifestError.missingManifest
        }

        let manifest: PluginManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch {
            throw PluginManifestError.invalidManifest(error.localizedDescription)
        }

        guard manifest.manifestVersion == PluginManifest.supportedManifestVersion else {
            throw PluginManifestError.incompatibleManifest(manifest.manifestVersion)
        }
        guard manifest.hostAPI.major == PluginManifest.hostAPI.major else {
            throw PluginManifestError.incompatibleHostAPI(manifest.hostAPI.major)
        }
        let validID = manifest.id.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]+$"#,
            options: .regularExpression
        ) != nil
        guard validID else { throw PluginManifestError.invalidPluginID }

        let relativeEntrypoint = manifest.runtime.architectures?[architecture] ?? manifest.runtime.entrypoint
        guard !relativeEntrypoint.isEmpty,
              !relativeEntrypoint.hasPrefix("/"),
              !relativeEntrypoint.split(separator: "/").contains("..") else {
            throw PluginManifestError.invalidEntrypoint
        }

        let standardizedBundle = bundleURL.standardizedFileURL
        let entrypointURL = bundleURL.appendingPathComponent(relativeEntrypoint).standardizedFileURL
        let bundlePrefix = standardizedBundle.path.hasSuffix("/")
            ? standardizedBundle.path
            : standardizedBundle.path + "/"
        guard entrypointURL.path.hasPrefix(bundlePrefix) else {
            throw PluginManifestError.invalidEntrypoint
        }
        guard FileManager.default.fileExists(atPath: entrypointURL.path) else {
            throw PluginManifestError.missingEntrypoint
        }
        return LoadedPluginManifest(
            manifest: manifest,
            bundleURL: standardizedBundle,
            entrypointURL: entrypointURL
        )
    }
}

enum PluginPlatform {
    static var architecture: String {
        #if arch(arm64)
        return "darwin-arm64"
        #elseif arch(x86_64)
        return "darwin-x86_64"
        #else
        return "darwin-unknown"
        #endif
    }
}

struct PluginDiscovery {
    static var defaultDirectories: [URL] {
        var directories: [URL] = []
        if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            directories.append(
                applicationSupport
                    .appendingPathComponent("RawSend", isDirectory: true)
                    .appendingPathComponent("Plugins", isDirectory: true)
            )
        }
        directories.append(
            URL(fileURLWithPath: "/Library/Application Support/RawSend/Plugins", isDirectory: true)
        )
        return directories
    }

    static func discover(in directories: [URL] = defaultDirectories) -> [URL] {
        var seen: Set<String> = []
        var bundles: [URL] = []
        for directory in directories {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children where child.pathExtension == "rawsendplugin" {
                let path = child.standardizedFileURL.path
                if seen.insert(path).inserted {
                    bundles.append(child)
                }
            }
        }
        return bundles.sorted { $0.path < $1.path }
    }
}
