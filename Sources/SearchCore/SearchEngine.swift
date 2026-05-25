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
        guard limit > 0 else { return [] }
        guard query.invalidRegexPatterns.isEmpty else { return [] }
        if query.terms.isEmpty, query.wildcardPatterns.isEmpty, query.regexPatterns.isEmpty {
            return unrankedResults(records, query: query, limit: limit)
        }

        let regexes = query.regexPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        guard regexes.count == query.regexPatterns.count else { return [] }
        let wildcardRegexes = query.wildcardPatterns.compactMap {
            try? NSRegularExpression(pattern: wildcardRegexPattern(from: $0), options: [.caseInsensitive])
        }
        let preferredFolders = normalizedPreferredFolders(preferredFolderPaths)

        var topMatches: [(record: FileRecord, score: Int)] = []
        topMatches.reserveCapacity(min(limit, records.count))

        for record in records {
            if Task.isCancelled {
                return []
            }

            guard matches(record, query: query, wildcardRegexes: wildcardRegexes, regexes: regexes) else {
                continue
            }

            insertTopMatch(
                (record, score(record, query: query, preferredFolders: preferredFolders)),
                into: &topMatches,
                limit: limit
            )
        }

        return topMatches.map(\.record)
    }

    private func unrankedResults(_ records: [FileRecord], query: SearchQuery, limit: Int) -> [FileRecord] {
        guard query.kindFilter != .all || query.extensionFilter != nil else {
            return Array(records.prefix(limit))
        }

        var results: [FileRecord] = []
        results.reserveCapacity(limit)
        for record in records {
            guard kindMatches(record, filter: query.kindFilter) else { continue }
            if let extensionFilter = query.extensionFilter, record.ext != extensionFilter {
                continue
            }
            results.append(record)
            if results.count == limit {
                break
            }
        }
        return results
    }

    private func insertTopMatch(
        _ candidate: (record: FileRecord, score: Int),
        into matches: inout [(record: FileRecord, score: Int)],
        limit: Int
    ) {
        if matches.count == limit, let last = matches.last, !isHigherPriority(candidate, than: last) {
            return
        }

        let insertionIndex = insertionIndex(for: candidate, in: matches)
        matches.insert(candidate, at: insertionIndex)

        if matches.count > limit {
            matches.removeLast()
        }
    }

    private func insertionIndex(
        for candidate: (record: FileRecord, score: Int),
        in matches: [(record: FileRecord, score: Int)]
    ) -> Int {
        var lowerBound = 0
        var upperBound = matches.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if isHigherPriority(candidate, than: matches[middle]) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }

        return lowerBound
    }

    private func isHigherPriority(
        _ lhs: (record: FileRecord, score: Int),
        than rhs: (record: FileRecord, score: Int)
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.record.openCount != rhs.record.openCount {
            return lhs.record.openCount > rhs.record.openCount
        }
        if lhs.record.lastOpenedAt != rhs.record.lastOpenedAt {
            return (lhs.record.lastOpenedAt ?? .distantPast) > (rhs.record.lastOpenedAt ?? .distantPast)
        }
        if lhs.record.modifiedAt != rhs.record.modifiedAt {
            return lhs.record.modifiedAt > rhs.record.modifiedAt
        }
        return lhs.record.path.localizedStandardCompare(rhs.record.path) == .orderedAscending
    }

    private func matches(
        _ record: FileRecord,
        query: SearchQuery,
        wildcardRegexes: [NSRegularExpression],
        regexes: [NSRegularExpression]
    ) -> Bool {
        guard kindMatches(record, filter: query.kindFilter) else { return false }

        if let extensionFilter = query.extensionFilter, record.ext != extensionFilter {
            return false
        }

        guard !query.terms.isEmpty || !query.wildcardPatterns.isEmpty || !query.regexPatterns.isEmpty else {
            return true
        }

        let name = record.name.lowercased()
        let path = query.matchPath ? record.path.lowercased() : ""
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

    private func kindMatches(_ record: FileRecord, filter: KindFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .files:
            return record.kind == .file
        case .folders:
            return record.kind == .folder
        }
    }

    private func score(_ record: FileRecord, query: SearchQuery, preferredFolders: [PreferredFolder]) -> Int {
        guard !query.terms.isEmpty else {
            return 1
                + min(record.openCount * 5, 100)
                + recentOpenBoost(for: record)
                + preferredFolderBoost(for: record, preferredFolders: preferredFolders)
        }

        let name = record.name.lowercased()
        let path = query.matchPath ? record.path.lowercased() : ""
        let stem = lowercasedStem(from: record.name)
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
            } else if query.matchPath && path.contains(term) {
                score += 250
            }
        }

        score -= min(pathComponentCount(record.path) * 2, 80)
        score += min(record.openCount * 15, 180)
        score += recentOpenBoost(for: record)
        score += preferredFolderBoost(for: record, preferredFolders: preferredFolders)
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

    private func normalizedPreferredFolders(_ paths: [String]) -> [PreferredFolder] {
        paths
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
            .map { PreferredFolder(root: "/" + $0) }
    }

    private func preferredFolderBoost(for record: FileRecord, preferredFolders: [PreferredFolder]) -> Int {
        guard !preferredFolders.isEmpty else { return 0 }
        var bestBoost = 0
        for folder in preferredFolders {
            let root = folder.root
            guard record.path == root || record.path.hasPrefix(root + "/") else { continue }
            let relativePath = String(record.path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let relativeDepth = pathComponentCount(relativePath)
            bestBoost = max(bestBoost, max(20, 80 - min(relativeDepth * 10, 60)))
        }
        return bestBoost
    }

    private func pathComponentCount(_ path: String) -> Int {
        guard !path.isEmpty else { return 0 }

        var count = 0
        var isInsideComponent = false
        for character in path {
            if character == "/" {
                isInsideComponent = false
            } else if !isInsideComponent {
                count += 1
                isInsideComponent = true
            }
        }
        return count
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

    private func lowercasedStem(from name: String) -> String {
        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
            return name.lowercased()
        }
        return String(name[..<dotIndex]).lowercased()
    }

    private struct PreferredFolder {
        let root: String
    }
}
