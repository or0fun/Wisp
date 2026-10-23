import Foundation

enum InputIntent: Equatable {
    case link(URL), question

    static func detect(_ input: String) -> Self? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains(where: \.isWhitespace), text.rangeOfCharacter(from: .controlCharacters) == nil {
            let candidate = text.lowercased().hasPrefix("www.") ? "https://" + text : text
            if let parts = URLComponents(string: candidate),
               ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
               let host = parts.host, !host.isEmpty, let url = parts.url {
                return .link(url)
            }
        }
        if let last = text.last, last == "?" || last == "？",
           text.dropLast().contains(where: { !$0.isWhitespace && $0 != "?" && $0 != "？" }) { return .question }
        return nil
    }
}
