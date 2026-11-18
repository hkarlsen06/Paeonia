import Foundation

/// One open source package Paeonia uses and its licence, from the bundled
/// `PackageLicences.txt`. `ios/Scripts/collect-package-licences.py` writes that
/// file and describes its format.
nonisolated struct PackageLicence: Identifiable, Equatable, Sendable {
    /// The package's name and version, such as "Kingfisher 8.16.0".
    let name: String
    /// Where the package comes from.
    let source: String
    let text: String

    var id: String { name }

    /// The bundled packages, or none when the file is missing.
    static func bundled(in bundle: Bundle = .main) -> [PackageLicence] {
        guard let url = bundle.url(forResource: "PackageLicences", withExtension: "txt"),
              let file = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }
        return parse(file)
    }

    /// A form feed on its own line separates the packages. Each starts with its
    /// name, then its source, then a blank line and the licence.
    static func parse(_ file: String) -> [PackageLicence] {
        file.components(separatedBy: "\n\u{0C}\n").compactMap { entry in
            let parts = entry.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else {
                return nil
            }
            return PackageLicence(
                name: String(parts[0]),
                source: String(parts[1]),
                text: parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
