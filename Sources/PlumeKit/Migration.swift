import Foundation

/// French names written by versions up to 1.0.1 move to their English name the first time
/// they are used. Old and new names are siblings, so the move is a single atomic rename.
public enum Migration {
    /// Path to use for a file or folder renamed in 1.0.2: moves `old` to `new` once.
    public static func resolve(old: URL, new: URL, fileManager: FileManager = .default) -> URL {
        guard !fileManager.fileExists(atPath: new.path), fileManager.fileExists(atPath: old.path) else { return new }
        do {
            try fileManager.moveItem(at: old, to: new)
            return new
        } catch {
            // Another process moved it first, or the folder is read-only: read whatever is there.
            return fileManager.fileExists(atPath: new.path) ? new : old
        }
    }

    /// Moves what an older version left in `old` into `new` (both folders); skips names already in `new`; removes `old` if empty.
    public static func merge(folder old: URL, into new: URL, fileManager: FileManager = .default) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: old.path) else { return }
        for name in names where name != ".DS_Store" && !fileManager.fileExists(atPath: new.appendingPathComponent(name).path) {
            try? fileManager.moveItem(at: old.appendingPathComponent(name), to: new.appendingPathComponent(name))
        }
        // Finder's .DS_Store is junk: not moved, and alone it must not keep the old folder (and this merge) alive.
        try? fileManager.removeItem(at: old.appendingPathComponent(".DS_Store"))
        if (try? fileManager.contentsOfDirectory(atPath: old.path))?.isEmpty == true {
            try? fileManager.removeItem(at: old)
        }
    }
}
