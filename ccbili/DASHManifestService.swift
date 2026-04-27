import Foundation

enum DASHManifestService {
    static func manifestURL(for source: PlayableVideoSource) throws -> URL {
        guard let audioURL = source.audioURL else {
            return source.url
        }

        let directory = FileManager.default.temporaryDirectory.appending(
            path: "BilibiliDASH",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appending(path: "\(source.bvid)-\(source.cid)-\(source.quality ?? 0).mpd")
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" minBufferTime="PT1.5S">
          <Period id="0" start="PT0S">
            <AdaptationSet id="1" contentType="video" mimeType="video/mp4" segmentAlignment="true" startWithSAP="1">
              <Representation id="video" bandwidth="0">
                <BaseURL>\(escapedXML(source.url.absoluteString))</BaseURL>
              </Representation>
            </AdaptationSet>
            <AdaptationSet id="2" contentType="audio" mimeType="audio/mp4" segmentAlignment="true" startWithSAP="1">
              <Representation id="audio" bandwidth="0">
                <BaseURL>\(escapedXML(audioURL.absoluteString))</BaseURL>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """
        try manifest.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func escapedXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
