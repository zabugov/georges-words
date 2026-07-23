import XCTest
@testable import GeorgesWords

final class AudioInputDevicesTests: XCTestCase {

    func testSystemGhostAggregatesAreFilteredFromThePicker() {
        // The echo-cancelling wrappers CoreAudio creates for
        // voice-processing apps ("CADefaultDeviceAggregate-<pid>-<n>",
        // seen live 2026-07-22) must never be listed or restorable as
        // a remembered selection.
        XCTAssertTrue(AudioInputDevices.isTransientAggregate(uid: "CADefaultDeviceAggregate-123-0"))
        XCTAssertTrue(AudioInputDevices.isTransientAggregate(uid: "CADefaultDeviceAggregate-45-1"))
    }

    func testRealDeviceUIDsAreNotFiltered() {
        XCTAssertFalse(AudioInputDevices.isTransientAggregate(uid: "BuiltInMicrophoneDevice"))
        XCTAssertFalse(AudioInputDevices.isTransientAggregate(uid: "AppleUSBAudioEngine:Blue Microphones:Yeti:123:1"))
        // User-created aggregates from Audio MIDI Setup stay selectable.
        XCTAssertFalse(AudioInputDevices.isTransientAggregate(uid: "~:AMS2_Aggregate:0"))
    }
}
