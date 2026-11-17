import XCTest
@testable import TuneHaven

final class ImportPresentationTests: XCTestCase {
    func testPickerCancellationIsNotReportedAsFailure() {
        XCTAssertNil(ImportPickerFailure.message(for: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        XCTAssertNil(ImportPickerFailure.message(for: URLError(.cancelled)))
        XCTAssertNotNil(ImportPickerFailure.message(for: CocoaError(.fileReadNoPermission)))
    }

    func testResultSeparatesPartialSuccessFromCompleteFailureAndDuplicates() {
        XCTAssertEqual(result(success: 2, failed: 1).presentationTitle, "部分导入完成")
        XCTAssertEqual(result(success: 2, unsupported: 1).presentationTitle, "部分导入完成")
        XCTAssertEqual(result(success: 2, duplicate: 1).presentationTitle, "导入完成")
        XCTAssertEqual(result(failed: 1).presentationTitle, "导入未完成")
        XCTAssertEqual(result(duplicate: 3).presentationTitle, "已跳过重复文件")
        XCTAssertEqual(result(unsupported: 1).presentationTitle, "没有可导入的文件")
        XCTAssertEqual(result().presentationTitle, "没有可导入的文件")
    }

    private func result(success: Int = 0, failed: Int = 0, duplicate: Int = 0, unsupported: Int = 0) -> ImportResult {
        ImportResult(successCount: success, skippedDuplicateCount: duplicate, skippedFormatCount: unsupported,
                     failedCount: failed, incompleteMetadataCount: 0, skippedOversizeCount: 0, details: [])
    }
}
