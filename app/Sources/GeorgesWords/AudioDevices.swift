import CoreAudio
import Foundation

/// Input-device enumeration and lookup for the microphone picker
/// (backlog 6.5). Devices are remembered by UID (stable across reboots
/// and unplug/replug); a UID that no longer resolves means the device
/// is gone and recording falls back to the system default.
enum AudioInputDevices {

    struct Device: Identifiable, Equatable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    /// System-created transient aggregates (echo-cancelling wrappers that
    /// CoreAudio spins up for voice-processing apps and tears down when
    /// they quit). They wrap the real default input and were never meant
    /// to be user-facing — keep them out of the picker, and treat a saved
    /// selection of one as "system default".
    static func isTransientAggregate(uid: String) -> Bool {
        uid.hasPrefix("CADefaultDeviceAggregate")
    }

    /// All devices currently offering input channels.
    static func list() -> [Device] {
        allDeviceIDs().compactMap { id in
            guard hasInput(id),
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  !isTransientAggregate(uid: uid),
                  let name = stringProperty(id, kAudioObjectPropertyName)
            else { return nil }
            return Device(uid: uid, name: name)
        }
    }

    /// Resolve a remembered UID to today's transient device ID.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let listPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { listPointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, listPointer) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(listPointer.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
