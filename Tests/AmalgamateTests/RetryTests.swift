import XCTest
import Combine
@testable import Amalgamate

typealias IntSequencePublisher = Publishers.Sequence<[Int], Never>

final class RetryTests: XCTestCase {
    
    // MARK: No Retry
    
    /// Feed in [1, 2, 3] and never retry. The sequence should just flow through.
    func testSequenceNoRetry() {
        let expectation = XCTestExpectation()
        let originalSequence = [1, 2, 3]
        let _ = IntSequencePublisher(sequence: originalSequence)
            .retry { _ in false }
            .collect()
            .sink { sequence in
                XCTAssertEqual(sequence, [1, 2, 3])
                expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
    
    // MARK: Retry without butFirst
    
    /// Feed in [1, 2, 3] and retry once on the 2. The sequence [1, 1, 2, 3] should come out.
    func testSequenceRetryOnce() {
        let expectation = XCTestExpectation()
        let originalSequence = [1, 2, 3]
        var retried = false
        let _ = IntSequencePublisher(sequence: originalSequence)
            .retry { value in
                if value == 2 && !retried {
                    retried = true
                    return true
                }
                return false
        }
        .collect()
        .sink { sequence in
            XCTAssertEqual(sequence, [1, 1, 2, 3])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
    
    /// Feed in [1, 2, 3] and retry once on the 2 and once on the 3. The sequence [1, 1, 2, 1, 2, 3] should come out.
    func testSequenceRetryTwice() {
        let expectation = XCTestExpectation()
        let originalSequence = [1, 2, 3]
        var retried = 0
        let _ = IntSequencePublisher(sequence: originalSequence)
            .retry { value in
                if (value == 2 && retried == 0) || (value == 3 && retried == 1) {
                    retried += 1
                    return true
                }
                return false
        }
        .collect()
        .sink { sequence in
            XCTAssertEqual(sequence, [1, 1, 2, 1, 2, 3])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
    
    // MARK: Retry with butFirst
    
    /// Feed in [1, 2, 3] and retry once on the 2 with a butFirst sequence of [4, 5, 6]. The sequence [1, 4, 5, 6, 1, 2, 3] should come out.
    func testSequenceRetryOnceWithButFirst() {
        let expectation = XCTestExpectation()
        let originalSequence = [1, 2, 3]
        var retried = false
        let _ = IntSequencePublisher(sequence: originalSequence)
            .retry(butFirst: IntSequencePublisher(sequence: [4, 5, 6])) { value in
                if value == 2 && !retried {
                    retried = true
                    return true
                }
                return false
        }
        .collect()
        .sink { sequence in
            XCTAssertEqual(sequence, [1, 4, 5, 6, 1, 2, 3])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
    
    /// Feed in [1, 2, 3] and retry once on the 2 and once on the 3 with a butFirst sequence of [4, 5, 6].
    /// The sequence [1, 4, 5, 6, 1, 2, 4, 5, 6, 1, 2, 3] should come out.
    func testSequenceRetryTwiceWithButFirst() {
        let expectation = XCTestExpectation()
        let originalSequence = [1, 2, 3]
        var retried = 0
        let _ = IntSequencePublisher(sequence: originalSequence)
            .retry(butFirst: IntSequencePublisher(sequence: [4, 5, 6])) { value in
                if (value == 2 && retried == 0) || (value == 3 && retried == 1) {
                    retried += 1
                    return true
                }
                return false
        }
        .collect()
        .sink { (sequence) in
            XCTAssertEqual(sequence, [1, 4, 5, 6, 1, 2, 4, 5, 6, 1, 2, 3])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
    
    // MARK: Failure
    
    /// If the upstream fails, the failure should propagate downstream.
    func testFailure() {
        let expectation = XCTestExpectation()
        let _ = Fail(outputType: Int.self, failure: URLError(.badServerResponse))
            .retry { $0 == 2 }
            .catch { error -> Just<Int> in
                expectation.fulfill()
                return Just(1)
        }
        .sink { value in
            // Do nothing
        }
        wait(for: [expectation], timeout: 1)
    }
    
    /// If the butFirst publisher fails, it should propagate downstream. We feed in [1, 2, 3] and retry on 2 with a failing butFirst publisher.
    func testFailureOfButFirst() {
        let expectation = XCTestExpectation()
        let _ = IntSequencePublisher(sequence: [1, 2, 3])
            .setFailureType(to: URLError.self)
            .retry(butFirst: Fail(outputType: Int.self, failure: URLError(.badServerResponse))) { $0 == 2 }
            .catch { error -> Just<Int> in
                expectation.fulfill()
                return Just(4)
        }
        .collect()
        .sink { sequence in
            XCTAssertEqual(sequence, [1, 4])
        }
        wait(for: [expectation], timeout: 1)
    }
    
    // MARK: Limited Demand
    
    /// Feed in [1, 2, 3], but only take a prefix of 2 values. The sequence [1, 2] should come out.
    func testLimitedDemand() {
        // TODO: This doesn't actually test the implementation of our Retry publisher, because the prefix
        // publisher doesn't demand 2 values. It demands an unlimited amount
        let expectation = XCTestExpectation()
        let originalSequence = [1, 2, 3]
        let _ = IntSequencePublisher(sequence: originalSequence)
            .retry { _ in false }
            .prefix(2)
            .collect()
            .sink { sequence in
                XCTAssertEqual(sequence, [1, 2])
                expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
    
    // TODO: Add tests for correct cleanup of values after cancelletation and stuff like that?
    
    static var allTests = [
        ("testSequenceNoRetry", testSequenceNoRetry),
        ("testSequenceRetryOnce", testSequenceRetryOnce),
        ("testSequenceRetryTwice", testSequenceRetryTwice),
        ("testSequenceRetryOnceWithButFirst", testSequenceRetryOnceWithButFirst),
        ("testSequenceRetryTwiceWithButFirst", testSequenceRetryTwiceWithButFirst),
        ("testFailure", testFailure),
        ("testFailureOfButFirst", testFailureOfButFirst),
        ("testLimitedDemand", testLimitedDemand),
    ]
}
