import Foundation

public enum TranscriptionOutputPreset: String, CaseIterable, Codable, Sendable {
    case verbatim
    case casualMessage
    case polishedMessage
    case emailDraft
    case meetingNotes

    public var displayName: String {
        switch self {
        case .verbatim:
            return "Verbatim"
        case .casualMessage:
            return "Casual Message"
        case .polishedMessage:
            return "Polished Message"
        case .emailDraft:
            return "Email Draft"
        case .meetingNotes:
            return "Meeting Notes"
        }
    }

    public var quickActionTitle: String {
        switch self {
        case .verbatim:
            return "Polish"
        case .casualMessage:
            return "Casual"
        case .polishedMessage:
            return "Polish"
        case .emailDraft:
            return "Email"
        case .meetingNotes:
            return "Notes"
        }
    }
}

public struct TranscriptionGlossaryItem: Codable, Equatable, Sendable {
    public var phrase: String
    public var replacement: String
    public var aliases: [String]

    public init(
        phrase: String,
        replacement: String,
        aliases: [String] = []
    ) {
        self.phrase = phrase
        self.replacement = replacement
        self.aliases = aliases
    }
}

public struct TranscriptionGlossaryAliasSuggestionPreview: Equatable, Sendable {
    public let visibleAliases: [String]
    public let overflowCount: Int

    public init(visibleAliases: [String], overflowCount: Int) {
        self.visibleAliases = visibleAliases
        self.overflowCount = overflowCount
    }

    public var isEmpty: Bool {
        visibleAliases.isEmpty && overflowCount == 0
    }
}

public enum TranscriptionGlossarySearchMatchSource: String, Codable, Equatable, Sendable {
    case phrase
    case replacement
    case explicitAlias
    case suggestedAlias

    public var displayName: String {
        switch self {
        case .phrase:
            return "Phrase"
        case .replacement:
            return "Replacement"
        case .explicitAlias:
            return "Alias"
        case .suggestedAlias:
            return "Suggested"
        }
    }
}

public struct TranscriptionGlossarySearchHighlight: Codable, Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public struct TranscriptionGlossarySearchMatch: Codable, Equatable, Sendable {
    public let source: TranscriptionGlossarySearchMatchSource
    public let value: String
    public let highlight: TranscriptionGlossarySearchHighlight?

    public init(
        source: TranscriptionGlossarySearchMatchSource,
        value: String,
        highlight: TranscriptionGlossarySearchHighlight? = nil
    ) {
        self.source = source
        self.value = value
        self.highlight = highlight
    }
}

public extension TranscriptionGlossaryItem {
    static let compactQualifierLabels = ["pro", "max", "mini", "ultra", "air"]

    var normalizedForPersistence: TranscriptionGlossaryItem? {
        let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = trimmedReplacement.isEmpty ? normalizedPhrase : trimmedReplacement

        guard !normalizedPhrase.isEmpty, !normalizedReplacement.isEmpty else {
            return nil
        }

        var seenAliases = Set<String>()
        let normalizedAliases = aliases.compactMap { alias -> String? in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let dedupeKey = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seenAliases.insert(dedupeKey).inserted else {
                return nil
            }

            return trimmed
        }

        return TranscriptionGlossaryItem(
            phrase: normalizedPhrase,
            replacement: normalizedReplacement,
            aliases: normalizedAliases
        )
    }

    var effectiveAliases: [String] {
        var seen = Set<String>()
        var collected: [String] = []

        for candidate in aliases + inferredAliases {
            let key = Self.aliasDedupeKey(candidate)
            guard seen.insert(key).inserted else {
                continue
            }
            collected.append(candidate)
        }

        return collected
    }

    var inferredAliases: [String] {
        let seeds = [phrase, replacement]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let reservedKeys = Set(
            ([phrase, replacement] + aliases)
                .map { Self.aliasDedupeKey($0) }
        )

        var seen = reservedKeys
        var inferred: [String] = []

        for seed in seeds {
            for candidate in Self.inferredAliasCandidates(from: seed) {
                let key = Self.aliasDedupeKey(candidate)
                guard seen.insert(key).inserted else {
                    continue
                }
                inferred.append(candidate)
            }
        }

        return inferred
    }

    func aliasSuggestionPreview(limit: Int = 3) -> TranscriptionGlossaryAliasSuggestionPreview {
        let safeLimit = max(0, limit)
        let suggestions = inferredAliases
        let visibleAliases = Array(suggestions.prefix(safeLimit))
        let overflowCount = max(0, suggestions.count - visibleAliases.count)

        return TranscriptionGlossaryAliasSuggestionPreview(
            visibleAliases: visibleAliases,
            overflowCount: overflowCount
        )
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        let normalizedQuery = Self.searchNormalizedValue(query)
        guard !normalizedQuery.isEmpty else {
            return true
        }
        return !searchMatches(for: query).isEmpty
    }

