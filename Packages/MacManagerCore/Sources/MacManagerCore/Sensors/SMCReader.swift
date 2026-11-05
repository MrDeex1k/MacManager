import MMHardware

/// Synchronous calls are confined to HardwareSensorSampler's actor. The boundary
/// permits deterministic resource/cache tests without opening a real SMC session.
protocol SMCReading: Sendable {
    func open(_ connection: inout UInt32) -> Int32
    func close(_ connection: UInt32)
    func read(_ connection: UInt32, key: UInt32, info: inout MMSMCKeyInfo, value: inout Double) -> Int32
}

struct SystemSMCReader: SMCReading {
    func open(_ connection: inout UInt32) -> Int32 { mm_smc_open(&connection) }
    func close(_ connection: UInt32) { mm_smc_close(connection) }
    func read(_ connection: UInt32, key: UInt32, info: inout MMSMCKeyInfo, value: inout Double) -> Int32 {
        mm_smc_read_number_cached(connection, key, &info, &value)
    }
}
