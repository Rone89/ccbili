import Foundation

final class HLSPlaybackDiagnostics {
    static let shared = HLSPlaybackDiagnostics()

    private let lock = NSLock()
    private var manifestText = "manifest=-"
    private var proxyText = "proxy=-"
    private var requestCount = 0
    private var playlistCount = 0

    private init() {}

    func reset() {
        lock.lock()
        manifestText = "manifest=-"
        proxyText = "proxy=-"
        requestCount = 0
        playlistCount = 0
        lock.unlock()
    }

    func recordPlaylist(path: String, status: Int) {
        lock.lock()
        playlistCount += 1
        let shortPath = path.split(separator: "?").first.map(String.init) ?? path
        proxyText = "hls#\(playlistCount) \(status) path=\(shortPath) \(proxyText)"
        lock.unlock()
    }

    func recordManifest(videoSegments: Int, audioSegments: Int, targetDuration: Int, videoIndex: String?, audioIndex: String?) {
        lock.lock()
        manifestText = "manifest=v\(videoSegments)/a\(audioSegments) target=\(targetDuration) vi=\(videoIndex ?? "nil") ai=\(audioIndex ?? "nil")"
        lock.unlock()
    }

    func recordProxy(path: String, requestRange: String?, status: Int, responseRange: String?, bytes: Int) {
        lock.lock()
        requestCount += 1
        let shortPath = path.split(separator: "?").first.map(String.init) ?? path
        proxyText = "proxy#\(requestCount) \(status) bytes=\(bytes) req=\(requestRange ?? "-") res=\(responseRange ?? "-") path=\(shortPath)"
        lock.unlock()
    }

    func recordProxyError(path: String, requestRange: String?, message: String) {
        lock.lock()
        requestCount += 1
        let shortPath = path.split(separator: "?").first.map(String.init) ?? path
        proxyText = "proxy#\(requestCount) err=\(message) req=\(requestRange ?? "-") path=\(shortPath)"
        lock.unlock()
    }

    func recordPlayerStatus(_ status: String) {
        lock.lock()
        proxyText = "player=\(status) \(proxyText)"
        lock.unlock()
    }

    var summary: String {
        lock.lock()
        let value = "\(manifestText) \(proxyText)"
        lock.unlock()
        return value
    }
}
