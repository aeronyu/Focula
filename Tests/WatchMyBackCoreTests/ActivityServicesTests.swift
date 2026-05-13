import Foundation
import XCTest
@testable import WatchMyBackCore

final class ActivityServicesTests: XCTestCase {
    func testFrameDeduplicatorSkipsImmediateDuplicateBytes() {
        let deduplicator = FrameDeduplicator()
        let frame = Data([1, 2, 3, 4, 5])

        XCTAssertTrue(deduplicator.shouldClassify(frame))
        XCTAssertFalse(deduplicator.shouldClassify(frame))
        XCTAssertTrue(deduplicator.shouldClassify(Data([1, 2, 3, 4, 6])))
    }
}
