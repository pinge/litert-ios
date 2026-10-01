import XCTest
@testable import LiteRTExample

final class CPUIntegrationTests: XCTestCase {
  func testAddModelRunsOnCPU() throws {
    XCTAssertEqual(try LiteRTRunner.runOnCPU(), [3, 9])
  }
}
