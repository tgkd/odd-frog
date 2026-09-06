import Testing
@testable import OddFrogCore

struct FuzzyScorerTests {
    @Test func prefixIsPerfect() {
        #expect(FuzzyScorer.normalized(query: "chr", candidate: "Chrome") == 100)
    }

    @Test func nonSubsequenceIsNil() {
        #expect(FuzzyScorer.score(query: "xyz", candidate: "Chrome") == nil)
        #expect(FuzzyScorer.score(query: "", candidate: "Chrome") == nil)
        #expect(FuzzyScorer.score(query: "chromes", candidate: "Chrome") == nil)
    }

    @Test func prefixBeatsBoundaryBeatsScattered() {
        let prefix = FuzzyScorer.score(query: "co", candidate: "Code")!
        let boundary = FuzzyScorer.score(query: "co", candidate: "Visual Code")!
        let scattered = FuzzyScorer.score(query: "co", candidate: "Chrome")!
        #expect(prefix > boundary)
        #expect(boundary > scattered)
    }

    @Test func initialsMatchThroughBoundaries() {
        let initials = FuzzyScorer.score(query: "vsc", candidate: "Visual Studio Code")!
        let scattered = FuzzyScorer.score(query: "vsc", candidate: "Vascular")!
        #expect(initials > scattered)
    }

    @Test func consecutiveBeatsGapped() {
        let consecutive = FuzzyScorer.score(query: "ode", candidate: "Xcode")!
        let gapped = FuzzyScorer.score(query: "ode", candidate: "xoxdxe")!
        #expect(consecutive > gapped)
    }

    @Test func caseInsensitive() {
        #expect(FuzzyScorer.score(query: "XCODE", candidate: "xcode") == FuzzyScorer.score(query: "xcode", candidate: "Xcode"))
    }

    @Test func normalizedIsBounded() {
        for (q, c) in [("a", "a"), ("zz", "zz zz zz"), ("q", "Some Q Thing"), ("abc", "a-b-c")] {
            let n = FuzzyScorer.normalized(query: q, candidate: c)!
            #expect(n >= 0 && n <= 100)
        }
    }

    @Test func initialsBeatSubstringRun() {
        let initials = FuzzyScorer.score(query: "ode", candidate: "Open Data Explorer")!
        let substring = FuzzyScorer.score(query: "ode", candidate: "Xcode")!
        #expect(initials > substring)
    }

    @Test func xcodeVersusVSCodeWithinBand() {
        let xcode = FuzzyScorer.normalized(query: "code", candidate: "Xcode")!
        let vscode = FuzzyScorer.normalized(query: "code", candidate: "Visual Studio Code")!
        #expect(abs(xcode - vscode) < SearchEngine.frecencyCap)
    }
}
