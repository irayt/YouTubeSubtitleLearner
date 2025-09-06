import Foundation

func fileSizeString(_ url: URL) -> String? {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber { return byteCount(Int64(truncating: size)) }
    } catch {}
    return nil
}

func byteCount(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

