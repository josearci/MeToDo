import AppKit
import Observation
import MeToDoCore

/// Keeps MeToDo current: checks the GitHub repo's latest release (at launch and every 6 hours),
/// downloads a newer one in the background, and installs it when the user clicks Restart.
/// Nothing about the user's tasks is sent anywhere; it's a plain GET of the public release info.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(version: String)
        case ready(version: String)
        case failed(String)
    }

    private(set) var state: State = .idle
    /// "1.0.42", or "dev" for local builds made outside a git checkout.
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    @ObservationIgnored private let repo = Bundle.main.object(forInfoDictionaryKey: "MeToDoUpdateRepo") as? String
    @ObservationIgnored private let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    @ObservationIgnored private var downloadedApp: URL?
    @ObservationIgnored private var timer: Timer?

    var canUpdate: Bool { repo != nil }

    func start() {
        guard canUpdate else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func check() async {
        switch state {
        case .checking, .downloading, .ready: return
        default: break
        }
        guard let repo, let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        state = .checking
        var request = URLRequest(url: api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            state = .idle   // offline or rate-limited: try again next time, quietly
            return
        }
        guard let release = Updates.newerRelease(in: data, than: currentBuild) else {
            state = .upToDate
            return
        }
        state = .downloading(version: release.version)
        do {
            downloadedApp = try await download(release)
            state = .ready(version: release.version)
        } catch {
            state = .failed("Couldn't download \(release.version): \(error.localizedDescription)")
        }
    }

    /// Downloads and unpacks the release zip; returns the MeToDo.app inside it.
    private func download(_ release: ReleaseInfo) async throws -> URL {
        let (zip, _) = try await URLSession.shared.download(from: release.downloadURL)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MeToDo-update-\(release.build)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        let app = folder.appendingPathComponent("MeToDo.app")
        guard unzip.terminationStatus == 0, Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return app
    }

    /// Swaps the installed app for the downloaded one and relaunches. Tasks are saved first.
    func installAndRelaunch(saving store: Store) {
        guard let downloadedApp else { return }
        store.saveNow()
        let installed = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(installed, withItemAt: downloadedApp)
        } catch {
            state = .failed("Couldn't replace \(installed.path): \(error.localizedDescription)")
            return
        }
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", installed.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
