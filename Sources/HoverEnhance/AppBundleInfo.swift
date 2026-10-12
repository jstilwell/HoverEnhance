import Foundation
import Security
import os

/// About an app or other bundle: its version, identity, the Macs it runs on, and who signed it.
struct AppBundleInfo: Sendable, Equatable {
    /// "26.0 (21622.1.22)".
    var version: String?
    var bundleID: String?
    /// "Apple silicon", "Intel".
    var architectures: [String] = []
    /// "macOS 14.0".
    var minimumSystem: String?

    /// Nil unless `url` is a bundle with an identifier. Reads Info.plist and the executable's header
    /// directly; `Bundle` would cache them for as long as HoverEnhance runs, so an updated app would
    /// keep showing its old version.
    static func read(_ url: URL) -> AppBundleInfo? {
        guard let info = CFBundleCopyInfoDictionaryInDirectory(url as CFURL) as? [String: Any],
              let bundleID = info[kCFBundleIdentifierKey as String] as? String else { return nil }
        let short = info["CFBundleShortVersionString"] as? String
        let build = info[kCFBundleVersionKey as String] as? String
        let version = switch (short, build) {
        case let (short?, build?) where short != build: "\(short) (\(build))"
        case let (short?, _): short
        case let (nil, build): build
        }
        let architectures = (CFBundleCopyExecutableArchitecturesForURL(url as CFURL) as? [NSNumber] ?? []).compactMap { number -> String? in
            switch number.intValue {
            case kCFBundleExecutableArchitectureARM64: "Apple silicon"
            case kCFBundleExecutableArchitectureX86_64, kCFBundleExecutableArchitectureI386: "Intel"
            case kCFBundleExecutableArchitecturePPC, kCFBundleExecutableArchitecturePPC64: "PowerPC"
            default: nil
            }
        }
        return AppBundleInfo(version: version, bundleID: bundleID, architectures: architectures.uniqued(),
                             minimumSystem: (info["LSMinimumSystemVersion"] as? String).map { "macOS " + $0 })
    }

    /// Who signed the code at `url`: "Apple", "Mac App Store", a Developer ID ("Developer ID
    /// Application: Jane Doe (ABCDE12345)"), "Ad hoc, no developer", or "Not signed", and whether its
    /// files are still as signed. Checking every file takes seconds for a big app, so that waits at most
    /// `timeout`; one that takes longer says so, and the answer is there on a later hover.
    static func signature(of url: URL, timeout: TimeInterval = 4) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        let quick = SecCSFlags(rawValue: kSecCSDoNotValidateExecutable | kSecCSDoNotValidateResources)
        let validity = SecStaticCodeCheckValidity(code, quick, nil)
        if validity == errSecCSUnsigned { return "Not signed" }

        func satisfies(_ requirement: String) -> Bool {
            var compiled: SecRequirement?
            guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess else { return false }
            return SecStaticCodeCheckValidity(code, quick, compiled) == errSecSuccess
        }
        var information: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate]

        let signer: String
        if certificates?.isEmpty != false {
            signer = "Ad hoc, no developer"
        } else if satisfies("anchor apple") {
            signer = "Apple"
        } else if satisfies("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists") {
            signer = "Mac App Store"
        } else {
            signer = certificates.flatMap { $0.first }.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "Unknown developer"
        }
        guard validity == errSecSuccess else { return signer + " · signature is broken" }
        switch FileSeals.check(url, timeout: timeout) {
        case .intact?: return signer
        case .broken?: return signer + " · files changed since signing"
        case nil: return signer + " · files not checked"
        }
    }

    /// Whether every file an app's signature covers, nested code included, is as signed. Callers asking
    /// about the same app share one check, and a check that outlasts its caller's wait goes on, since the
    /// system can't stop it; answers are kept a few minutes, for the next hover. (A file changed deep in an
    /// app doesn't change the app's own date, so they aren't kept longer.)
    enum FileSeals {
        enum Seal: Sendable { case intact, broken }

        private struct State {
            var known: [String: (seal: Seal, time: Date)] = [:]
            var running: [String: DispatchGroup] = [:]
        }
        private static let state = OSAllocatedUnfairLock(initialState: State())
        private static let lifetime: TimeInterval = 5 * 60

        static func check(_ url: URL, timeout: TimeInterval) -> Seal? {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let key = "\(url.path(percentEncoded: false))@\(modified?.timeIntervalSince1970 ?? 0)"
            let running = state.withLock { current -> DispatchGroup? in
                current.known = current.known.filter { Date().timeIntervalSince($0.value.time) < lifetime }
                if current.known[key] != nil { return nil }
                if let group = current.running[key] { return group }
                let group = DispatchGroup()
                group.enter()
                current.running[key] = group
                DispatchQueue.global(qos: .utility).async {
                    let seal = fullCheck(url)
                    state.withLock {
                        $0.known[key] = (seal, Date())
                        $0.running[key] = nil
                    }
                    group.leave()
                }
                return group
            }
            if let running, running.wait(timeout: .now() + timeout) == .timedOut { return nil }
            return state.withLock { $0.known[key]?.seal }
        }

        private static func fullCheck(_ url: URL) -> Seal {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return .broken }
            return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckNestedCode), nil) == errSecSuccess ? .intact : .broken
        }
    }
}
