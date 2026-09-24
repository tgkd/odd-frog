import Foundation
import Testing
import ClipboardPluginCore
import OddFrogPluginAPI

struct ClipboardArchiveTests {
    private func temp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("odd-frog-clip-\(UUID().uuidString)")
    }
    private var now: Date { Date(timeIntervalSince1970: 1_700_000_000) }
    private func limits(count: Int = 50) -> ClipboardLimits {
        ClipboardLimits(count: count, captureImages: true)
    }
    private func png() -> Data { Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }
    private func image(png: Data = Data([0x89, 0x50, 0x4E, 0x47])) -> ProcessedImage {
        ProcessedImage(png: png, thumbnail: png, width: 2, height: 2)
    }

    @Test func claimOwnsTheNewestGenerationOnly() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let one = archive.nextGeneration()
        let two = archive.nextGeneration()
        #expect(try await archive.claim(generation: one, directory: dir, limits: limits()))
        #expect(try await archive.claim(generation: two, directory: dir, limits: limits()))
        #expect(!(try await archive.claim(generation: one, directory: dir, limits: limits())))
        #expect(try await archive.record(.text("hello"), image: nil, generation: two, now: now))
        #expect(await archive.entries(generation: two).count == 1)
        #expect(await archive.entries(generation: one).isEmpty)
    }

    @Test func releaseOnlyClearsTheOwningGeneration() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let one = archive.nextGeneration()
        let two = archive.nextGeneration()
        #expect(try await archive.claim(generation: two, directory: dir, limits: limits()))
        await archive.release(generation: one)
        #expect(try await archive.record(.text("kept"), image: nil, generation: two, now: now))
        await archive.release(generation: two)
        #expect(await archive.entries(generation: two).isEmpty)
    }

    @Test func duplicatesMoveToTheFrontInsteadOfDuplicating() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: limits())
        _ = try await archive.record(.text("alpha"), image: nil, generation: gen, now: now)
        _ = try await archive.record(.text("beta"), image: nil, generation: gen, now: now)
        let alpha = try #require(await archive.entries(generation: gen).first { $0.text == "alpha" })
        let later = now.addingTimeInterval(1)
        _ = try await archive.record(.text("alpha"), image: nil, generation: gen, now: later)
        let entries = await archive.entries(generation: gen)
        #expect(entries.count == 2)
        #expect(entries.first?.id == alpha.id)
        #expect(entries.first?.copied == later)
    }

    @Test func recordEnforcesTheEntryLimit() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: limits(count: 2))
        _ = try await archive.record(.text("one"), image: nil, generation: gen, now: now)
        _ = try await archive.record(.text("two"), image: nil, generation: gen, now: now)
        _ = try await archive.record(.text("three"), image: nil, generation: gen, now: now)
        #expect(await archive.entries(generation: gen).map(\.text) == ["three", "two"])
    }

    @Test func recordRejectsImagesWhenDisabledOrMissing() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: ClipboardLimits(count: 50, captureImages: false))
        #expect(!(try await archive.record(.image(data: png(), type: .png), image: image(), generation: gen, now: now)))
        try await archive.configure(generation: gen, limits: limits())
        #expect(!(try await archive.record(.image(data: png(), type: .png), image: nil, generation: gen, now: now)))
    }

    @Test func imageEntriesPersistFilesAndDeleteCleansUp() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: limits())
        let pngData = png()
        _ = try await archive.record(.image(data: pngData, type: .png),
                                     image: ProcessedImage(png: pngData, thumbnail: pngData, width: 4, height: 3),
                                     generation: gen, now: now)
        let entry = try #require(await archive.entries(generation: gen).first)
        #expect(entry.kind == .image)
        #expect(entry.width == 4)
        #expect(entry.height == 3)
        let images = dir.appendingPathComponent("images", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: images.appendingPathComponent("\(entry.id).png").path))
        #expect(FileManager.default.fileExists(atPath: images.appendingPathComponent("\(entry.id)-thumb.png").path))
        #expect(await archive.imageData(generation: gen, id: entry.id) == pngData)
        try await archive.delete(generation: gen, id: entry.id)
        #expect(await archive.entries(generation: gen).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: images.appendingPathComponent("\(entry.id).png").path))
        #expect(!FileManager.default.fileExists(atPath: images.appendingPathComponent("\(entry.id)-thumb.png").path))
    }

    @Test func touchMovesAnEntryToTheFront() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: limits())
        _ = try await archive.record(.text("first"), image: nil, generation: gen, now: now)
        _ = try await archive.record(.text("second"), image: nil, generation: gen, now: now)
        let last = try #require(await archive.entries(generation: gen).last)
        try await archive.touch(generation: gen, id: last.id, now: now.addingTimeInterval(1))
        let entries = await archive.entries(generation: gen)
        #expect(entries.count == 2)
        #expect(entries.first?.id == last.id)
    }

    @Test func clearRemovesAllEntriesAndReportsTheCount() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: limits())
        _ = try await archive.record(.text("a"), image: nil, generation: gen, now: now)
        _ = try await archive.record(.text("b"), image: nil, generation: gen, now: now)
        #expect(try await archive.clear(generation: gen) == 2)
        #expect(await archive.entries(generation: gen).isEmpty)
    }

    @Test func configureTrimsImmediately() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: limits(count: 5))
        for i in 0..<5 { _ = try await archive.record(.text("t\(i)"), image: nil, generation: gen, now: now) }
        #expect(await archive.entries(generation: gen).count == 5)
        try await archive.configure(generation: gen, limits: limits(count: 2))
        #expect(await archive.entries(generation: gen).count == 2)
    }

    @Test func claimRefusesACorruptIndex() async throws {
        let archive = ClipboardArchive()
        let dir = temp()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not json".utf8).write(to: dir.appendingPathComponent("index.json"))
        let gen = archive.nextGeneration()
        await #expect(throws: RPCError.self) {
            try await archive.claim(generation: gen, directory: dir, limits: limits())
        }
    }

    @Test func claimDropsImageEntriesWhoseFilesAreMissing() async throws {
        let archive = ClipboardArchive()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let gen = archive.nextGeneration()
        _ = try await archive.claim(generation: gen, directory: dir, limits: limits())
        let pngData = png()
        _ = try await archive.record(.image(data: pngData, type: .png),
                                     image: ProcessedImage(png: pngData, thumbnail: pngData, width: 1, height: 1),
                                     generation: gen, now: now)
        _ = try await archive.record(.text("kept"), image: nil, generation: gen, now: now)
        let image = try #require(await archive.entries(generation: gen).first { $0.kind == .image })
        try FileManager.default.removeItem(at: dir.appendingPathComponent("images").appendingPathComponent("\(image.id).png"))
        let fresh = ClipboardArchive()
        let gen2 = fresh.nextGeneration()
        #expect(try await fresh.claim(generation: gen2, directory: dir, limits: limits()))
        let entries = await fresh.entries(generation: gen2)
        #expect(!entries.contains { $0.id == image.id })
        #expect(entries.map(\.text) == ["kept"])
    }

    @Test func thumbnailPathPointsInsideTheImagesDirectory() {
        let dir = URL(fileURLWithPath: "/tmp/x")
        #expect(ClipboardArchive.thumbnailPath(in: dir, id: "abc") == "/tmp/x/images/abc-thumb.png")
    }
}
