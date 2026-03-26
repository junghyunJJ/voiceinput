import Foundation

public struct PostTranscriptionProcessor: Sendable {
    public var configuration: PostTranscriptionProcessingConfiguration

    public init(configuration: PostTranscriptionProcessingConfiguration = .noOp) {
        self.configuration = configuration
    }

    public func process(_ transcription: String) -> PostTranscriptionProcessingResult {
        let processing = processed(transcription)
        return PostTranscriptionProcessingResult(
            originalText: transcription,
            processedText: processing.text,
            appliedCorrections: processing.appliedCorrections,
            suppressedCandidates: processing.suppressedCandidates
        )
    }

    private func processed(_ transcription: String) -> ProcessingPassResult {
        guard !configuration.isNoOp else {
            return ProcessingPassResult(
                text: transcription,
                appliedCorrections: [],
                suppressedCandidates: []
            )
        }

        var current = transcription
        var appliedCorrections: [TranscriptionCandidateCorrection] = []
        var suppressedCandidates: [TranscriptionCandidateCorrection] = []

        current = applyCorrections(to: current, appliedCorrections: &appliedCorrections)
        current = applyGlossary(to: current, appliedCorrections: &appliedCorrections)
        current = applyCandidateCorrections(
            to: current,
            appliedCorrections: &appliedCorrections,
            suppressedCandidates: &suppressedCandidates
        )
        suppressedCandidates = dedupedAndSortedSuppressedCandidates(suppressedCandidates)
        current = applyFormattingOptions(to: current, options: configuration.formatting)
        current = applyPreset(to: current, preset: configuration.outputPreset)
        return ProcessingPassResult(
            text: current,
            appliedCorrections: appliedCorrections,
            suppressedCandidates: suppressedCandidates
        )
    }

