import Foundation

nonisolated(unsafe) var xctFailures = 0
nonisolated(unsafe) var xctCurrent = ""

func xctFail(_ msg: String, _ file: StaticString, _ line: UInt) {
    xctFailures += 1
    print("FAIL \(xctCurrent) \(file):\(line): \(msg)")
}

@MainActor open class XCTestCase {
    public required init() {}
    open func setUp() {}
    open func tearDown() {}
    open func setUpWithError() throws {}
    open func tearDownWithError() throws {}
}

struct XCTUnwrapError: Error {}

func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) { xctFail(message, file, line) }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let x = try a(), y = try b(); if x != y { xctFail("\(x) != \(y) \(message())", file, line) } } catch { xctFail("threw \(error)", file, line) }
}
func XCTAssertTrue(_ a: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !a() { xctFail("not true \(message())", file, line) } } catch { xctFail("threw \(error)", file, line) }
}
func XCTAssertFalse(_ a: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try a() { xctFail("not false \(message())", file, line) } } catch { xctFail("threw \(error)", file, line) }
}
func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let x = try a(), y = try b(); if !(x > y) { xctFail("\(x) <= \(y)", file, line) } } catch { xctFail("threw \(error)", file, line) }
}
func XCTAssertNil(_ a: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if let v = try a() { xctFail("not nil: \(v) \(message())", file, line) } } catch { xctFail("threw \(error)", file, line) }
}
func XCTAssertNotNil(_ a: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try a() == nil { xctFail("nil \(message())", file, line) } } catch { xctFail("threw \(error)", file, line) }
}
func XCTAssertThrowsError<T>(_ a: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try a(); xctFail("did not throw \(message())", file, line) } catch { handler(error) }
}
func XCTUnwrap<T>(_ a: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let v = try a() else { xctFail("unwrap nil", file, line); throw XCTUnwrapError() }
    return v
}
