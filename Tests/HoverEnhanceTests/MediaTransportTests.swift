import AVFoundation
import Foundation
import Testing
@testable import HoverEnhance

@MainActor
struct MediaTransportTests {
    private func song() throws -> URL {
        try #require(Bundle.module.url(forResource: "untagged", withExtension: "mp3", subdirectory: "Fixtures"))
    }

    /// Waits up to two seconds for the player's callbacks to arrive.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test func playBeforeThereIsAPlayerStartsOne() {
        var started = false
        let transport = MediaTransport(duration: 60) { started = true }
        transport.toggle()
        #expect(started)
        // Nothing to move through yet.
        transport.scrub(to: 0.5, done: true)
        #expect(transport.elapsed == 0 && !transport.isAttached)
    }

    @Test func readsTheLengthTheDetailsLeftOut() async throws {
        let transport = MediaTransport(duration: nil)
        transport.loadDuration(of: try song())
        #expect(await eventually { transport.duration != nil })
        #expect(abs((transport.duration ?? 0) - 1) < 0.2)
    }

    @Test func movesAndFollowsItsPlayer() async throws {
        let player = AVPlayer(url: try song())
        let transport = MediaTransport(duration: 1)
        transport.attach(player)
        #expect(transport.isAttached && !transport.isPlaying)

        transport.scrub(to: 0.5, done: true)
        #expect(transport.elapsed == 0.5)
        #expect(await eventually { abs(player.currentTime().seconds - 0.5) < 0.05 })

        // Muted first, so the test makes no sound.
        transport.toggleMute()
        #expect(await eventually { transport.isMuted })
        transport.toggle()
        #expect(await eventually { transport.isPlaying })
        transport.toggle()
        #expect(await eventually { !transport.isPlaying })

        transport.detach()
        #expect(!transport.isAttached)
    }

    @Test func clockReadsLikeAPlayer() {
        #expect(VideoPlayback.clock(0) == "0:00")
        #expect(VideoPlayback.clock(83.9) == "1:23")
        #expect(VideoPlayback.clock(3723) == "1:02:03")
    }
}