    func searchMatches(for query: String) -> [TranscriptionGlossarySearchMatch] {
        let normalizedQuery = Self.searchNormalizedValue(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        var seen = Set<String>()
        let candidates =
            [
                TranscriptionGlossarySearchMatch(source: .phrase, value: phrase),
                TranscriptionGlossarySearchMatch(source: .replacement, value: replacement)
            ]
            + aliases.map {
                TranscriptionGlossarySearchMatch(source: .explicitAlias, value: $0)
            }
            + inferredAliases.map {
                TranscriptionGlossarySearchMatch(source: .suggestedAlias, value: $0)
            }

        return candidates.compactMap { candidate in
            guard let highlight = Self.searchMatchHighlight(in: candidate.value, query: query) else {
                return nil
            }

            let dedupeKey = "\(candidate.source.rawValue)|\(Self.aliasDedupeKey(candidate.value))"
            guard seen.insert(dedupeKey).inserted else {
                return nil
            }

            return TranscriptionGlossarySearchMatch(
                source: candidate.source,
                value: candidate.value,
                highlight: highlight
            )
        }
    }

    static func inferredAliasCandidates(from seed: String) -> [String] {
        var inferred: [String] = []
        var seen = Set<String>()

        func append(_ candidates: [String]) {
            for candidate in candidates {
                let key = aliasDedupeKey(candidate)
                guard seen.insert(key).inserted else {
                    continue
                }
                inferred.append(candidate)
            }
        }

        if let fullDottedTokens = fullDottedModelTokens(from: seed) {
            append(separatorVariants(from: fullDottedTokens, separators: ["", " ", "-"]))
            return inferred
        }

        if let dottedTokens = dottedModelTokens(from: seed) {
            append(separatorVariants(from: dottedTokens, separators: ["", " ", "-"]))
            return inferred
        }

        if let tokens = aliasTokens(from: seed), tokens.count > 1 {
            append(separatorVariants(from: tokens))
        }

        append(acronymAliasCandidates(from: seed))
        return inferred
    }

    fileprivate static func acronymAliasCandidates(from seed: String) -> [String] {
        guard let rawSegments = rawAliasSegments(from: seed), !rawSegments.isEmpty else {
            return []
        }

        let segmentVariants = rawSegments.enumerated().map { index, segment in
            inferredAcronymSegmentVariants(
                for: segment,
                index: index,
                totalSegments: rawSegments.count
            )
        }

        guard segmentVariants.contains(where: { $0.count > 1 }) else {
            return []
        }

        var aliases: [String] = []
        var seen = Set<String>()

        func build(_ index: Int, current: [String], changed: Bool) {
            guard index < segmentVariants.count else {
                guard changed else {
                    return
                }

                let candidate = current.joined(separator: " ")
                let key = aliasDedupeKey(candidate)
                guard seen.insert(key).inserted else {
                    return
                }

                aliases.append(candidate)
                return
            }

            let variants = segmentVariants[index]
            guard let base = variants.first else {
                return
            }

            for variant in variants {
                build(
                    index + 1,
                    current: current + [variant],
                    changed: changed || variant != base
                )
            }
        }

        build(0, current: [], changed: false)
        return aliases
    }

    private static func inferredAcronymSegmentVariants(
        for segment: String,
        index: Int,
        totalSegments: Int
    ) -> [String] {
        let normalizedBase = segment.lowercased()
        guard shouldInferAcronymPhonetics(for: segment, index: index, totalSegments: totalSegments) else {
            return [normalizedBase]
        }

        let letters = Array(segment.uppercased())
        let englishLetterTokens = letters.map { String($0).lowercased() }

        let koreanLetterNames = letters.compactMap { koreanAcronymLetterNames[$0] }
        let japaneseLetterNames = letters.compactMap { japaneseAcronymLetterNames[$0] }

        var variants = [normalizedBase] + separatorVariants(from: englishLetterTokens)
        if koreanLetterNames.count == letters.count {
            variants.append(koreanLetterNames.joined())
            variants.append(koreanLetterNames.joined(separator: " "))
        }
        if japaneseLetterNames.count == letters.count {
            variants.append(japaneseLetterNames.joined())
        }

        var seen = Set<String>()
        return variants.compactMap { variant in
            let key = aliasDedupeKey(variant)
            guard seen.insert(key).inserted else {
                return nil
            }
            return variant
        }
    }

    private static func shouldInferAcronymPhonetics(
        for segment: String,
        index: Int,
        totalSegments: Int
    ) -> Bool {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3,
              trimmed.unicodeScalars.allSatisfy(CharacterSet.letters.contains(_:)),
              trimmed == trimmed.uppercased()
        else {
            return false
        }

        if totalSegments == 1 {
            return true
        }

        return index > 0
    }

    private static func rawAliasSegments(from seed: String) -> [String]? {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isASCIIAliasSeed(trimmed) else {
            return nil
        }

        let separated = trimmed.replacingOccurrences(
            of: #"[\s._-]+"#,
            with: " ",
            options: .regularExpression
        )
        let rawSegments = separated.split(separator: " ").map(String.init)
        guard !rawSegments.isEmpty else {
            return nil
        }

        let tokens = rawSegments.flatMap(camelCaseTokens)
            .filter { !$0.isEmpty }

        return tokens.isEmpty ? nil : tokens
    }

    private static func aliasTokens(from seed: String) -> [String]? {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isASCIIAliasSeed(trimmed) else {
            return nil
        }

        if let compactModelTokens = compactModelTokens(from: trimmed) {
            return compactModelTokens
        }

        let separated = trimmed.replacingOccurrences(
            of: #"[\s._-]+"#,
            with: " ",
            options: .regularExpression
        )
        let rawSegments = separated.split(separator: " ").map(String.init)
        guard !rawSegments.isEmpty else {
            return nil
        }

        let tokens = rawSegments.flatMap(camelCaseTokens)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }

        guard tokens.count > 1 else {
            return nil
        }

        return tokens
    }