    private func applyCorrections(
        to text: String,
        appliedCorrections: inout [TranscriptionCandidateCorrection]
    ) -> String {
        let rules = configuration.corrections.map {
            ReplacementRule(
                canonicalSource: $0.source,
                variants: [$0.source],
                replacement: $0.replacement,
                confidence: 1,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .explicitRule,
                    detail: $0.source
                ),
                autoApplyPolicy: .always,
                matchingStyle: .standardFlexible
            )
        }
        return applyReplacementRules(
            rules,
            to: text,
            appliedCorrections: &appliedCorrections
        )
    }

    private func applyGlossary(
        to text: String,
        appliedCorrections: inout [TranscriptionCandidateCorrection]
    ) -> String {
        let rules = configuration.glossary.map { item in
            let variants = [item.phrase] + item.effectiveAliases
            return ReplacementRule(
                canonicalSource: item.phrase,
                variants: variants,
                replacement: item.replacement,
                confidence: 1,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .glossary,
                    detail: item.phrase
                ),
                autoApplyPolicy: .always,
                matchingStyle: .standardFlexible
            )
        }
        return applyReplacementRules(
            rules,
            to: text,
            appliedCorrections: &appliedCorrections
        )
    }

    private func applyCandidateCorrections(
        to text: String,
        appliedCorrections: inout [TranscriptionCandidateCorrection],
        suppressedCandidates: inout [TranscriptionCandidateCorrection]
    ) -> String {
        let rules = configuration.candidateCorrections.map {
            ReplacementRule(
                canonicalSource: $0.source,
                variants: $0.matchingVariants,
                replacement: $0.replacement,
                confidence: $0.confidence,
                evidence: $0.evidence,
                autoApplyPolicy: $0.autoApplyPolicy,
                matchingStyle: .conservativeCandidate
            )
        }
        return applyReplacementRules(
            rules,
            to: text,
            appliedCorrections: &appliedCorrections,
            suppressedCandidates: &suppressedCandidates
        )
    }

    private func applyReplacementRules(
        _ rules: [ReplacementRule],
        to text: String,
        appliedCorrections: inout [TranscriptionCandidateCorrection]
    ) -> String {
        var discardedSuppressedCandidates: [TranscriptionCandidateCorrection] = []
        return applyReplacementRules(
            rules,
            to: text,
            appliedCorrections: &appliedCorrections,
            suppressedCandidates: &discardedSuppressedCandidates
        )
    }

    private func applyReplacementRules(
        _ rules: [ReplacementRule],
        to text: String,
        appliedCorrections: inout [TranscriptionCandidateCorrection],
        suppressedCandidates: inout [TranscriptionCandidateCorrection]
    ) -> String {
        let patterns = compiledPatterns(from: rules)
        return patterns.reduce(text) { partial, pattern in
            applyCompiledPattern(
                pattern,
                to: partial,
                appliedCorrections: &appliedCorrections,
                suppressedCandidates: &suppressedCandidates
            )
        }
    }

    private func compiledPatterns(from rules: [ReplacementRule]) -> [CompiledReplacementPattern] {
        let patterns = rules.flatMap { rule in
            rule.variants.flatMap { variant in
                compiledPatterns(
                    for: variant.trimmingCharacters(in: .whitespacesAndNewlines),
                    canonicalSource: rule.canonicalSource,
                    replacement: rule.replacement,
                    confidence: rule.confidence,
                    evidence: rule.evidence,
                    autoApplyPolicy: rule.autoApplyPolicy,
                    matchingStyle: rule.matchingStyle
                )
            }
        }

        var dedupedPatterns: [String: CompiledReplacementPattern] = [:]
        for pattern in patterns {
            let key =
                "\(pattern.pattern)|\(pattern.preserveTrailingCapture)|\(pattern.replacement)|\(pattern.confidence)|\(pattern.evidence.kind.rawValue)|\(pattern.evidence.detail ?? "")|\(pattern.autoApplyPolicy.strategy.rawValue)|\(pattern.autoApplyPolicy.minimumConfidence ?? -1)"

            guard let existing = dedupedPatterns[key] else {
                dedupedPatterns[key] = pattern
                continue
            }

            guard existing.canonicalSource != pattern.canonicalSource else {
                continue
            }

            dedupedPatterns[key] = CompiledReplacementPattern(
                pattern: existing.pattern,
                canonicalSource: nil,
                replacement: existing.replacement,
                confidence: existing.confidence,
                evidence: existing.evidence,
                autoApplyPolicy: existing.autoApplyPolicy,
                preserveTrailingCapture: existing.preserveTrailingCapture,
                priority: existing.priority
            )
        }

        return dedupedPatterns.values.sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    if lhs.preserveTrailingCapture == rhs.preserveTrailingCapture {
                        return lhs.pattern.count > rhs.pattern.count
                    }
                    return lhs.preserveTrailingCapture && !rhs.preserveTrailingCapture
                }
                return lhs.priority > rhs.priority
            }
    }

    private func compiledPatterns(
        for variant: String,
        canonicalSource: String?,
        replacement: String,
        confidence: Double,
        evidence: TranscriptionCorrectionEvidence,
        autoApplyPolicy: TranscriptionCandidateAutoApplyPolicy,
        matchingStyle: ReplacementRule.MatchingStyle
    ) -> [CompiledReplacementPattern] {
        guard !variant.isEmpty else {
            return []
        }

        var patterns: [CompiledReplacementPattern] = []
        let tokenComponents = variantTokenComponents(variant)
        let exactBody = NSRegularExpression.escapedPattern(for: variant)
        let trailingGuard = trailingGuard(for: variant)
        let flexibleBody = flexibleVariantPatternBody(
            for: tokenComponents,
            separatorPattern: separatorPattern(
                for: variant,
                requiresExplicitSeparator: matchingStyle == .conservativeCandidate
            )
        )
        let priority = normalizedPriority(for: variant, tokens: tokenComponents)
        let includeExactPatterns = matchingStyle != .conservativeCandidate || tokenComponents.count <= 1

        if includeExactPatterns {
            patterns.append(
                CompiledReplacementPattern(
                    pattern: boundaryWrapped(exactBody, trailingGuard: trailingGuard),
                    canonicalSource: canonicalSource,
                    replacement: replacement,
                    confidence: confidence,
                    evidence: evidence,
                    autoApplyPolicy: autoApplyPolicy,
                    preserveTrailingCapture: false,
                    priority: priority + 2
                )
            )

            patterns.append(
                CompiledReplacementPattern(
                    pattern: suffixWrapped(
                        exactBody,
                        trailingGuard: trailingGuard,
                        matchingStyle: matchingStyle
                    ),
                    canonicalSource: canonicalSource,
                    replacement: replacement,
                    confidence: confidence,
                    evidence: evidence,
                    autoApplyPolicy: autoApplyPolicy,
                    preserveTrailingCapture: true,
                    priority: priority + 1
                )
            )
        }

        if matchingStyle != .exactOnly, let flexibleBody, flexibleBody != exactBody {
            patterns.append(
                CompiledReplacementPattern(
                    pattern: boundaryWrapped(flexibleBody, trailingGuard: trailingGuard),
                    canonicalSource: canonicalSource,
                    replacement: replacement,
                    confidence: confidence,
                    evidence: evidence,
                    autoApplyPolicy: autoApplyPolicy,
                    preserveTrailingCapture: false,
                    priority: priority
                )
            )

            patterns.append(
                CompiledReplacementPattern(
                    pattern: suffixWrapped(
                        flexibleBody,
                        trailingGuard: trailingGuard,
                        matchingStyle: matchingStyle
                    ),
                    canonicalSource: canonicalSource,
                    replacement: replacement,
                    confidence: confidence,
                    evidence: evidence,
                    autoApplyPolicy: autoApplyPolicy,
                    preserveTrailingCapture: true,
                    priority: priority - 1
                )
            )
        }

        return patterns
    }

    private func boundaryWrapped(_ body: String, trailingGuard: String? = nil) -> String {
        let suffix = trailingGuard ?? ""
        return #"(?<![\p{L}\p{N}])"# + body + suffix + #"(?![\p{L}\p{N}])"#
    }

    private func suffixWrapped(
        _ body: String,
        trailingGuard: String? = nil,
        matchingStyle: ReplacementRule.MatchingStyle
    ) -> String {
        // Standard rules keep the broad suffix matcher so glossary and exact
        // corrections can still normalize dense mixed-language phrases. Candidate
        // rules use a more conservative suffix pattern to avoid firing inside
        // ordinary Korean/Japanese words such as `에러` or `のり`.
        let suffix = trailingGuard ?? ""
        let suffixPattern = matchingStyle == .conservativeCandidate
            ? conservativeAttachedSuffixPattern
            : attachedSuffixPattern
        return #"(?<![\p{L}\p{N}])"# + body + suffix + "(\(suffixPattern))"
    }

    private var attachedSuffixPattern: String {
        Self.attachedSuffixes
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
    }

    private var conservativeAttachedSuffixPattern: String {
        var patterns: [String] = []

        let escapedKorean = Self.koreanAttachedParticles
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        if !escapedKorean.isEmpty {
            patterns.append(#"(?:"# + escapedKorean + #")(?=$|[\s\p{P}\p{S}])"#)
        }

        let japaneseMultiCharacter = Self.japaneseAttachedParticles
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        if !japaneseMultiCharacter.isEmpty {
            patterns.append(#"(?:"# + japaneseMultiCharacter + #")"#)
        }

        let japaneseSingleCharacter = Self.japaneseAttachedParticles
            .filter { $0.count == 1 }
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        if !japaneseSingleCharacter.isEmpty {
            patterns.append(
                #"(?:"# + japaneseSingleCharacter + #")(?=$|[\s\p{P}\p{S}]|[^\p{Hiragana}])"#
            )
        }

        return patterns.joined(separator: "|")
    }

    private func variantTokenComponents(_ variant: String) -> [String] {
        if let fullDottedTokens = TranscriptionGlossaryItem.fullDottedModelTokens(from: variant) {
            return fullDottedTokens
        }

        if let dottedTokens = TranscriptionGlossaryItem.dottedModelTokens(from: variant) {
            return dottedTokens
        }

        if let compactTokens = TranscriptionGlossaryItem.compactModelTokens(from: variant) {
            return compactTokens
        }

        let nsRange = NSRange(variant.startIndex..., in: variant)
        guard let regex = try? NSRegularExpression(pattern: #"\p{L}[\p{L}\p{N}]*|\p{N}+"#) else {
            return []
        }

        return regex.matches(in: variant, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: variant) else {
                return nil
            }
            return String(variant[range])
        }
    }

    private func flexibleVariantPatternBody(
        for tokens: [String],
        separatorPattern: String
    ) -> String? {
        guard tokens.count > 1 else {
            return nil
        }

        return tokens
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: separatorPattern)
    }

    private func separatorPattern(
        for variant: String,
        requiresExplicitSeparator: Bool
    ) -> String {
        if TranscriptionGlossaryItem.fullDottedModelTokens(from: variant) != nil
            || TranscriptionGlossaryItem.dottedModelTokens(from: variant) != nil
        {
            return requiresExplicitSeparator ? #"(?:[\s\-]+)"# : #"(?:[\s\-]+)?"#
        }
        return requiresExplicitSeparator ? #"(?:[\s\.\-_/·]+)"# : #"(?:[\s\.\-_/·]+)?"#
    }

    private func trailingGuard(for variant: String) -> String? {
        if let fullVariantTokens = TranscriptionGlossaryItem.fullDottedModelTokens(from: variant) {
            return fullVariantTrailingGuard(exactLabel: fullVariantTokens[2])
        }

        if TranscriptionGlossaryItem.dottedModelTokens(from: variant) != nil {
            return dottedVersionTrailingLabelGuard
        }

        if let compactTokens = TranscriptionGlossaryItem.compactModelTokens(from: variant),
           compactTokens.count == 2,
           TranscriptionGlossaryItem.compactQualifierLabels.contains(compactTokens[1].lowercased())
        {
            return compactQualifierTrailingGuard(exactQualifier: compactTokens[1])
        }

        return nil
    }

    private var dottedVersionTrailingLabelGuard: String {
        #"(?!\s+(?:sonnet|opus|haiku|instruct|vision|turbo)\b)"#
    }

    private func fullVariantTrailingGuard(exactLabel: String) -> String {
        let blockedLabels = ([exactLabel] + Self.modelVariantLabels)
            .map(NSRegularExpression.escapedPattern)
            .sorted { $0.count > $1.count }
            .joined(separator: "|")

        return #"(?!\s+(?:[0-9]+(?:\.[0-9]+)?|"#
            + blockedLabels
            + #")\b)"#
    }

    private func compactQualifierTrailingGuard(exactQualifier: String) -> String {
        let blockedQualifiers = ([exactQualifier] + TranscriptionGlossaryItem.compactQualifierLabels)
            .map(NSRegularExpression.escapedPattern)
            .sorted { $0.count > $1.count }
            .joined(separator: "|")

        return #"(?![\s\.\-_/·]+(?:[0-9]+(?:\.[0-9]+)?|"#
            + blockedQualifiers
            + #")\b)"#
    }

    private func normalizedPriority(for variant: String, tokens: [String]) -> Int {
        let tokenLength = tokens.reduce(0) { $0 + $1.count }
        return max(tokenLength, variant.count)
    }

    private func applyCompiledPattern(
        _ pattern: CompiledReplacementPattern,
        to text: String,
        appliedCorrections: inout [TranscriptionCandidateCorrection],
        suppressedCandidates: inout [TranscriptionCandidateCorrection]
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern.pattern,
            options: [.caseInsensitive]
        ) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else {
            return text
        }

        var result = text
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else {
                continue
            }

            let sourceText = String(result[matchRange])
            var replacement = pattern.replacement
            if pattern.preserveTrailingCapture,
               match.numberOfRanges > 1,
               let suffixRange = Range(match.range(at: 1), in: result)
            {
                replacement += String(result[suffixRange])
            }

            guard !isAlreadyNormalized(sourceText, replacement: replacement) else {
                continue
            }

            let candidate = TranscriptionCandidateCorrection(
                sourceText: sourceText,
                canonicalSource: pattern.canonicalSource,
                replacement: pattern.replacement,
                resolvedReplacement: replacement,
                sourceRangeLocation: match.range.location,
                sourceRangeLength: match.range.length,
                confidence: pattern.confidence,
                evidence: pattern.evidence,
                autoApplyPolicy: pattern.autoApplyPolicy
            )

            guard pattern.autoApplyPolicy.shouldAutoApply(confidence: pattern.confidence) else {
                suppressedCandidates.append(candidate)
                continue
            }

            result.replaceSubrange(matchRange, with: replacement)
            appliedCorrections.append(candidate)
        }

        return result
    }

    private func isAlreadyNormalized(_ sourceText: String, replacement: String) -> Bool {
        sourceText == replacement
    }

    private func dedupedAndSortedSuppressedCandidates(
        _ candidates: [TranscriptionCandidateCorrection]
    ) -> [TranscriptionCandidateCorrection] {
        guard candidates.count > 1 else {
            return candidates
        }

        let indexedCandidates = candidates.enumerated().map { index, candidate in
            IndexedSuppressedCandidate(index: index, candidate: candidate)
        }

        let rangedCandidates = indexedCandidates.filter { stableRange(for: $0.candidate) != nil }
        let unrangedCandidates = indexedCandidates.filter { stableRange(for: $0.candidate) == nil }

        var deduped: [TranscriptionCandidateCorrection] = []

        let rangedGroups = Dictionary(grouping: rangedCandidates) { indexedCandidate in
            normalizedSuppressedReplacementKey(for: indexedCandidate.candidate)
        }
        for group in rangedGroups.values {
            deduped.append(contentsOf: overlapDedupedWinners(from: group))
        }

        let unrangedGroups = Dictionary(grouping: unrangedCandidates) { indexedCandidate in
            SuppressedCandidateFallbackGroupKey(candidate: indexedCandidate.candidate)
        }
        for group in unrangedGroups.values {
            if let winner = dedupedWinner(from: group) {
                deduped.append(winner)
            }
        }

        return deduped.sorted(by: suppressedCandidateDisplayPrecedes(_:_:))
    }

    private func overlapDedupedWinners(
        from candidates: [IndexedSuppressedCandidate]
    ) -> [TranscriptionCandidateCorrection] {
        let sortedCandidates = candidates.sorted { lhs, rhs in
            guard let lhsRange = stableRange(for: lhs.candidate),
                  let rhsRange = stableRange(for: rhs.candidate) else {
                return lhs.index < rhs.index
            }

            if lhsRange.location != rhsRange.location {
                return lhsRange.location < rhsRange.location
            }

            if lhsRange.length != rhsRange.length {
                return lhsRange.length > rhsRange.length
            }

            return lhs.index < rhs.index
        }

        var groups: [[IndexedSuppressedCandidate]] = []
        var currentGroup: [IndexedSuppressedCandidate] = []
        var representativeRange: SuppressedCandidateStableRange?

        for candidate in sortedCandidates {
            guard let range = stableRange(for: candidate.candidate) else {
                continue
            }

            if let currentRepresentativeRange = representativeRange,
               !currentGroup.isEmpty,
               currentRepresentativeRange.isNestedOverlap(with: range)
            {
                currentGroup.append(candidate)
                representativeRange = currentRepresentativeRange.containing(range)
                continue
            }

            if !currentGroup.isEmpty {
                groups.append(currentGroup)
            }

            currentGroup = [candidate]
            representativeRange = range
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups.compactMap { dedupedWinner(from: $0) }
    }

    private func stableRange(
        for candidate: TranscriptionCandidateCorrection
    ) -> SuppressedCandidateStableRange? {
        guard let location = candidate.sourceRangeLocation,
              let length = candidate.sourceRangeLength else {
            return nil
        }

        return SuppressedCandidateStableRange(location: location, length: length)
    }

    private func normalizedSuppressedReplacementKey(
        for candidate: TranscriptionCandidateCorrection
    ) -> String {
        candidate.resolvedReplacement
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func dedupedWinner(
        from group: [IndexedSuppressedCandidate]
    ) -> TranscriptionCandidateCorrection? {
        guard var winner = group.first else {
            return nil
        }

        let prefersRepresentativeSpan = groupContainsDistinctStableRanges(group)

        for candidate in group.dropFirst() {
            if suppressedCandidateHasHigherPriority(
                candidate,
                than: winner,
                prefersRepresentativeSpan: prefersRepresentativeSpan
            ) {
                winner = candidate
            }
        }

        let canonicalSources = Set(
            group.compactMap { indexedCandidate in
                indexedCandidate.candidate.canonicalSource?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
        )

        guard canonicalSources.count > 1 else {
            return winner.candidate
        }

        return TranscriptionCandidateCorrection(
            sourceText: winner.candidate.sourceText,
            canonicalSource: nil,
            replacement: winner.candidate.replacement,
            resolvedReplacement: winner.candidate.resolvedReplacement,
            sourceRangeLocation: winner.candidate.sourceRangeLocation,
            sourceRangeLength: winner.candidate.sourceRangeLength,
            confidence: winner.candidate.confidence,
            evidence: winner.candidate.evidence,
            autoApplyPolicy: winner.candidate.autoApplyPolicy
        )
    }

    private func suppressedCandidateHasHigherPriority(
        _ lhs: IndexedSuppressedCandidate,
        than rhs: IndexedSuppressedCandidate,
        prefersRepresentativeSpan: Bool = false
    ) -> Bool {
        if prefersRepresentativeSpan,
           let lhsRange = stableRange(for: lhs.candidate),
           let rhsRange = stableRange(for: rhs.candidate) {
            if lhsRange.length != rhsRange.length {
                return lhsRange.length > rhsRange.length
            }

            if lhsRange.location != rhsRange.location {
                return lhsRange.location < rhsRange.location
            }
        }

        if lhs.candidate.confidence != rhs.candidate.confidence {
            return lhs.candidate.confidence > rhs.candidate.confidence
        }

        let lhsPolicyRank = suppressedCandidatePolicyRank(lhs.candidate.autoApplyPolicy)
        let rhsPolicyRank = suppressedCandidatePolicyRank(rhs.candidate.autoApplyPolicy)
        if lhsPolicyRank != rhsPolicyRank {
            return lhsPolicyRank > rhsPolicyRank
        }

        let lhsHasCanonical = lhs.candidate.canonicalSource != nil
        let rhsHasCanonical = rhs.candidate.canonicalSource != nil
        if lhsHasCanonical != rhsHasCanonical {
            return lhsHasCanonical && !rhsHasCanonical
        }

        let lhsSpanLength = lhs.candidate.sourceRangeLength ?? (lhs.candidate.sourceText as NSString).length
        let rhsSpanLength = rhs.candidate.sourceRangeLength ?? (rhs.candidate.sourceText as NSString).length
        if lhsSpanLength != rhsSpanLength {
            return lhsSpanLength > rhsSpanLength
        }

        if lhs.candidate.resolvedReplacement != rhs.candidate.resolvedReplacement {
            return lhs.candidate.resolvedReplacement.localizedStandardCompare(
                rhs.candidate.resolvedReplacement
            ) == .orderedAscending
        }

        if lhs.candidate.sourceText != rhs.candidate.sourceText {
            return lhs.candidate.sourceText.localizedStandardCompare(
                rhs.candidate.sourceText
            ) == .orderedAscending
        }

        let lhsCanonical = lhs.candidate.canonicalSource ?? ""
        let rhsCanonical = rhs.candidate.canonicalSource ?? ""
        if lhsCanonical != rhsCanonical {
            return lhsCanonical.localizedStandardCompare(rhsCanonical) == .orderedAscending
        }

        let lhsDetail = lhs.candidate.evidence.detail ?? ""
        let rhsDetail = rhs.candidate.evidence.detail ?? ""
        if lhsDetail != rhsDetail {
            return lhsDetail.localizedStandardCompare(rhsDetail) == .orderedAscending
        }

        return lhs.index < rhs.index
    }

    private func groupContainsDistinctStableRanges(
        _ group: [IndexedSuppressedCandidate]
    ) -> Bool {
        var ranges = Set<SuppressedCandidateStableRange>()
        for candidate in group {
            guard let range = stableRange(for: candidate.candidate) else {
                continue
            }

            ranges.insert(range)
            if ranges.count > 1 {
                return true
            }
        }

        return false
    }

    private func suppressedCandidateDisplayPrecedes(
        _ lhs: TranscriptionCandidateCorrection,
        _ rhs: TranscriptionCandidateCorrection
    ) -> Bool {
        switch (lhs.sourceRangeLocation, rhs.sourceRangeLocation) {
        case let (lhsLocation?, rhsLocation?) where lhsLocation != rhsLocation:
            return lhsLocation < rhsLocation
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        let lhsSpanLength = lhs.sourceRangeLength ?? (lhs.sourceText as NSString).length
        let rhsSpanLength = rhs.sourceRangeLength ?? (rhs.sourceText as NSString).length
        if lhsSpanLength != rhsSpanLength {
            return lhsSpanLength > rhsSpanLength
        }

        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }

        let lhsHasCanonical = lhs.canonicalSource != nil
        let rhsHasCanonical = rhs.canonicalSource != nil
        if lhsHasCanonical != rhsHasCanonical {
            return lhsHasCanonical && !rhsHasCanonical
        }

        if lhs.resolvedReplacement != rhs.resolvedReplacement {
            return lhs.resolvedReplacement.localizedStandardCompare(rhs.resolvedReplacement) == .orderedAscending
        }

        if lhs.sourceText != rhs.sourceText {
            return lhs.sourceText.localizedStandardCompare(rhs.sourceText) == .orderedAscending
        }

        let lhsCanonical = lhs.canonicalSource ?? ""
        let rhsCanonical = rhs.canonicalSource ?? ""
        return lhsCanonical.localizedStandardCompare(rhsCanonical) == .orderedAscending
    }

    private func suppressedCandidatePolicyRank(
        _ policy: TranscriptionCandidateAutoApplyPolicy
    ) -> Int {
        switch policy.strategy {
        case .never:
            return 0
        case .ifConfidenceAtLeast:
            return 1
        case .always:
            return 2
        }
    }

    private func applyFormattingOptions(
        to text: String,
        options: TranscriptionFormattingOptions
    ) -> String {
        var current = text

        if options.trimLeadingAndTrailingWhitespace {
            current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if options.capitalizeFirstCharacter {
            current = capitalizeLeadingCharacter(in: current)
        }

        if options.ensureTrailingPunctuation {
            current = ensureSentenceTerminator(in: current)
        }

        return current
    }

    private func applyPreset(to text: String, preset: TranscriptionOutputPreset) -> String {
        switch preset {
        case .verbatim:
            return text
        case .casualMessage:
            return capitalizeLeadingCharacter(in: condensedSentence(from: text))
        case .polishedMessage:
            return ensureSentenceTerminator(in: capitalizeLeadingCharacter(in: condensedSentence(from: text)))
        case .emailDraft:
            let body = ensureSentenceTerminator(in: capitalizeLeadingCharacter(in: condensedSentence(from: text)))
            guard !body.isEmpty else {
                return ""
            }
            return "Hi,\n\n\(body)\n\nBest,"
        case .meetingNotes:
            let bullets = bulletLines(from: text)
            guard !bullets.isEmpty else {
                return ""
            }
            return bullets.map { "- \($0)" }.joined(separator: "\n")
        }
    }

    private func condensedSentence(from text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bulletLines(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n;"))
            .map { condensedSentence(from: $0) }
            .filter { !$0.isEmpty }
            .map { capitalizeLeadingCharacter(in: $0) }
    }

    private func capitalizeLeadingCharacter(in text: String) -> String {
        guard let firstLetterRange = text.rangeOfCharacter(from: .letters) else {
            return text
        }

        var result = text
        let character = String(result[firstLetterRange]).uppercased()
        result.replaceSubrange(firstLetterRange, with: character)
        return result
    }

    private func ensureSentenceTerminator(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }

        return trimmed + "."
    }
}

private struct ReplacementRule {
    enum MatchingStyle {
        case exactOnly
        case standardFlexible
        case conservativeCandidate
    }

    let canonicalSource: String?
    let variants: [String]
    let replacement: String
    let confidence: Double
    let evidence: TranscriptionCorrectionEvidence
    let autoApplyPolicy: TranscriptionCandidateAutoApplyPolicy
    let matchingStyle: MatchingStyle
}

private struct CompiledReplacementPattern {
    let pattern: String
    let canonicalSource: String?
    let replacement: String
    let confidence: Double
    let evidence: TranscriptionCorrectionEvidence
    let autoApplyPolicy: TranscriptionCandidateAutoApplyPolicy
    let preserveTrailingCapture: Bool
    let priority: Int
}

private struct ProcessingPassResult {
    let text: String
    let appliedCorrections: [TranscriptionCandidateCorrection]
    let suppressedCandidates: [TranscriptionCandidateCorrection]
}

private struct SuppressedCandidateFallbackGroupKey: Hashable {
    private let normalizedSourceText: String
    private let resolvedReplacementKey: String

    init(candidate: TranscriptionCandidateCorrection) {
        normalizedSourceText = candidate.sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        resolvedReplacementKey = candidate.resolvedReplacement
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct SuppressedCandidateStableRange: Hashable {
    let location: Int
    let length: Int

    var upperBound: Int {
        location + length
    }

    func contains(_ other: SuppressedCandidateStableRange) -> Bool {
        location <= other.location && upperBound >= other.upperBound
    }

    func isNestedOverlap(with other: SuppressedCandidateStableRange) -> Bool {
        contains(other) || other.contains(self)
    }

    func containing(_ other: SuppressedCandidateStableRange) -> SuppressedCandidateStableRange {
        contains(other) ? self : other
    }
}

private struct IndexedSuppressedCandidate {
    let index: Int
    let candidate: TranscriptionCandidateCorrection
}

private extension PostTranscriptionProcessor {
    static let modelVariantLabels: [String] = [
        "sonnet", "opus", "haiku", "instruct", "vision", "turbo",
        "mini", "ultra", "air", "max", "pro"
    ]

    static let attachedSuffixes: [String] = koreanAttachedParticles + japaneseAttachedParticles

    static let koreanAttachedParticles: [String] = [
        "입니다", "이에요", "예요", "이라고", "라고", "이라서", "라서",
        "에서", "으로", "까지", "부터", "처럼", "마다", "에게", "한테", "께서",
        "이랑", "하고", "랑", "은", "는", "이", "가", "을", "를", "와", "과",
        "도", "만", "의", "에", "로"
    ]

    static let japaneseAttachedParticles: [String] = [
        "では", "には", "とは", "から", "まで", "より",
        "で", "に", "は", "が", "を", "と", "も", "の", "へ", "や"
    ]
}
