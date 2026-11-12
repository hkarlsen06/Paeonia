import SwiftUI

struct RecapShareCard: View {
    let title: String
    let names: String?
    let period: String
    let numbers: [RecapNumber]
    let countedOn: String

    var body: some View {
        PaeoniaShareCardFrame(title: title, subtitle: [names, period].compactMap(\.self).joined(separator: "\n")) {
            RecapNumberList(numbers: numbers, countedOn: countedOn)
                .frame(width: PaeoniaShareRenderer.contentWidth, alignment: .leading)
        }
    }

    /// Both first names, as each partner chose them, or nil when either is missing.
    static func names(_ current: String, _ partner: String) -> String? {
        let first = [current, partner].compactMap { $0.split(separator: " ").first.map(String.init) }
        return first.count == 2 ? first.joined(separator: " & ") : nil
    }
}
