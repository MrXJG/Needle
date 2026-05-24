import Foundation

public enum KindFilter: String, Sendable, CaseIterable {
    case all
    case files
    case folders
}

public struct SearchQuery: Equatable, Sendable {
    public var rawText: String
    public var terms: [String]
    public var extensionFilter: String?
    public var wildcardPatterns: [String]
    public var regexPatterns: [String]
    public var invalidRegexPatterns: [String]
    public var kindFilter: KindFilter
    public var matchPath: Bool

    public init(
        rawText: String = "",
        terms: [String] = [],
        extensionFilter: String? = nil,
        wildcardPatterns: [String] = [],
        regexPatterns: [String] = [],
        invalidRegexPatterns: [String] = [],
        kindFilter: KindFilter = .all,
        matchPath: Bool = true
    ) {
        self.rawText = rawText
        self.terms = terms
        self.extensionFilter = extensionFilter
        self.wildcardPatterns = wildcardPatterns
        self.regexPatterns = regexPatterns
        self.invalidRegexPatterns = invalidRegexPatterns
        self.kindFilter = kindFilter
        self.matchPath = matchPath
    }

    public static func parse(
        _ rawText: String,
        kindFilter: KindFilter = .all,
        matchPath: Bool = true
    ) -> SearchQuery {
        var tokens = tokenize(rawText)
        var extensionFilter: String?
        var wildcardPatterns: [String] = []
        var regexPatterns: [String] = []
        var invalidRegexPatterns: [String] = []

        tokens.removeAll { token in
            let lowercasedToken = token.lowercased()

            if lowercasedToken.hasPrefix("ext:"), token.count > 4 {
                extensionFilter = String(token.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                return true
            }

            if isExtensionShortcut(token) {
                extensionFilter = String(token.dropFirst()).lowercased()
                return true
            }

            if lowercasedToken.hasPrefix("re:"), token.count > 3 {
                let pattern = String(token.dropFirst(3))
                if isValidRegex(pattern) {
                    regexPatterns.append(pattern)
                } else {
                    invalidRegexPatterns.append(pattern)
                }
                return true
            }

            if isWildcardPattern(token) {
                wildcardPatterns.append(token.lowercased())
                return true
            }

            return false
        }

        return SearchQuery(
            rawText: rawText,
            terms: tokens.map { $0.lowercased() },
            extensionFilter: extensionFilter,
            wildcardPatterns: wildcardPatterns,
            regexPatterns: regexPatterns,
            invalidRegexPatterns: invalidRegexPatterns,
            kindFilter: kindFilter,
            matchPath: matchPath
        )
    }

    public var validationMessage: String? {
        guard let pattern = invalidRegexPatterns.first else { return nil }
        return "正则表达式无效：\(pattern)"
    }

    private static func isExtensionShortcut(_ token: String) -> Bool {
        guard token.hasPrefix("."), token.count > 1 else { return false }
        return token.dropFirst().allSatisfy { character in
            character.isLetter || character.isNumber
        }
    }

    private static func isWildcardPattern(_ token: String) -> Bool {
        token.contains("*") || token.contains("?")
    }

    private static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false

        for character in text {
            if character == "\"" {
                inQuote.toggle()
                continue
            }

            if character.isWhitespace && !inQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
