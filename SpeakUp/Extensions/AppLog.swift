import os.log

extension Logger {
    /// App logger for a category. The subsystem was written out at a dozen
    /// call sites; a bundle-id change should be one edit, not a grep.
    ///
    nonisolated static func app(_ category: String) -> Logger {
        Logger(subsystem: "com.vansh.SpeakUpMore", category: category)
    }
}