    static func compactModelTokens(from seed: String) -> [String]? {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isASCIIAliasSeed(trimmed) else {
            return nil
        }

        let separated = trimmed.replacingOccurrences(
            of: #"[\s._-]+"#,
            with: " ",
            options: .regularExpression
        )
        let rawSegments = separated.split(separator: " ").map(String.init)
        guard let tokens = compactModelTokens(fromRawSegments: rawSegments), tokens.count > 1 else {
            return nil
        }

        return tokens.map { $0.lowercased() }
    }

    static func fullDottedModelTokens(from seed: String) -> [String]? {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isASCIIAliasSeed(trimmed) else {
            return nil
        }

        let separated = trimmed.replacingOccurrences(
            of: #"[\s-]+"#,
            with: " ",
            options: .regularExpression
        )
        let rawSegments = separated.split(separator: " ").map(String.init)
        guard let tokens = fullDottedModelTokens(fromRawSegments: rawSegments), tokens.count == 3 else {
            return nil
        }

        return tokens.map { $0.lowercased() }
    }

    static func dottedModelTokens(from seed: String) -> [String]? {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isASCIIAliasSeed(trimmed) else {
            return nil
        }

        let separated = trimmed.replacingOccurrences(
            of: #"[\s-]+"#,
            with: " ",
            options: .regularExpression
        )
        let rawSegments = separated.split(separator: " ").map(String.init)
        guard let tokens = dottedModelTokens(fromRawSegments: rawSegments), tokens.count == 2 else {
            return nil
        }

        return tokens.map { $0.lowercased() }
    }

    private static func camelCaseTokens(from segment: String) -> [String] {
        let nsRange = NSRange(segment.startIndex..., in: segment)
        let pattern = #"[A-Z]+(?=[A-Z][a-z]|\b)|[A-Z]?[a-z]+|[0-9]+|[A-Z]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [segment]
        }

        let matches = regex.matches(in: segment, range: nsRange).compactMap { match -> String? in
            guard let range = Range(match.range, in: segment) else {
                return nil
            }
            return String(segment[range])
        }

