import Foundation

public struct SearchRecord: Sendable {
    public let index: Int
    public let lowercasedName: String
    public let lowercasedDisplayName: String
    public let pathComponentCount: Int
    public let kind: FileKind
    public let ext: String

    public init(record: FileRecord, index: Int = 0) {
        self.index = index
        lowercasedName = record.name.lowercased()
        lowercasedDisplayName = record.displayName.lowercased()
        pathComponentCount = Self.pathComponentCount(record.path)
        kind = record.kind
        ext = record.ext
    }

    private static func lowercasedStem(from name: String) -> String {
        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
            return name.lowercased()
        }
        return String(name[..<dotIndex]).lowercased()
    }

    private static func pathComponentCount(_ path: String) -> Int {
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
}

public struct SearchEngine: Sendable {
    public init() {}

    public func search(
        _ records: [FileRecord],
        query: SearchQuery,
        limit: Int = 200,
        preferredFolderPaths: [String] = []
    ) -> [FileRecord] {
        let cachedRecords = records.enumerated().map { index, record in
            SearchRecord(record: record, index: index)
        }
        return search(
            cachedRecords,
            records: records,
            query: query,
            limit: limit,
            preferredFolderPaths: preferredFolderPaths
        )
    }

    public func search(
        _ cachedRecords: [SearchRecord],
        records: [FileRecord],
        query: SearchQuery,
        limit: Int = 200,
        preferredFolderPaths: [String] = []
    ) -> [FileRecord] {
        guard !cachedRecords.isEmpty, !records.isEmpty else { return [] }
        guard limit > 0 else { return [] }
        guard query.invalidRegexPatterns.isEmpty else { return [] }
        if query.terms.isEmpty, query.wildcardPatterns.isEmpty, query.regexPatterns.isEmpty {
            return unrankedResults(cachedRecords, records: records, query: query, limit: limit)
        }

        let regexes = query.regexPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        guard regexes.count == query.regexPatterns.count else { return [] }
        let wildcardRegexes = query.wildcardPatterns.compactMap {
            try? NSRegularExpression(pattern: wildcardRegexPattern(from: $0), options: [.caseInsensitive])
        }
        let preferredFolders = normalizedPreferredFolders(preferredFolderPaths)

        var topMatches: [(record: SearchRecord, score: Int)] = []
        topMatches.reserveCapacity(min(limit, cachedRecords.count))

        for record in cachedRecords {
            if Task.isCancelled {
                return []
            }

            guard matches(record, query: query, wildcardRegexes: wildcardRegexes, regexes: regexes, includePath: false, records: records) else {
                continue
            }

            insertTopMatch(
                (record, score(record, query: query, preferredFolders: preferredFolders, records: records)),
                into: &topMatches,
                limit: limit,
                records: records
            )
        }

        if query.matchPath, topMatches.count < limit || queryRequiresPathScan(query) {
            for record in cachedRecords {
                if Task.isCancelled {
                    return []
                }
                guard matches(record, query: query, wildcardRegexes: wildcardRegexes, regexes: regexes, includePath: true, records: records) else {
                    continue
                }
                guard !matches(record, query: query, wildcardRegexes: wildcardRegexes, regexes: regexes, includePath: false, records: records) else {
                    continue
                }
                insertTopMatch(
                    (record, score(record, query: query, preferredFolders: preferredFolders, records: records)),
                    into: &topMatches,
                    limit: limit,
                    records: records
                )
            }
        }

        return topMatches.map { records[$0.record.index] }
    }

    private func unrankedResults(_ cachedRecords: [SearchRecord], records: [FileRecord], query: SearchQuery, limit: Int) -> [FileRecord] {
        guard query.kindFilter != .all || query.extensionFilter != nil else {
            return Array(records.prefix(limit))
        }

        var results: [FileRecord] = []
        results.reserveCapacity(limit)
        for record in cachedRecords {
            guard kindMatches(record, filter: query.kindFilter) else { continue }
            if let extensionFilter = query.extensionFilter, record.ext != extensionFilter {
                continue
            }
            results.append(records[record.index])
            if results.count == limit {
                break
            }
        }
        return results
    }

    private func insertTopMatch(
        _ candidate: (record: SearchRecord, score: Int),
        into matches: inout [(record: SearchRecord, score: Int)],
        limit: Int,
        records: [FileRecord]
    ) {
        if matches.count == limit, let last = matches.last, !isHigherPriority(candidate, than: last, records: records) {
            return
        }

        let insertionIndex = insertionIndex(for: candidate, in: matches, records: records)
        matches.insert(candidate, at: insertionIndex)

        if matches.count > limit {
            matches.removeLast()
        }
    }

