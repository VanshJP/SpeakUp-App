import os.log

extension Logger {
    /// App logger for a category. The subsystem was written out at a dozen
    /// call sites; a bundle-id change should be one edit, not a grep.
    ///
    /// Prefer this over `print` anywhere in the app target — `print` runs in
    /// release builds too, pays for its string interpolation whether or not
    /// anyone is watching, and cannot be filtered by category in Console.
    /// `nonisolated` because default actor isolation here is MainActor and
    /// off-main callers (memory-pressure handlers, the llama.cpp engine) log too.
    nonisolated static func app(_ category: String) -> Logger {
        Logger(subsystem: "com.vansh.SpeakUpMore", category: category)
    }
}