        return matches.isEmpty ? [segment] : matches
    }

    private static func isASCIIAliasSeed(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (
                CharacterSet.alphanumerics.contains(scalar)
                    || CharacterSet.whitespaces.contains(scalar)
                    || "._-".unicodeScalars.contains(scalar)
            )
        }
    }

    private static func aliasDedupeKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func searchNormalizedValue(_ value: String) -> String {
        aliasDedupeKey(value)
    }

    private static func separatorVariants(from tokens: [String]) -> [String] {
        separatorVariants(from: tokens, separators: [" ", "-", ".", "_", ""])
    }

    private static func separatorVariants(
        from tokens: [String],
        separators: [String]
    ) -> [String] {
        var seen = Set<String>()
        return separators.compactMap { separator in
            let candidate = tokens.joined(separator: separator)
            guard !candidate.isEmpty else {
                return nil
            }
            let key = aliasDedupeKey(candidate)
            guard seen.insert(key).inserted else {
                return nil
            }
            return candidate
        }
    }

    private static let koreanAcronymLetterNames: [Character: String] = [
        "A": "에이", "B": "비", "C": "씨", "D": "디", "E": "이", "F": "에프",
        "G": "지", "H": "에이치", "I": "아이", "J": "제이", "K": "케이", "L": "엘",
        "M": "엠", "N": "엔", "O": "오", "P": "피", "Q": "큐", "R": "알",
        "S": "에스", "T": "티", "U": "유", "V": "브이", "W": "더블유", "X": "엑스",
        "Y": "와이", "Z": "제트"
    ]

    private static let japaneseAcronymLetterNames: [Character: String] = [
        "A": "エー", "B": "ビー", "C": "シー", "D": "ディー", "E": "イー", "F": "エフ",
        "G": "ジー", "H": "エイチ", "I": "アイ", "J": "ジェー", "K": "ケー", "L": "エル",
        "M": "エム", "N": "エヌ", "O": "オー", "P": "ピー", "Q": "キュー", "R": "アール",
        "S": "エス", "T": "ティー", "U": "ユー", "V": "ブイ", "W": "ダブリュー", "X": "エックス",
        "Y": "ワイ", "Z": "ゼット"
    ]

    private static func searchMatchHighlight(
        in value: String,
        query: String
    ) -> TranscriptionGlossarySearchHighlight? {
        let normalizedQuery = searchNormalizedValue(query)
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        if let fullDottedTokens = fullDottedModelTokens(from: value) {
            let matchesExactVariant = separatorVariants(
                from: fullDottedTokens,
                separators: ["", " ", "-"]
            )
            .contains { searchNormalizedValue($0) == normalizedQuery }
            guard matchesExactVariant else {
                return nil
            }

            return searchHighlight(in: value, query: query)
                ?? TranscriptionGlossarySearchHighlight(
                    location: 0,
                    length: value.count
                )
        }

        if let dottedTokens = dottedModelTokens(from: value) {
            let matchesExactVariant = separatorVariants(
                from: dottedTokens,
                separators: ["", " ", "-"]
            )
            .contains { searchNormalizedValue($0) == normalizedQuery }
            guard matchesExactVariant else {
                return nil
            }

            return searchHighlight(in: value, query: query)
                ?? TranscriptionGlossarySearchHighlight(
                    location: 0,
                    length: value.count
                )
        }

        if let compactTokens = compactModelTokens(from: value) {
            let matchesExactVariant = separatorVariants(from: compactTokens)
                .contains { searchNormalizedValue($0) == normalizedQuery }
            guard matchesExactVariant else {
                return nil
            }

            return searchHighlight(in: value, query: query)
                ?? TranscriptionGlossarySearchHighlight(
                    location: 0,
                    length: value.count
                )
        }

        guard searchNormalizedValue(value).contains(normalizedQuery) else {
            return nil
        }

        return searchHighlight(in: value, query: query)
    }

    private static func searchHighlight(
        in value: String,
        query: String
    ) -> TranscriptionGlossarySearchHighlight? {
        guard let range = value.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }

        let location = value.distance(from: value.startIndex, to: range.lowerBound)
        let length = value.distance(from: range.lowerBound, to: range.upperBound)
        return TranscriptionGlossarySearchHighlight(location: location, length: length)
    }

    private static func compactModelTokens(fromRawSegments segments: [String]) -> [String]? {
        switch segments.count {
        case 1:
            let segment = segments[0]
            if let match = regexMatch(
                pattern: #"^([A-Za-z]+)([0-9]+[a-z]{1,2})$"#,
                in: segment
            ) {
                return [match[0], match[1]]
            }

            if let match = regexMatch(
                pattern: compactQualifiedModelPattern,
                in: segment
            ) {
                return [match[0], match[1]]
            }

            return nil
        case 2:
            let first = segments[0]
            let second = segments[1]

            if regexMatches(#"^[A-Za-z]+$"#, value: first),
               regexMatches(#"^[0-9]+[a-z]{1,2}$"#, value: second)
            {
                return [first, second]
            }

            if regexMatches(#"^[A-Za-z]+[0-9]+$"#, value: first),
               regexMatches(compactQualifierTokenPattern, value: second)
            {
                return [first, second]
            }

            return nil
        default:
            return nil
        }
    }

    private static var compactQualifiedModelPattern: String {
        #"^([A-Za-z]+[0-9]+)(\#(compactQualifierAlternation))$"#
    }

    private static var compactQualifierTokenPattern: String {
        #"^(\#(compactQualifierAlternation))$"#
    }

    private static var compactQualifierAlternation: String {
        "(?i:" + compactQualifierLabels.joined(separator: "|") + ")"
    }

    private static func fullDottedModelTokens(fromRawSegments segments: [String]) -> [String]? {
        switch segments.count {
        case 1:
            let segment = segments[0]
            if let match = regexMatch(
                pattern: #"^([A-Za-z]+)([0-9]+\.[0-9]+)([A-Za-z]+)$"#,
                in: segment
            ) {
                return [match[0], match[1], match[2]]
            }

            return nil
        case 2:
            let first = segments[0]
            let second = segments[1]

            if let leadingTokens = dottedModelTokens(fromRawSegments: [first]),
               regexMatches(#"^[A-Za-z]+$"#, value: second)
            {
                return [leadingTokens[0], leadingTokens[1], second]
            }

            if regexMatches(#"^[A-Za-z]+$"#, value: first),
               let trailingTokens = regexMatch(
                pattern: #"^([0-9]+\.[0-9]+)([A-Za-z]+)$"#,
                in: second
               )
            {
                return [first, trailingTokens[0], trailingTokens[1]]
            }

            return nil
        case 3:
            let first = segments[0]
            let second = segments[1]
            let third = segments[2]

            if regexMatches(#"^[A-Za-z]+$"#, value: first),
               regexMatches(#"^[0-9]+\.[0-9]+$"#, value: second),
               regexMatches(#"^[A-Za-z]+$"#, value: third)
            {
                return [first, second, third]
            }

            return nil
        default:
            return nil
        }
    }

    private static func dottedModelTokens(fromRawSegments segments: [String]) -> [String]? {
        switch segments.count {
        case 1:
            let segment = segments[0]
            if let match = regexMatch(
                pattern: #"^([A-Za-z]+)([0-9]+\.[0-9]+)$"#,
                in: segment
            ) {
                return [match[0], match[1]]
            }

            return nil
        case 2:
            let first = segments[0]
            let second = segments[1]

            if regexMatches(#"^[A-Za-z]+$"#, value: first),
               regexMatches(#"^[0-9]+\.[0-9]+$"#, value: second)
            {
                return [first, second]
            }

            return nil
        default:
            return nil
        }
    }

    private static func regexMatches(_ pattern: String, value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private static func regexMatch(pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let matchRange = Range(match.range(at: index), in: value) else {
                return nil
            }
            return String(value[matchRange])
        }
    }
}

public extension Array where Element == TranscriptionGlossaryItem {
    var normalizedForPersistence: [TranscriptionGlossaryItem] {
        compactMap(\.normalizedForPersistence)
    }
}

public struct TranscriptionCorrectionRule: Codable, Equatable, Sendable {
    public var source: String
    public var replacement: String

    public init(source: String, replacement: String) {
        self.source = source
        self.replacement = replacement
    }
}

public enum TranscriptionCorrectionSearchMatchSource: String, Codable, Equatable, Sendable {
    case source
    case replacement

    public var displayName: String {
        switch self {
        case .source:
            return "Heard"
        case .replacement:
            return "Replacement"
        }
    }
}

public struct TranscriptionCorrectionSearchHighlight: Codable, Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public struct TranscriptionCorrectionSearchMatch: Codable, Equatable, Sendable {
    public let source: TranscriptionCorrectionSearchMatchSource
    public let value: String
    public let highlight: TranscriptionCorrectionSearchHighlight?

    public init(
        source: TranscriptionCorrectionSearchMatchSource,
        value: String,
        highlight: TranscriptionCorrectionSearchHighlight? = nil
    ) {
        self.source = source
        self.value = value
        self.highlight = highlight
    }
}

public extension TranscriptionCorrectionRule {
    var normalizedForPersistence: TranscriptionCorrectionRule? {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSource.isEmpty, !normalizedReplacement.isEmpty else {
            return nil
        }

        return TranscriptionCorrectionRule(
            source: normalizedSource,
            replacement: normalizedReplacement
        )
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        let normalizedQuery = Self.searchNormalizedValue(query)
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return !searchMatches(for: query).isEmpty
    }

    func searchMatches(for query: String) -> [TranscriptionCorrectionSearchMatch] {
        let normalizedQuery = Self.searchNormalizedValue(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let candidates = [
            TranscriptionCorrectionSearchMatch(source: .source, value: source),
            TranscriptionCorrectionSearchMatch(source: .replacement, value: replacement)
        ]

        return candidates.compactMap { candidate in
            guard let highlight = Self.searchMatchHighlight(in: candidate.value, query: query) else {
                return nil
            }

            return TranscriptionCorrectionSearchMatch(
                source: candidate.source,
                value: candidate.value,
                highlight: highlight
            )
        }
    }

    private static func searchNormalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func searchMatchHighlight(
        in value: String,
        query: String
    ) -> TranscriptionCorrectionSearchHighlight? {
        let normalizedQuery = searchNormalizedValue(query)
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        guard searchNormalizedValue(value).contains(normalizedQuery) else {
            return nil
        }

        guard let range = value.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return TranscriptionCorrectionSearchHighlight(
                location: 0,
                length: value.count
            )
        }

        let location = value.distance(from: value.startIndex, to: range.lowerBound)
        let length = value.distance(from: range.lowerBound, to: range.upperBound)
        return TranscriptionCorrectionSearchHighlight(location: location, length: length)
    }
}

public extension Array where Element == TranscriptionCorrectionRule {
    var normalizedForPersistence: [TranscriptionCorrectionRule] {
        compactMap(\.normalizedForPersistence)
    }
}

public struct TranscriptionCorrectionEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case explicitRule
        case glossary
        case candidateRule
    }

    public var kind: Kind
    public var detail: String?

    public init(kind: Kind, detail: String? = nil) {
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.detail = trimmedDetail?.isEmpty == true ? nil : trimmedDetail
    }
}

public struct TranscriptionCandidateAutoApplyPolicy: Codable, Equatable, Sendable {
    public enum Strategy: String, Codable, Equatable, Sendable {
        case never
        case always
        case ifConfidenceAtLeast
    }

    public var strategy: Strategy
    public var minimumConfidence: Double?

    public init(strategy: Strategy = .never, minimumConfidence: Double? = nil) {
        self.strategy = strategy
        switch strategy {
        case .never, .always:
            self.minimumConfidence = nil
        case .ifConfidenceAtLeast:
            self.minimumConfidence = Self.clamp(minimumConfidence ?? 1.0)
        }
    }

    public static let never = Self()
    public static let always = Self(strategy: .always)

    public static func ifConfidenceAtLeast(_ threshold: Double) -> Self {
        Self(strategy: .ifConfidenceAtLeast, minimumConfidence: threshold)
    }

    public func shouldAutoApply(confidence: Double) -> Bool {
        switch strategy {
        case .never:
            return false
        case .always:
            return true
        case .ifConfidenceAtLeast:
            return confidence >= (minimumConfidence ?? 1.0)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct TranscriptionCandidateCorrectionRule: Codable, Equatable, Sendable {
    public var source: String
    public var aliases: [String]
    public var replacement: String
    public var confidence: Double
    public var evidence: TranscriptionCorrectionEvidence
    public var autoApplyPolicy: TranscriptionCandidateAutoApplyPolicy

    public init(
        source: String,
        aliases: [String] = [],
        replacement: String,
        confidence: Double,
        evidence: TranscriptionCorrectionEvidence,
        autoApplyPolicy: TranscriptionCandidateAutoApplyPolicy
    ) {
        self.source = source
        self.aliases = aliases
        self.replacement = replacement
        self.confidence = confidence
        self.evidence = evidence
        self.autoApplyPolicy = autoApplyPolicy
    }

    enum CodingKeys: String, CodingKey {
        case source
        case aliases
        case replacement
        case confidence
        case evidence
        case autoApplyPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        replacement = try container.decode(String.self, forKey: .replacement)
        confidence = try container.decode(Double.self, forKey: .confidence)
        evidence = try container.decode(TranscriptionCorrectionEvidence.self, forKey: .evidence)
        autoApplyPolicy = try container.decode(
            TranscriptionCandidateAutoApplyPolicy.self,
            forKey: .autoApplyPolicy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(replacement, forKey: .replacement)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(autoApplyPolicy, forKey: .autoApplyPolicy)
    }
}

public extension TranscriptionCandidateCorrectionRule {
    var matchingVariants: [String] {
        var variants: [String] = []
        var seen = Set<String>()

        let inferred = TranscriptionGlossaryItem.acronymAliasCandidates(from: replacement)

        for candidate in [source] + aliases + inferred {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = Self.aliasDedupeKey(trimmed)
            guard seen.insert(key).inserted else {
                continue
            }

            variants.append(trimmed)
        }

        return variants
    }

    var normalizedForEvaluation: TranscriptionCandidateCorrectionRule? {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSource.isEmpty, !normalizedReplacement.isEmpty else {
            return nil
        }

        var seenAliases = Set<String>()
        let sourceKey = Self.aliasDedupeKey(normalizedSource)
        let normalizedAliases = aliases.compactMap { alias -> String? in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let dedupeKey = Self.aliasDedupeKey(trimmed)
            guard dedupeKey != sourceKey, seenAliases.insert(dedupeKey).inserted else {
                return nil
            }

            return trimmed
        }

        return TranscriptionCandidateCorrectionRule(
            source: normalizedSource,
            aliases: normalizedAliases,
            replacement: normalizedReplacement,
            confidence: min(max(confidence, 0), 1),
            evidence: evidence,
            autoApplyPolicy: autoApplyPolicy
        )
    }

    private static func aliasDedupeKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

public extension Array where Element == TranscriptionCandidateCorrectionRule {
    var normalizedForEvaluation: [TranscriptionCandidateCorrectionRule] {
        compactMap(\.normalizedForEvaluation)
    }
}

public struct TranscriptionCandidateCorrection: Codable, Equatable, Sendable {
    public var sourceText: String
    public var canonicalSource: String?
    public var replacement: String
    public var resolvedReplacement: String
    public var sourceRangeLocation: Int?
    public var sourceRangeLength: Int?
    public var confidence: Double
    public var evidence: TranscriptionCorrectionEvidence
    public var autoApplyPolicy: TranscriptionCandidateAutoApplyPolicy

    public init(
        sourceText: String,
        canonicalSource: String? = nil,
        replacement: String,
        resolvedReplacement: String? = nil,
        sourceRangeLocation: Int? = nil,
        sourceRangeLength: Int? = nil,
        confidence: Double,
        evidence: TranscriptionCorrectionEvidence,
        autoApplyPolicy: TranscriptionCandidateAutoApplyPolicy
    ) {
        self.sourceText = sourceText
        let trimmedCanonicalSource = canonicalSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.canonicalSource = trimmedCanonicalSource?.isEmpty == true ? nil : trimmedCanonicalSource
        self.replacement = replacement
        self.resolvedReplacement = resolvedReplacement ?? replacement
        self.sourceRangeLocation = sourceRangeLocation
        self.sourceRangeLength = sourceRangeLength
        self.confidence = confidence
        self.evidence = evidence
        self.autoApplyPolicy = autoApplyPolicy
    }

    enum CodingKeys: String, CodingKey {
        case sourceText
        case canonicalSource
        case replacement
        case resolvedReplacement
        case sourceRangeLocation
        case sourceRangeLength
        case confidence
        case evidence
        case autoApplyPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        canonicalSource = try container.decodeIfPresent(String.self, forKey: .canonicalSource)
        replacement = try container.decode(String.self, forKey: .replacement)
        resolvedReplacement = try container.decodeIfPresent(String.self, forKey: .resolvedReplacement)
            ?? replacement
        sourceRangeLocation = try container.decodeIfPresent(Int.self, forKey: .sourceRangeLocation)
        sourceRangeLength = try container.decodeIfPresent(Int.self, forKey: .sourceRangeLength)
        confidence = try container.decode(Double.self, forKey: .confidence)
        evidence = try container.decode(TranscriptionCorrectionEvidence.self, forKey: .evidence)
        autoApplyPolicy = try container.decode(
            TranscriptionCandidateAutoApplyPolicy.self,
            forKey: .autoApplyPolicy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceText, forKey: .sourceText)
        try container.encodeIfPresent(canonicalSource, forKey: .canonicalSource)
        try container.encode(replacement, forKey: .replacement)
        try container.encode(resolvedReplacement, forKey: .resolvedReplacement)
        try container.encodeIfPresent(sourceRangeLocation, forKey: .sourceRangeLocation)
        try container.encodeIfPresent(sourceRangeLength, forKey: .sourceRangeLength)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(autoApplyPolicy, forKey: .autoApplyPolicy)
    }
}

public extension TranscriptionCandidateCorrection {
    var promotedAlwaysApplyRule: TranscriptionCandidateCorrectionRule? {
        let normalizedVisibleSource = promotedVisibleSource
        let normalizedCanonicalSource = canonicalSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        let ruleSource = (normalizedCanonicalSource?.isEmpty == false
            ? normalizedCanonicalSource
            : normalizedVisibleSource)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let ruleSource, !ruleSource.isEmpty, !normalizedReplacement.isEmpty else {
            return nil
        }

        let alias: String?
        if let normalizedVisibleSource {
            let trimmedVisible = normalizedVisibleSource.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedVisible.isEmpty,
               Self.candidateRuleDedupeKey(trimmedVisible) != Self.candidateRuleDedupeKey(ruleSource) {
                alias = trimmedVisible
            } else {
                alias = nil
            }
        } else {
            alias = nil
        }

        return TranscriptionCandidateCorrectionRule(
            source: ruleSource,
            aliases: alias.map { [$0] } ?? [],
            replacement: normalizedReplacement,
            confidence: 1,
            evidence: evidence,
            autoApplyPolicy: .always
        ).normalizedForEvaluation
    }

    func applying(to text: String) -> String? {
        if let sourceRange = stableSourceRange(in: text) {
            var updated = text
            updated.replaceSubrange(sourceRange, with: resolvedReplacement)
            return updated
        }

        guard sourceRangeLocation == nil, sourceRangeLength == nil,
              let sourceRange = text.range(of: sourceText)
        else {
            return nil
        }

        var updated = text
        updated.replaceSubrange(sourceRange, with: resolvedReplacement)
        return updated
    }

    private func stableSourceRange(in text: String) -> Range<String.Index>? {
        guard let sourceRangeLocation, let sourceRangeLength else {
            return nil
        }

        let nsRange = NSRange(location: sourceRangeLocation, length: sourceRangeLength)
        guard let range = Range(nsRange, in: text),
              String(text[range]) == sourceText
        else {
            return nil
        }

        return range
    }

    private var promotedVisibleSource: String? {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            return nil
        }

        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResolvedReplacement = resolvedReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReplacement.isEmpty, !trimmedResolvedReplacement.isEmpty else {
            return trimmedSource
        }

        for suffix in Self.promotableAttachedSuffixes.sorted(by: { $0.count > $1.count }) {
            guard trimmedSource.hasSuffix(suffix),
                  trimmedResolvedReplacement.hasSuffix(suffix)
            else {
                continue
            }

            let sourceBase = String(trimmedSource.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedBase = String(trimmedResolvedReplacement.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !sourceBase.isEmpty,
                  !resolvedBase.isEmpty,
                  resolvedBase == trimmedReplacement
            else {
                continue
            }

            return sourceBase
        }

        return trimmedSource
    }

    private static func candidateRuleDedupeKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static let promotableAttachedSuffixes: [String] = [
        "입니다", "이에요", "예요", "이라고", "라고", "이라서", "라서",
        "에서", "으로", "까지", "부터", "처럼", "마다", "에게", "한테", "께서",
        "이랑", "하고", "랑", "은", "는", "이", "가", "을", "를", "와", "과",
        "도", "만", "의", "에", "로",
        "では", "には", "とは", "から", "まで", "より",
        "で", "に", "は", "が", "を", "と", "も", "の", "へ", "や"
    ]
}

public extension Array where Element == TranscriptionCandidateCorrectionRule {
    func upsertingPromotedSuggestion(
        _ candidate: TranscriptionCandidateCorrection
    ) -> [TranscriptionCandidateCorrectionRule] {
        guard let promotedRule = candidate.promotedAlwaysApplyRule else {
            return self
        }

        var updated = self
        if let existingIndex = updated.firstIndex(where: {
            guard let normalizedRule = $0.normalizedForEvaluation else {
                return false
            }

            return Self.promotionDedupeKey(for: normalizedRule.source)
                == Self.promotionDedupeKey(for: promotedRule.source)
                && Self.promotionDedupeKey(for: normalizedRule.replacement)
                == Self.promotionDedupeKey(for: promotedRule.replacement)
        }) {
            let existingNormalizedRule = updated[existingIndex].normalizedForEvaluation ?? promotedRule
            var existingRule = existingNormalizedRule
            existingRule.aliases = (existingRule.aliases + promotedRule.aliases)
                .normalizedForPromotionAliases(source: existingRule.source)
            existingRule.confidence = 1
            existingRule.autoApplyPolicy = .always
            if existingRule.evidence.detail == nil {
                existingRule.evidence = promotedRule.evidence
            }
            updated[existingIndex] = existingRule.normalizedForEvaluation ?? promotedRule
            return updated
        }

        updated.append(promotedRule)
        return updated
    }

    private static func promotionDedupeKey(for value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private extension Array where Element == String {
    func normalizedForPromotionAliases(source: String) -> [String] {
        let sourceKey = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var seen = Set<String>()

        return compactMap { alias in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard key != sourceKey, seen.insert(key).inserted else {
                return nil
            }

            return trimmed
        }
    }
}

public struct TranscriptionFormattingOptions: Codable, Equatable, Sendable {
    public var capitalizeFirstCharacter: Bool
    public var ensureTrailingPunctuation: Bool
    public var trimLeadingAndTrailingWhitespace: Bool

    public init(
        capitalizeFirstCharacter: Bool = false,
        ensureTrailingPunctuation: Bool = false,
        trimLeadingAndTrailingWhitespace: Bool = false
    ) {
        self.capitalizeFirstCharacter = capitalizeFirstCharacter
        self.ensureTrailingPunctuation = ensureTrailingPunctuation
        self.trimLeadingAndTrailingWhitespace = trimLeadingAndTrailingWhitespace
    }

    public static let preserveExactOutput = Self()

    public var preservesExactOutput: Bool {
        !capitalizeFirstCharacter
            && !ensureTrailingPunctuation
            && !trimLeadingAndTrailingWhitespace
    }
}

public struct PostTranscriptionProcessingConfiguration: Codable, Equatable, Sendable {
    public var glossary: [TranscriptionGlossaryItem]
    public var corrections: [TranscriptionCorrectionRule]
    public var candidateCorrections: [TranscriptionCandidateCorrectionRule]
    public var formatting: TranscriptionFormattingOptions
    public var outputPreset: TranscriptionOutputPreset

    public init(
        glossary: [TranscriptionGlossaryItem] = [],
        corrections: [TranscriptionCorrectionRule] = [],
        candidateCorrections: [TranscriptionCandidateCorrectionRule] = [],
        formatting: TranscriptionFormattingOptions = .preserveExactOutput,
        outputPreset: TranscriptionOutputPreset = .verbatim
    ) {
        self.glossary = glossary
        self.corrections = corrections
        self.candidateCorrections = candidateCorrections.normalizedForEvaluation
        self.formatting = formatting
        self.outputPreset = outputPreset
    }

    public static let noOp = Self()

    public var isNoOp: Bool {
        glossary.isEmpty
            && corrections.isEmpty
            && candidateCorrections.isEmpty
            && formatting.preservesExactOutput
            && outputPreset == .verbatim
    }
}

public struct PostTranscriptionProcessingResult: Equatable, Sendable {
    public let originalText: String
    public let processedText: String
    public let appliedCorrections: [TranscriptionCandidateCorrection]
    public let suppressedCandidates: [TranscriptionCandidateCorrection]

    public init(
        originalText: String,
        processedText: String,
        appliedCorrections: [TranscriptionCandidateCorrection] = [],
        suppressedCandidates: [TranscriptionCandidateCorrection] = []
    ) {
        self.originalText = originalText
        self.processedText = processedText
        self.appliedCorrections = appliedCorrections
        self.suppressedCandidates = suppressedCandidates
    }

    public var didChange: Bool {
        originalText != processedText
    }
}
