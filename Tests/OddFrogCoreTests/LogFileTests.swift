import Foundation
import Testing
@testable import OddFrogCore

struct LogFileTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("odd-frog-logfile-\(UUID().uuidString).log")
    }

    private func contents(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test func createsAMissingFile() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        LogFile(url: url, limit: 100).append("first\n")
        #expect(contents(url) == "first\n")
        LogFile(url: url, limit: 100).append("second\n")
        #expect(contents(url) == "first\nsecond\n")
    }

    @Test func staysUnderTheLimitAfterManyAppends() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = LogFile(url: url, limit: 200)
        for n in 0..<500 {
            log.append("line number \(n)\n")
            let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            #expect(size <= 200)
        }
    }

    @Test func cutKeepsNewestWholeLinesInOrder() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = LogFile(url: url, limit: 100)
        for n in 0..<40 { log.append("entry-\(String(format: "%03d", n))\n") }
        let lines = contents(url).split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        #expect(!lines.isEmpty)
        #expect(lines.first != "entry-000")
        #expect(lines.allSatisfy { $0.hasPrefix("entry-") && $0.count == 9 })
        #expect(lines.last == "entry-039")
        let numbers = lines.compactMap { Int($0.dropFirst(6)) }
        #expect(numbers == Array(numbers[0]...39))
        #expect(contents(url).hasSuffix("\n"))
    }
}
