import Foundation
import AVFoundation
import UIKit
import libmpv

final class MPVPlayerController {
    private var mpv: OpaquePointer?
    private var isInitialized = false

    init() {
        mpv = mpv_create()
        guard let mpv else { return }
        mpv_request_log_messages(mpv, "warn")
        setOption("vo", value: "avfoundation")
        setOption("keepaspect", value: "yes")
        setOption("input-default-bindings", value: "no")
        setOption("input-vo-keyboard", value: "no")
        setOption("hwdec", value: "auto-safe")
        setOption("gpu-api", value: "opengl")
        setOption("profile", value: "fast")
        setOption("cache", value: "yes")
        setOption("demuxer-max-bytes", value: "128MiB")
        setOption("demuxer-readahead-secs", value: "8")
        setOption("force-seekable", value: "yes")
        setOption("audio-file-auto", value: "no")
        setOption("audio-pitch-correction", value: "no")
    }

    deinit {
        stop()
        if let mpv {
            mpv_terminate_destroy(mpv)
        }
    }

    func attach(to view: UIView) {
        guard !isInitialized else { return }
        var viewPointer = Int64(Int(bitPattern: Unmanaged.passUnretained(view).toOpaque()))
        setOption("wid", format: MPV_FORMAT_INT64, value: &viewPointer)
        if let mpv, mpv_initialize(mpv) >= 0 {
            isInitialized = true
        }
    }

    func play(source: PlayableVideoSource) {
        guard isInitialized else { return }
        configureAudioSession()
        configureHeaders(source.headers)
        if let audioURL = source.audioURL {
            command(["loadfile", source.url.absoluteString, "replace"])
            command(["audio-add", audioURL.absoluteString, "select", "dash-audio"])
        } else {
            command(["loadfile", source.url.absoluteString, "replace"])
        }
        command(["set", "pause", "no"])
    }

    func togglePlay() {
        command(["cycle", "pause"])
    }

    func stop() {
        command(["stop"])
    }

    private func configureHeaders(_ headers: [String: String]) {
        var enrichedHeaders = headers
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        if let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty {
            enrichedHeaders["Cookie"] = cookieHeader
        }
        enrichedHeaders["Accept"] = "*/*"
        let headerString = enrichedHeaders
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        setOption("http-header-fields", value: headerString)
        if let referer = enrichedHeaders["Referer"] {
            setOption("referrer", value: referer)
        }
        if let userAgent = enrichedHeaders["User-Agent"] {
            setOption("user-agent", value: userAgent)
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure mpv audio session: \(error.localizedDescription)")
        }
    }

    private func setOption(_ name: String, value: String) {
        guard let mpv else { return }
        mpv_set_option_string(mpv, name, value)
    }

    private func setOption(_ name: String, format: mpv_format, value: UnsafeMutableRawPointer) {
        guard let mpv else { return }
        mpv_set_option(mpv, name, format, value)
    }

    private func command(_ args: [String]) {
        guard let mpv else { return }
        args.withCStringArray { argv in
            _ = mpv_command(mpv, argv)
        }
    }

}

private extension Array where Element == String {
    func withCStringArray<Result>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) -> Result) -> Result {
        var cStrings = map { strdup($0) }
        defer {
            for pointer in cStrings {
                free(pointer)
            }
        }
        cStrings.append(nil)
        var constPointers = cStrings.map { UnsafePointer<CChar>($0) }
        return constPointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }
}

