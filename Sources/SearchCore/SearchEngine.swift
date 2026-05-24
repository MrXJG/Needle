import Foundation

public struct SearchEngine: Sendable {
    public init() {}

    public func search(
        _ records: [FileRecord],
        query: SearchQuery,
        limit: Int = 200,
        preferredFolderPaths: [String] = []
    ) -> [FileRecord] {
        guard !records.isEmpty else { return [] }
        guard query.invalidRegexPatterns.isEmpty else { return [] }
        let regexes = query.regexPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        guard regexes.count == query.regexPatterns.count else { return [] }
        let wildcardRegexes = query.wildcardPatterns.compactMap {
            try? NSRegularExpression(pattern: wildcardRegexPattern(from: $0), options: [.caseInsensitive])
        }

        let filtered = records.compactMap { record -> (FileRecord, Int)? in
            guard matches(record, query: query, wildcardRegexes: wildcardRegexes, regexes: regexes) else {
                return nil
            }
            return (record, score(record, query: query, preferredFolderPaths: preferredFolderPaths))
        }

        return filtered
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                if lhs.0.openCount != rhs.0.openCount {
                    return lhs.0.openCount > rhs.0.openCount
                }
                if lhs.0.lastOpenedAt != rhs.0.lastOpenedAt {
                    return (lhs.0.lastOpenedAt ?? .distantPast) > (rhs.0.lastOpenedAt ?? .distantPast)
                }
                if lhs.0.modifiedAt != rhs.0.modifiedAt {
                    return lhs.0.modifiedAt > rhs.0.modifiedAt
                }
                return lhs.0.path.localizedStandardCompare(rhs.0.path) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private func matches(
        _ record: FileRecord,
        query: SearchQuery,
        wildcardRegexes: [NSRegularExpression],
        regexes: [NSRegularExpression]
    ) -> Bool {
        switch query.kindFilter {
        case .all:
            break
        case .files where record.kind != .file:
            return false
        case .folders where record.kind != .folder:
            return false
        default:
            break
        }

        if let extensionFilter = query.extensionFilter, record.ext != extensionFilter {
            return false
        }

        guard !query.terms.isEmpty || !query.wildcardPatterns.isEmpty || !query.regexPatterns.isEmpty else {
            return true
        }

        let name = record.name.lowercased()
        let path = record.path.lowercased()
        guard query.terms.allSatisfy({ term in
            name.contains(term) || (query.matchPath && path.contains(term))
        }) else {
            return false
        }

        guard wildcardRegexes.allSatisfy({ regex in
            matchesRegex(regex, in: name) || (query.matchPath && matchesRegex(regex, in: path))
        }) else {
            return false
        }

        return regexes.allSatisfy { regex in
            matchesRegex(regex, in: name) || (query.matchPath && matchesRegex(regex, in: path))
        }
    }

    private func score(_ record: FileRecord, query: SearchQuery, preferredFolderPaths: [String]) -> Int {
        guard !query.terms.isEmpty else {
            return 1
                + min(record.openCount * 5, 100)
                + recentOpenBoost(for: record)
                + preferredFolderBoost(for: record, preferredFolderPaths: preferredFolderPaths)
        }

        let name = record.name.lowercased()
        let path = record.path.lowercased()
        let stem = URL(fileURLWithPath: record.name).deletingPathExtension().lastPathComponent.lowercased()
        var score = 0

        for term in query.terms {
            if name == term {
                score += 1600
            } else if stem == term {
                score += 1350
            } else if stem.hasPrefix(term) {
                score += 1050
            } else if name.hasPrefix(term) {
                score += 900
            } else if name.contains(term) {
                score += 650
            } else if path.contains(term) {
                score += 250
            }
        }

        score -= min(record.path.split(separator: "/").count * 2, 80)
        score += min(record.openCount * 15, 180)
        score += recentOpenBoost(for: record)
        score += preferredFolderBoost(for: record, preferredFolderPaths: preferredFolderPaths)
        return score
    }

    private func recentOpenBoost(for record: FileRecord) -> Int {
        guard let lastOpenedAt = record.lastOpenedAt else { return 0 }
        let age = max(0, Date().timeIntervalSince(lastOpenedAt))
        let day: TimeInterval = 86_400

        if age <= day {
            return 140
        } else if age <= day * 7 {
            return 90
        } else if age <= day * 30 {
            return 45
        }
        return 15
    }

    private func preferredFolderBoost(for record: FileRecord, preferredFolderPaths: [String]) -> Int {
        let normalizedPaths = preferredFolderPaths
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }

        guard !normalizedPaths.isEmpty else { return 0 }

        var bestBoost = 0
        for folderPath in normalizedPaths {
            let root = "/" + folderPath
            guard record.path == root || record.path.hasPrefix(root + "/") else { continue }
            let relativePath = String(record.path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let relativeDepth = relativePath.isEmpty ? 0 : relativePath.split(separator: "/").count
            bestBoost = max(bestBoost, max(20, 80 - min(relativeDepth * 10, 60)))
        }
        return bestBoost
    }

    private func wildcardRegexPattern(from wildcard: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: wildcard)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return "^\(escaped)$"
    }

    private func matchesRegex(_ regex: NSRegularExpression, in text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
