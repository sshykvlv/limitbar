import AppKit
import CryptoKit

// Self-updater, ported from Lidless's checkUpdates()/downloadUpdate() (~/dev/mac-keep-awake/main.swift),
// using the SAFE "verify-then-reveal" model: never auto-swaps the running app bundle and never
// relaunches. It downloads the release zip, optionally verifies its SHA-256 against a published
// SHA256SUMS asset, unzips it, then — as a mandatory, non-optional barrier — verifies the unzipped
// .app has a valid code signature AND was signed by LimitBar's own Developer ID Team ID. Only then
// does it reveal the verified .app in Finder for the user to drag into /Applications themselves.
// Dependency-free: URLSession for network, FileManager + /usr/bin/ditto for unzip, Process for
// codesign, CryptoKit for hashing.
enum Updates {
    private static let repo = "https://github.com/sshykvlv/limitbar"
    private static let expectedTeamID = "J2Q78NFXZX"
    private static let expectedAssetName = "LimitBar.zip"

    private static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    static func check(announce: Bool) {
        guard let api = URL(string: "https://api.github.com/repos/sshykvlv/limitbar/releases/latest") else { return }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if announce { DispatchQueue.main.async { alert("Couldn’t check for updates", "Please try again later.") } }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isNewer(latest, than: currentVersion) else {
                if announce {
                    DispatchQueue.main.async { alert("You’re up to date", "LimitBar v\(currentVersion) is the latest version.") }
                }
                return
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            func assetURL(_ match: (String) -> Bool) -> URL? {
                for a in assets {
                    if let name = a["name"] as? String, match(name),
                       let s = a["browser_download_url"] as? String, let u = URL(string: s) { return u }
                }
                return nil
            }
            guard let zip = assetURL({ $0 == expectedAssetName }) ?? assetURL({ $0.hasSuffix(".zip") }) else {
                if announce { DispatchQueue.main.async { alert("Update failed", "Couldn’t find a downloadable release asset.") } }
                return
            }
            let sums = assetURL { $0 == "SHA256SUMS" }
            downloadAndVerify(zip, sums: sums, version: latest, announce: announce)
        }.resume()
    }

    // Componentwise numeric comparison — matches Lidless's isNewer(_:than:). Internal (not private)
    // so it's unit-testable via @testable import LimitBar.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<Swift.max(x.count, y.count) {
            let xi = i < x.count ? x[i] : 0, yi = i < y.count ? y[i] : 0
            if xi != yi { return xi > yi }
        }
        return false
    }

    private static func downloadAndVerify(_ zip: URL, sums: URL?, version: String, announce: Bool) {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let zipPath = downloads.appendingPathComponent("LimitBar-v\(safeVersion(version)).zip")
        let appPath = downloads.appendingPathComponent("LimitBar.app")

        URLSession.shared.downloadTask(with: zip) { tmp, _, error in
            func fail(_ title: String, _ message: String) {
                DispatchQueue.main.async {
                    alert(title, message)
                    openReleasesPage()
                }
            }
            guard let tmp, error == nil else {
                fail("Download failed", "Opening the releases page instead.")
                return
            }

            // Save the downloaded archive to Downloads.
            try? FileManager.default.removeItem(at: zipPath)
            guard (try? FileManager.default.moveItem(at: tmp, to: zipPath)) != nil else {
                fail("Download failed", "Couldn’t save the update.")
                return
            }

            // 1) Integrity (optional): SHA-256 against the published SHA256SUMS asset, if present.
            if let sums {
                let sumsText = fetchText(sums, timeout: 15) ?? ""
                guard let expected = expectedHash(in: sumsText, for: expectedAssetName),
                      let actual = sha256(ofFileAt: zipPath) else {
                    try? FileManager.default.removeItem(at: zipPath)
                    fail("Update verification failed", "Couldn’t verify the download’s checksum. Grab it from the releases page.")
                    return
                }
                guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                    try? FileManager.default.removeItem(at: zipPath)
                    fail("Update verification failed", "Checksum mismatch — the download was not trusted and has been removed.")
                    return
                }
            }

            // Unzip.
            try? FileManager.default.removeItem(at: appPath)
            _ = run("/usr/bin/ditto", ["-x", "-k", zipPath.path, downloads.path])
            guard FileManager.default.fileExists(atPath: appPath.path) else {
                try? FileManager.default.removeItem(at: zipPath)
                fail("Update failed", "The downloaded archive looked malformed.")
                return
            }

            // 2) Authenticity (mandatory, critical barrier): valid Developer ID signature +
            //    expected Team ID. This is the main supply-chain gate — it can't be forged
            //    without the private signing key, unlike the release zip contents or the API JSON.
            guard codesignValid(appPath), teamID(of: appPath) == expectedTeamID else {
                try? FileManager.default.removeItem(at: appPath)
                try? FileManager.default.removeItem(at: zipPath)
                fail("Update rejected",
                     "The downloaded app isn’t signed by LimitBar’s Developer ID, so it was removed. Download manually from the releases page.")
                return
            }

            // Verified → reveal the ready .app, never auto-swap the running bundle or relaunch.
            try? FileManager.default.removeItem(at: zipPath)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([appPath])
                if announce {
                    alert("Update verified", "Drag LimitBar.app to /Applications to install.")
                }
            }
        }.resume()
    }

    // Name from tag_name is untrusted (API/MITM) — keep only safe characters to rule out
    // path traversal (`v../../…`) when building file paths.
    private static func safeVersion(_ v: String) -> String {
        let s = v.filter { ($0.isASCII && $0.isLetter) || $0.isNumber || $0 == "." || $0 == "-" }
        return s.isEmpty ? "update" : s
    }

    private static func openReleasesPage() {
        if let url = URL(string: "\(repo)/releases") { NSWorkspace.shared.open(url) }
    }

    private static func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    // MARK: - Subprocess helpers

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        // Read before waitUntilExit: otherwise large output fills the pipe buffer, the
        // process blocks on write, and wait hangs forever (classic deadlock).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // Run with exit code + stdout + stderr (codesign writes metadata to stderr).
    @discardableResult
    private static func runStatus(_ path: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (-1, "", "") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(data: od, encoding: .utf8) ?? "",
                String(data: ed, encoding: .utf8) ?? "")
    }

    // SHA-256 of a file, as lowercase hex.
    private static func sha256(ofFileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // Extracts the expected hash from SHA256SUMS text (lines like "<hash>␣␣<filename>").
    private static func expectedHash(in sumsText: String, for filename: String) -> String? {
        for line in sumsText.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
            if cols.count >= 2, cols.last.map(String.init) == filename { return String(cols[0]) }
        }
        return nil
    }

    // Code signature validity (strict bundle check, including nested code).
    private static func codesignValid(_ app: URL) -> Bool {
        runStatus("/usr/bin/codesign", ["--verify", "--strict", app.path]).status == 0
    }

    // Team ID from the signature: `codesign -dvvv` prints "TeamIdentifier=XX…" to stderr.
    private static func teamID(of app: URL) -> String? {
        let r = runStatus("/usr/bin/codesign", ["-dvvv", app.path])
        for line in (r.err + "\n" + r.out).split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            if line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count))
            }
        }
        return nil
    }

    // Fetch a small text asset (SHA256SUMS) with a hard timeout — don't block the
    // background download-task callback forever if the CDN stalls.
    private static func fetchText(_ url: URL, timeout: TimeInterval) -> String? {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data { result = String(data: data, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 2)
        return result
    }
}