    private func insertionIndex(
        for candidate: (record: SearchRecord, score: Int),
        in matches: [(record: SearchRecord, score: Int)],
        records: [FileRecord]
    ) -> Int {
        var lowerBound = 0
        var upperBound = matches.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if isHigherPriority(candidate, than: matches[middle], records: records) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }

        return lowerBound
    }

    private func isHigherPriority(
        _ lhs: (record: SearchRecord, score: Int),
        than rhs: (record: SearchRecord, score: Int),
        records: [FileRecord]
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        let left = records[lhs.record.index]
        let right = records[rhs.record.index]
        if left.openCount != right.openCount {
            return left.openCount > right.openCount
        }
        if left.lastOpenedAt != right.lastOpenedAt {
            return (left.lastOpenedAt ?? .distantPast) > (right.lastOpenedAt ?? .distantPast)
        }
        if left.modifiedAt != right.modifiedAt {
            return left.modifiedAt > right.modifiedAt
        }
        return left.path.localizedStandardCompare(right.path) == .orderedAscending
    }

    private func matches(
        _ record: SearchRecord,
        query: SearchQuery,
        wildcardRegexes: [NSRegularExpression],
        regexes: [NSRegularExpression],
        includePath: Bool,
        records: [FileRecord]
    ) -> Bool {
        guard kindMatches(record, filter: query.kindFilter) else { return false }

        if let extensionFilter = query.extensionFilter, record.ext != extensionFilter {
            return false
        }

        guard !query.terms.isEmpty || !query.wildcardPatterns.isEmpty || !query.regexPatterns.isEmpty else {
            return true
        }

        let name = record.lowercasedName
        let displayName = record.lowercasedDisplayName
        let file = records[record.index]
        guard query.terms.allSatisfy({ term in
            name.contains(term)
                || displayName.contains(term)
                || (includePath && pathContains(file.path, term: term))
        }) else {
            return false
        }

        guard wildcardRegexes.allSatisfy({ regex in
            matchesRegex(regex, in: name)
                || matchesRegex(regex, in: displayName)
                || (includePath && matchesRegex(regex, in: file.path))
        }) else {
            return false
        }

        return regexes.allSatisfy { regex in
            matchesRegex(regex, in: name)
                || matchesRegex(regex, in: displayName)
                || (includePath && matchesRegex(regex, in: file.path))
        }
    }

    private func kindMatches(_ record: SearchRecord, filter: KindFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .files:
            return record.kind == .file
        case .folders:
            return record.kind == .folder
        }
    }

    private func score(_ record: SearchRecord, query: SearchQuery, preferredFolders: [PreferredFolder], records: [FileRecord]) -> Int {
        let file = records[record.index]
        guard !query.terms.isEmpty else {
            return 1
                + min(file.openCount * 5, 100)
                + recentOpenBoost(for: file)
                + preferredFolderBoost(for: record, preferredFolders: preferredFolders, records: records)
        }

        let name = record.lowercasedName
        let displayName = record.lowercasedDisplayName
        let stem = lowercasedStem(from: file.name)
        let displayStem = lowercasedStem(from: file.displayName)
        var score = 0

        for term in query.terms {
            if name == term {
                score += 1600
            } else if displayName == term {
                score += 1550
            } else if stem == term {
                score += 1350
            } else if displayStem == term {
                score += 1325
            } else if stem.hasPrefix(term) {
                score += 1050
            } else if displayStem.hasPrefix(term) {
                score += 1025
            } else if name.hasPrefix(term) {
                score += 900
            } else if displayName.hasPrefix(term) {
                score += 875
            } else if name.contains(term) {
                score += 650
            } else if displayName.contains(term) {
                score += 625
            } else if query.matchPath && pathContains(file.path, term: term) {
                score += 250
            }
        }

        score -= min(record.pathComponentCount * 2, 80)
        score += min(file.openCount * 15, 180)
        score += recentOpenBoost(for: file)
        score += preferredFolderBoost(for: record, preferredFolders: preferredFolders, records: records)
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

    private func queryRequiresPathScan(_ query: SearchQuery) -> Bool {
        !query.wildcardPatterns.isEmpty
            || !query.regexPatterns.isEmpty
            || query.terms.contains(where: { term in
                term.contains("/")
                    || term.contains("~")
                    || term.contains(".")
                    || term.count >= 12
            })
    }

    private func pathContains(_ path: String, term: String) -> Bool {
        path.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func preferredFolderBoost(for record: SearchRecord, preferredFolders: [PreferredFolder], records: [FileRecord]) -> Int {
        guard !preferredFolders.isEmpty else { return 0 }
        let path = records[record.index].path
        var bestBoost = 0
        for folder in preferredFolders {
            let root = folder.root
            guard path == root || path.hasPrefix(root + "/") else { continue }
            let relativePath = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
