import XCTest
@testable import NoTypeCore

final class SpeechAndInsertionTests: XCTestCase {
    func testDisabledDictationMessageAndNestedCause() {
        let cause = NSError(domain: "kAFAssistantErrorDomain", code: 1101,
                            userInfo: [NSLocalizedDescriptionKey: "Siri and Dictation are disabled"])
        XCTAssertTrue(SpeechFailure.dictationDisabled(cause))
        let wrapper = NSError(domain: "Speech", code: 1, userInfo: [NSUnderlyingErrorKey: cause])
        XCTAssertTrue(SpeechFailure.dictationDisabled(wrapper))
        XCTAssertFalse(SpeechFailure.dictationDisabled(NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "No speech detected"])))
    }
    func testAutomaticInputReturnsOnlyFromNoTypeOrOriginalApplication() {
        XCTAssertTrue(InsertionPolicy.mayReturnToTarget(frontmost: 10, target: 10, own: 20))
        XCTAssertTrue(InsertionPolicy.mayReturnToTarget(frontmost: 20, target: 10, own: 20))
        XCTAssertFalse(InsertionPolicy.mayReturnToTarget(frontmost: 30, target: 10, own: 20))
        XCTAssertFalse(InsertionPolicy.mayReturnToTarget(frontmost: nil, target: 10, own: 20))
        XCTAssertFalse(InsertionPolicy.mayReturnToTarget(frontmost: 20, target: 20, own: 20))
    }
}
