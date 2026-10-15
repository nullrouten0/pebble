// Installing the bundled default texture pack into the packs folder. The app
// calls this at launch (ResourcePacks.swift); it lives in the core so pebsmoke
// can check the decision and the copy against a scratch folder.

import Foundation

public enum PackInstall: Equatable {
    case kept            // already this release, untouched since
    case stamped         // installed before the stamps existed; now stamped
    case updated         // replaced with this build's release
    case restored        // was missing; copied in
    case failed(String)  // the copy failed; any old pack stays in place
}

/// Copy `bundled` into `dir` as `file` when it's missing, a different release,
/// or changed since it was installed. Two stamps beside it record what was
/// installed: `.default-pack-release` holds the release (builds 1.6.8 to 1.6.18
/// read only this one) and `.default-pack-size` the installed size, so a pack
/// replaced behind the stamp's back (by an older build, or a restore) is caught.
public func installBundledPack(bundled: URL, into dir: URL, file: String, release: String) -> PackInstall {
    let fm = FileManager.default
    let dest = dir.appendingPathComponent(file)
    let releaseStamp = dir.appendingPathComponent(".default-pack-release")
    let sizeStamp = dir.appendingPathComponent(".default-pack-size")
    func read(_ u: URL) -> String? {
        (try? String(contentsOf: u, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func size(_ u: URL) -> Int64? { (try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value }
    func stamp() {
        try? release.write(to: releaseStamp, atomically: true, encoding: .utf8)
        if let n = size(dest) { try? String(n).write(to: sizeStamp, atomically: true, encoding: .utf8) }
    }
    let installed = size(dest)
    if let installed, read(releaseStamp) ?? release == release {
        if let recorded = read(sizeStamp).flatMap({ Int64($0) }) {
            if recorded == installed && read(releaseStamp) == release { return .kept }
        } else if installed == size(bundled) {
            // stamped by 1.6.8–1.6.18 (no size yet), or never stamped: the same
            // size as the bundled zip means it's this release
            stamp()
            return .stamped
        }
    }
    // copy beside it first, then swap in, so a failed copy leaves the old pack in place
    let tmp = dir.appendingPathComponent(".\(file).partial")
    try? fm.removeItem(at: tmp)
    do {
        try fm.copyItem(at: bundled, to: tmp)
        if installed != nil {
            _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            stamp()
            return .updated
        }
        try fm.moveItem(at: tmp, to: dest)
        stamp()
        return .restored
    } catch {
        try? fm.removeItem(at: tmp)
        return .failed(error.localizedDescription)
    }
}
