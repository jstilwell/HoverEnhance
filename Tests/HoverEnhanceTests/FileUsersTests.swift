import Foundation
import Testing
@testable import HoverEnhance

struct FileUsersTests {
    private func tempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "HoverEnhanceTests-\(UUID().uuidString).txt")
        try Data("held".utf8).write(to: url)
        return url
    }

    /// `sleep` with `file` as its standard input, so it holds the file open until it ends.
    private func holder(of file: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sleep")
        process.arguments = ["30"]
        process.standardInput = try FileHandle(forReadingFrom: file)
        try process.run()
        return process
    }

    @Test func findsAProcessHoldingAFileOpen() async throws {
        let file = try tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let sleeper = try holder(of: file)
        defer { sleeper.terminate() }

        let users = await FileUsers.find(file)
        let user = try #require(users.first { $0.pid == sleeper.processIdentifier })
        #expect(user.name == "sleep")
        #expect(user.use == .open)
        #expect(user.executable == "/bin/sleep")
        #expect(!users.contains { $0.pid == getpid() })
    }

    @Test func commandsGoByTheNameTheyWereStartedUnder() throws {
        // `exec -a` starts sleep under another name, as Claude Code's versioned executable runs as "claude".
        for (argument0, expected) in [("fancyname", "fancyname"), ("-zsh", "zsh"), ("-/bin/zsh", "zsh"), ("/opt/tools/bin/thing", "thing")] {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/bash")
            process.arguments = ["-c", "exec -a '\(argument0)' /bin/sleep 10"]
            try process.run()
            defer { process.terminate() }
            var name: String?
            for _ in 0..<50 {
                name = FileUsers.commandName(of: process.processIdentifier)
                if name == expected { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
            #expect(name == expected)
            #expect(FileUsers.name(of: process.processIdentifier) == expected)
        }
    }

    @Test func findsAWorkingFolder() async {
        let here = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        let users = await FileUsers.find(here, excluding: 0)
        #expect(users.first { $0.pid == getpid() }?.use == .workingFolder)
    }

    @Test func findsARunningApp() async {
        let users = await FileUsers.find(URL(filePath: "/System/Library/CoreServices/Finder.app", directoryHint: .isDirectory))
        #expect(users.contains { $0.name == "Finder" && $0.use == .running })
    }

    @Test func nothingUsesAFreshFile() async throws {
        let file = try tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(await FileUsers.find(file).isEmpty)
    }

    @MainActor
    @Test func quittingTakesTwoClicks() async throws {
        let file = try tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let sleeper = try holder(of: file)
        defer { if sleeper.isRunning { sleeper.terminate() } }

        let card = FileCard(url: file, details: FileDetails(), options: FileCardOptions())
        await card.loadUsers()
        let user = try #require(card.users?.first { $0.pid == sleeper.processIdentifier })

        card.quitClicked(user)
        #expect(card.quitStates[user.pid] == .confirming)
        #expect(FileUsers.isRunning(user.pid))

        card.quitClicked(user)
        for _ in 0..<40 where card.quitStates[user.pid] != .quit {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(card.quitStates[user.pid] == .quit)
        #expect(!FileUsers.isRunning(user.pid))
    }

    @MainActor
    @Test func usersAreLeftAloneWhenTurnedOff() async throws {
        let card = FileCard(url: try tempFile(), details: FileDetails(), options: FileCardOptions(hidden: [.users]))
        defer { try? FileManager.default.removeItem(at: card.url) }
        await card.loadUsers()
        #expect(card.users == nil)
    }
}
