import Foundation

/// Lightweight fuzzy subsequence matcher with scoring, used to filter the
/// current directory live. Higher scores rank first.
enum FuzzyMatcher {

    /// Returns a match score, or `nil` if `query` is not a subsequence of
    /// `candidate` (case-insensitive). An empty query matches everything with a
    /// neutral score of 0.
    static func score(_ candidate: String, query: String) -> Int? {
        if query.isEmpty { return 0 }

        let haystack = Array(candidate.lowercased())
        let needle = Array(query.lowercased())

        var score = 0
        var haystackIndex = 0
        var previousMatchIndex = -2

        for needleChar in needle {
            var found = false
            while haystackIndex < haystack.count {
                let current = haystack[haystackIndex]
                haystackIndex += 1
                if current == needleChar {
                    score += 1
                    // Bonus for consecutive matches.
                    if haystackIndex - 1 == previousMatchIndex + 1 {
                        score += 5
                    }
                    // Bonus for start-of-word / start-of-string matches.
                    if haystackIndex - 1 == 0 {
                        score += 8
                    } else {
                        let prev = haystack[haystackIndex - 2]
                        if prev == " " || prev == "-" || prev == "_" || prev == "." {
                            score += 8
                        }
                    }
                    previousMatchIndex = haystackIndex - 1
                    found = true
                    break
                }
            }
            if !found { return nil }
        }
        // Prefer shorter candidates when scores are otherwise close.
        score -= max(0, haystack.count - needle.count) / 8
        return score
    }

    static func matches(_ candidate: String, query: String) -> Bool {
        score(candidate, query: query) != nil
    }
}
