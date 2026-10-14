import Foundation

enum APIKeyFile {
    static func read(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 16_385) ?? Data()
        guard data.count <= 16_384, let text = String(data: data, encoding: .utf8) else { throw InvalidKey() }
        return try validated(text)
    }

    static func validated(_ text: String) throws -> String {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 16_384,
              !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw InvalidKey()
        }
        return key
    }

    struct InvalidKey: LocalizedError {
        var errorDescription: String? { "Use a UTF-8 text file containing only the API key on one line (up to 16 KiB)." }
    }
}
