import MMHardware
import Synchronization
import Testing
@testable import MacManagerCore

private final class SMCStub: SMCReading {
    struct State {
        var opens = 0, closes = 0, metadataReads = 0
        var keys: [UInt32] = []
        var fails = false
        var failsOpen = false
    }
    let state = Mutex(State())
    func open(_ connection: inout UInt32) -> Int32 {
        state.withLock {
            $0.opens += 1
            if $0.failsOpen { return -1 }
            connection = 1
            return 0
        }
    }
    func close(_ connection: UInt32) {
        #expect(connection == 1)
        state.withLock { $0.closes += 1 }
    }
    func read(_ connection: UInt32, key: UInt32, info: inout MMSMCKeyInfo, value: inout Double) -> Int32 {
        #expect(connection == 1)
        return state.withLock {
            $0.keys.append(key)
            if $0.fails { info.length = 0; return -1 }
            if info.length == 0 { $0.metadataReads += 1; info.length = 4 }
            value = key == 0x464e756d ? 0 : 50 // FNum: a real passive result, not a failed read.
            return 0
        }
    }
}

@Test func smcReusesConnectionAndMetadataThenClosesWhenNoSensorsAreRequested() async {
    let reader = SMCStub(), sampler = HardwareSensorSampler(reader: reader)
    let catalog = SensorCatalog(processor: "Apple M4 Pro")
    let request = MetricSamplingRequest(kinds: [], cpuTemperature: true, gpuTemperature: false, fans: false)
    for _ in 0..<3 {
        let result = await sampler.sample(catalog: catalog, request: request)
        #expect(result.cpuTemperature == 50 && result.gpuTemperature == nil)
    }
    reader.state.withLock {
        #expect($0.opens == 1 && $0.metadataReads == 1)
        #expect($0.keys == Array(repeating: 0x54434d62, count: 3)) // TCMb only.
    }
    let unused = await sampler.sample(catalog: catalog, request: .none)
    #expect(!unused.isSampled && unused.catalog.supported)
    #expect(reader.state.withLock { $0.closes } == 1)
    _ = await sampler.sample(catalog: catalog, request: request)
    reader.state.withLock { #expect($0.opens == 2 && $0.metadataReads == 2) }
    await sampler.reset()
    await sampler.reset()
    #expect(reader.state.withLock { $0.closes } == 2)
}

@Test func unknownTemperatureCatalogDoesNotOpenSMCButStillAllowsFansAndPower() async {
    let reader = SMCStub(), sampler = HardwareSensorSampler(reader: reader)
    let catalog = SensorCatalog(processor: "Unknown chip")
    let temperatures = MetricSamplingRequest(kinds: [], cpuTemperature: true, gpuTemperature: true, fans: false)
    for _ in 0..<20 {
        let result = await sampler.sample(catalog: catalog, request: temperatures)
        #expect(result.isSampled && !result.catalog.supported)
        #expect(result.cpuTemperature == nil && result.gpuTemperature == nil)
    }
    #expect(reader.state.withLock { $0.opens } == 0)
    let result = await sampler.sample(catalog: catalog,
        request: .init(kinds: [.power], cpuTemperature: false, gpuTemperature: false, fans: true))
    #expect(result.fans == .passive && result.powerWatts == 50)
    reader.state.withLock { #expect($0.keys == [0x50535452, 0x464e756d]) } // PSTR, FNum.
    await sampler.reset()
}

@Test func failedSMCReadsReleaseSessionAndCanRecover() async {
    let reader = SMCStub(), sampler = HardwareSensorSampler(reader: reader)
    let catalog = SensorCatalog(processor: "Apple M4 Pro")
    reader.state.withLock { $0.failsOpen = true }
    let unopened = await sampler.sample(catalog: catalog)
    #expect(unopened.isSampled && unopened.cpuTemperature == nil && unopened.fans == .unavailable)
    #expect(reader.state.withLock { $0.closes } == 0)
    reader.state.withLock { $0.failsOpen = false; $0.fails = true }
    let failed = await sampler.sample(catalog: catalog)
    #expect(failed.fans == .unavailable && failed.powerWatts == nil)
    #expect(reader.state.withLock { $0.closes } == 1)
    reader.state.withLock { $0.fails = false }
    let recovered = await sampler.sample(catalog: catalog)
    #expect(recovered.cpuTemperature == 50 && recovered.fans == .passive)
    #expect(reader.state.withLock { $0.opens } == 3)
    await sampler.reset()
}

@Test func sensorScreenRequiresATemperatureAndFanSample() async {
    let reader = SMCStub(), sampler = HardwareSensorSampler(reader: reader)
    let catalog = SensorCatalog(processor: "Apple M4 Pro")
    let overview = await sampler.sample(catalog: catalog, request: .overview)
    #expect(overview.isSampled && overview.powerWatts == 50)
    #expect(!overview.isTemperatureAndFanSample)

    let cpuOnly = MetricSamplingRequest(kinds: [], cpuTemperature: true, gpuTemperature: false, fans: false)
    let background = await sampler.sample(catalog: catalog, request: cpuOnly)
    #expect(background.cpuTemperature == 50 && !background.isTemperatureAndFanSample)

    let sensors = await sampler.sample(catalog: catalog, request: .sensors)
    #expect(sensors.isTemperatureAndFanSample && sensors.fans == .passive)
    #expect(sensors.stale().isTemperatureAndFanSample)

    await sampler.reset()
    reader.state.withLock { $0.failsOpen = true }
    let unavailable = await sampler.sample(catalog: catalog, request: .sensors)
    #expect(unavailable.isTemperatureAndFanSample && unavailable.fans == .unavailable)
}

@Test func hardwareBridgeRejectsMissingOutputPointersBeforeReadingSystem() {
    #expect(mm_cpu_read(nil) != 0)
    #expect(mm_memory_read(nil) != 0)
}
