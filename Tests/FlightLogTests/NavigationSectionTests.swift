import XCTest
@testable import FlightLog

final class NavigationSectionTests: XCTestCase {
    func testNavigationSectionsExposeRequiredChineseDestinationsInOrder() {
        XCTAssertEqual(
            AppSection.allCases.map(\.title),
            ["概览", "航班", "地图", "统计", "设置", "对比"]
        )
    }
}
