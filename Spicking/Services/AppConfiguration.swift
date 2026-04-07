import Foundation

struct AppConfiguration {
    let workerURL: URL
    let appSharedSecret: String
    let model: String
    let voice: String
}

enum AppConfigurationError: LocalizedError {
    case missingFile
    case invalidValues

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "SpickingConfig.plist is missing from the app bundle."
        case .invalidValues:
            return "Update SpickingConfig.plist with your Worker URL and shared secret before starting a conversation."
        }
    }
}

enum AppConfigurationLoader {
    static func load(bundle: Bundle = .main) throws -> AppConfiguration {
        guard let url = bundle.url(forResource: "SpickingConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            throw AppConfigurationError.missingFile
        }

        let workerURLString = (dictionary["WORKER_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sharedSecret = (dictionary["APP_SHARED_SECRET"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = ((dictionary["MODEL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-realtime"
        let voice = ((dictionary["VOICE"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "marin"

        guard
            let workerURL = URL(string: workerURLString),
            !workerURLString.contains("YOUR_"),
            !sharedSecret.isEmpty,
            !sharedSecret.contains("YOUR_")
        else {
            throw AppConfigurationError.invalidValues
        }

        return AppConfiguration(workerURL: workerURL, appSharedSecret: sharedSecret, model: model, voice: voice)
    }
}
