import AppKit

/// What the commands that draw to files share: reading the output path and
/// reporting failure on standard error.
enum RenderCommand {
    /// The path after `flag`, or nil after printing `usage`.
    static func outputURL(after flag: String, in arguments: [String], usage: String) -> URL? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            _ = fail("usage: Barbarian \(flag) \(usage)")
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) -> Int32 {
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return fail("Rendering failed.") }
        do {
            try png.write(to: url)
        } catch {
            return fail("Could not write \(url.path): \(error.localizedDescription)")
        }
        return 0
    }

    static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }
}
