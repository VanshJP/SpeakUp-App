import Foundation
import Testing
@testable import SpeakUp

struct MediaPathTests {
    @Test func acceptsPlainBasenames() {
        #expect(MediaPath.sanitizedFilename("take-1.m4a") == "take-1.m4a")
        #expect(MediaPath.sanitizedFilename("  clip.mp4  ") == "clip.mp4")
    }

    @Test func stripsDirectoryPrefixes() {
        #expect(MediaPath.sanitizedFilename("subdir/take.m4a") == "take.m4a")
        #expect(MediaPath.sanitizedFilename("../../etc/passwd") == "passwd")
        #expect(MediaPath.sanitizedFilename("Recordings/../secret.m4a") == "secret.m4a")
    }

    @Test func rejectsDotAndEmpty() {
        #expect(MediaPath.sanitizedFilename("") == nil)
        #expect(MediaPath.sanitizedFilename("   ") == nil)
        #expect(MediaPath.sanitizedFilename(".") == nil)
        #expect(MediaPath.sanitizedFilename("..") == nil)
        #expect(MediaPath.sanitizedFilename("foo/..") == nil)
    }

    @Test func rejectsNullBytes() {
        #expect(MediaPath.sanitizedFilename("evil\0.m4a") == nil)
    }

    @Test func documentsRootIsAllowed() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let nested = docs.appendingPathComponent("clip.m4a")
        #expect(MediaPath.isUnderAllowedMediaRoot(docs))
        #expect(MediaPath.isUnderAllowedMediaRoot(nested))
    }

    @Test func pathsOutsideDocumentsAreRejectedWithoutUbiquity() {
        let escape = URL(fileURLWithPath: "/tmp/escape.m4a")
        #expect(!MediaPath.isUnderAllowedMediaRoot(escape, ubiquityContainer: nil))
    }

    @Test func ubiquityContainerIsAllowedWhenProvided() {
        let cloud = URL(fileURLWithPath: "/tmp/fake-icloud-container")
        let nested = cloud.appendingPathComponent("Documents/Recordings/a.m4a")
        #expect(MediaPath.isUnderAllowedMediaRoot(nested, ubiquityContainer: cloud))
        #expect(!MediaPath.isUnderAllowedMediaRoot(
            URL(fileURLWithPath: "/tmp/other/a.m4a"),
            ubiquityContainer: cloud
        ))
    }
}
