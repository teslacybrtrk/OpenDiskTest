//
//  OpenDiskTestTests.swift
//  OpenDiskTestTests
//
//  Created by Philip Emanuele on 9/9/24.
//

import XCTest
@testable import OpenDiskTest

final class OpenDiskTestTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - TestResult aggregation

    func testTestResultEmptyDefaultsToZero() throws {
        let result = TestResult(name: "Empty")
        XCTAssertEqual(result.minSpeed, 0)
        XCTAssertEqual(result.avgSpeed, 0)
        XCTAssertEqual(result.maxSpeed, 0)
        XCTAssertTrue(result.speeds.isEmpty)
    }

    func testTestResultComputesMinAvgMaxAndSorted() throws {
        var result = TestResult(name: "Speeds")
        result.speeds = [12.5, 9.0, 15.75, 9.0, 20.0]
        result.sortedSpeeds = result.speeds.enumerated().sorted { $0.element < $1.element }

        XCTAssertEqual(result.minSpeed, 9.0)
        XCTAssertEqual(result.maxSpeed, 20.0)
        XCTAssertEqual(result.avgSpeed, 13.25, accuracy: 0.0001)
        XCTAssertEqual(result.sortedSpeeds.count, 5)
        XCTAssertEqual(result.sortedSpeeds.first?.element, 9.0)
        XCTAssertEqual(result.sortedSpeeds.last?.element, 20.0)
    }

    // MARK: - ViewModel configuration & validation

    func testViewModelDefaultCanStartIsTrue() throws {
        // Ensure clean UserDefaults state so the persistence logic doesn't pollute the "default" assertion
        UserDefaults.standard.removeObject(forKey: "fileSize")
        UserDefaults.standard.removeObject(forKey: "iterations")
        UserDefaults.standard.removeObject(forKey: "testDirectoryBookmark")

        let vm = DiskSpeedTestViewModel()
        // Fresh VM should have valid defaults
        XCTAssertTrue(vm.canStartTests)
        XCTAssertEqual(vm.fileSize, 10)
        XCTAssertEqual(vm.iterations, 100)
    }

    func testViewModelRejectsInvalidParameters() throws {
        let vm = DiskSpeedTestViewModel()
        vm.fileSize = 0
        XCTAssertFalse(vm.canStartTests)

        vm.fileSize = 10
        vm.iterations = 0
        XCTAssertFalse(vm.canStartTests)

        vm.iterations = 2000
        XCTAssertFalse(vm.canStartTests)

        vm.fileSize = 5000
        vm.iterations = 50
        XCTAssertFalse(vm.canStartTests)

        vm.fileSize = 100
        vm.iterations = 10
        XCTAssertTrue(vm.canStartTests)
    }

    // MARK: - Update SHA comparison logic (mirrors UpdateChecker predicate)

    func testUpdateSHAIsNewComparison() throws {
        func isNew(localSHA: String, remoteSHA: String) -> Bool {
            !localSHA.hasPrefix(remoteSHA) && !remoteSHA.hasPrefix(localSHA)
        }

        XCTAssertTrue(isNew(localSHA: "d365f26701ffd38100cb8dd37f9f2d3f3b629d08", remoteSHA: "abc1234"))
        XCTAssertFalse(isNew(localSHA: "abc1234dead", remoteSHA: "abc1234"))
        XCTAssertFalse(isNew(localSHA: "abc1234", remoteSHA: "abc1234deadbeef"))
        XCTAssertFalse(isNew(localSHA: "abc1234", remoteSHA: "abc1234"))
        XCTAssertTrue(isNew(localSHA: "1111111", remoteSHA: "2222222"))
    }

    func testPerformanceExample() throws {
        // Leave a performance placeholder (disk I/O not unit-tested here)
        self.measure {
            _ = (1...1000).map { $0 * 2 }
        }
    }

}
