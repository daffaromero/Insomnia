import XCTest
@testable import Insomnia

final class FloorRulesTests: XCTestCase {
    func eval(_ percent: Int?, charging: Bool = false, thermal: ProcessInfo.ThermalState = .nominal, lid: Bool = false, lp: Bool = false, config: Config = Config()) -> [FloorRules.Action] {
        FloorRules.evaluate(percent: percent, isCharging: charging, thermal: thermal, lidClosed: lid, lowPowerSetByUs: lp, config: config)
    }

    // Row 1: battery below lowPowerFloor -> lowpowermode 1
    func testBelowLowPowerFloorEnablesLowPower() {
        XCTAssertEqual(eval(39), [.enableLowPower(.battery)])
        XCTAssertEqual(eval(40), [])
        XCTAssertEqual(eval(39, lp: true), [])
    }

    // Row 1 undo: charger connected, or session end (session end is restoreAll)
    func testChargerConnectedClearsLowPower() {
        XCTAssertEqual(eval(39, charging: true, lp: true), [.disableLowPower])
        XCTAssertEqual(eval(39, charging: true), [])
    }

    func testBackAboveFloorClearsLowPower() {
        XCTAssertEqual(eval(45, lp: true), [.disableLowPower])
    }

    // Row 2: battery below endFloor -> end session
    func testBelowEndFloorEndsSession() {
        XCTAssertEqual(eval(9), [.endSession(.batteryFloor)])
        XCTAssertEqual(eval(10), [.enableLowPower(.battery)])
        XCTAssertEqual(eval(9, lp: true), [.endSession(.batteryFloor)])
    }

    func testBelowEndFloorWhileChargingDoesNotEnd() {
        XCTAssertEqual(eval(5, charging: true), [])
    }

    // Row 3: thermal serious -> lowpowermode 1; undo when nominal/fair
    func testThermalSeriousEnablesLowPower() {
        XCTAssertEqual(eval(80, thermal: .serious), [.enableLowPower(.thermal)])
        XCTAssertEqual(eval(80, charging: true, thermal: .serious), [.enableLowPower(.thermal)])
        XCTAssertEqual(eval(80, thermal: .serious, lp: true), [])
    }

    func testThermalBackToNominalOrFairClearsLowPower() {
        XCTAssertEqual(eval(80, thermal: .nominal, lp: true), [.disableLowPower])
        XCTAssertEqual(eval(80, thermal: .fair, lp: true), [.disableLowPower])
    }

    // Row 4: thermal critical -> end session
    func testThermalCriticalEndsSession() {
        XCTAssertEqual(eval(80, thermal: .critical), [.endSession(.thermalCritical)])
        XCTAssertEqual(eval(nil, thermal: .critical), [.endSession(.thermalCritical)])
    }

    func testBatteryEndFloorWinsOverThermalCritical() {
        XCTAssertEqual(eval(5, thermal: .critical), [.endSession(.batteryFloor)])
    }

    func testThermalRulesOffIgnoresThermal() {
        var c = Config()
        c.thermalRules = false
        XCTAssertEqual(eval(80, thermal: .serious, config: c), [])
        XCTAssertEqual(eval(80, thermal: .critical, config: c), [])
        XCTAssertEqual(eval(80, thermal: .serious, lp: true, config: c), [.disableLowPower])
        // Battery rules still apply.
        XCTAssertEqual(eval(30, thermal: .critical, config: c), [.enableLowPower(.battery)])
    }

    func testLowPowerStaysWhileEitherCauseHolds() {
        XCTAssertEqual(eval(30, thermal: .serious, lp: true), [])
        XCTAssertEqual(eval(30, thermal: .nominal, lp: true), [])
        XCTAssertEqual(eval(80, charging: true, thermal: .serious, lp: true), [])
    }

    func testNoBatteryInfoOnlyThermalApplies() {
        XCTAssertEqual(eval(nil), [])
        XCTAssertEqual(eval(nil, thermal: .serious), [.enableLowPower(.thermal)])
    }

    func testCustomFloors() {
        var c = Config()
        c.lowPowerFloor = 60
        c.endFloor = 25
        XCTAssertEqual(eval(59, config: c), [.enableLowPower(.battery)])
        XCTAssertEqual(eval(24, config: c), [.endSession(.batteryFloor)])
    }

    // Row 5: lid closed (optional, default on) -> lowpowermode 1; undo on lid open
    func testLidClosedEnablesLowPowerWhenConfigured() {
        XCTAssertEqual(eval(80, lid: true), [.enableLowPower(.lid)])
        XCTAssertEqual(eval(nil, lid: true), [.enableLowPower(.lid)])
        XCTAssertEqual(eval(80, lid: true, lp: true), [])
    }

    func testLidClosedWithOptionOffDoesNothing() {
        var c = Config()
        c.lowPowerOnLidClose = false
        XCTAssertEqual(eval(80, lid: true, config: c), [])
        XCTAssertEqual(eval(80, lid: true, lp: true, config: c), [.disableLowPower])
        // Battery and thermal rules still apply with the lid closed.
        XCTAssertEqual(eval(30, lid: true, config: c), [.enableLowPower(.battery)])
    }

    func testLidOpenAfterLidCausedEnableClearsLowPower() {
        XCTAssertEqual(eval(80, lid: false, lp: true), [.disableLowPower])
    }

    func testLidOpenWithBatteryBelowFloorKeepsLowPower() {
        XCTAssertEqual(eval(30, lid: false, lp: true), [])
        XCTAssertEqual(eval(80, thermal: .serious, lid: false, lp: true), [])
    }

    func testLidClosedWhileChargingStillEnablesLowPower() {
        XCTAssertEqual(eval(80, charging: true, lid: true), [.enableLowPower(.lid)])
        XCTAssertEqual(eval(80, charging: true, lid: true, lp: true), [])
    }

    func testEndSessionRulesWinOverLid() {
        XCTAssertEqual(eval(5, lid: true), [.endSession(.batteryFloor)])
        XCTAssertEqual(eval(80, thermal: .critical, lid: true), [.endSession(.thermalCritical)])
    }

    /// The cause names the strongest reason: thermal, then battery, then lid.
    func testLidIsTheWeakestCause() {
        XCTAssertEqual(eval(30, lid: true), [.enableLowPower(.battery)])
        XCTAssertEqual(eval(30, thermal: .serious, lid: true), [.enableLowPower(.thermal)])
        XCTAssertEqual(eval(80, thermal: .serious, lid: true), [.enableLowPower(.thermal)])
    }

    func cause(_ percent: Int?, charging: Bool = false, thermal: ProcessInfo.ThermalState = .nominal, lid: Bool = false, config: Config = Config()) -> FloorRules.LowPowerCause? {
        FloorRules.lowPowerCause(percent: percent, isCharging: charging, thermal: thermal, lidClosed: lid, config: config)
    }

    /// The effective cause is the strongest one holding right now, whether
    /// or not Insomnia already has the mode on.
    func testLowPowerCauseNamesTheStrongestHoldingCause() {
        XCTAssertNil(cause(80))
        XCTAssertNil(cause(35, charging: true))
        XCTAssertEqual(cause(35), .battery)
        XCTAssertEqual(cause(80, thermal: .serious), .thermal)
        XCTAssertEqual(cause(80, lid: true), .lid)
        XCTAssertEqual(cause(35, lid: true), .battery)
        XCTAssertEqual(cause(35, charging: true, lid: true), .lid)
        XCTAssertEqual(cause(35, thermal: .serious, lid: true), .thermal)
    }

    func testLowPowerCauseHonorsTheOptions() {
        var c = Config()
        c.lowPowerOnLidClose = false
        c.thermalRules = false
        XCTAssertNil(cause(80, thermal: .serious, lid: true, config: c))
        XCTAssertEqual(cause(35, thermal: .serious, lid: true, config: c), .battery)
    }
}

@MainActor
final class FloorRuleDriverTests: XCTestCase {
    var h: Harness!

    override func setUp() async throws { h = Harness() }
    override func tearDown() async throws { h.home.destroy() }

    func testEndFloorEndsSessionWithReason() async throws {
        let m = h.makeManager()
        await m.start(duration: 3600)
        let driver = FloorRuleDriver(manager: m, notifier: h.notifier)
        await driver.run(percent: 8, isCharging: false, thermal: .nominal, lidClosed: false)
        XCTAssertFalse(m.isActive)
        XCTAssertNil(try h.store.loadSession())
        XCTAssertEqual(h.guardFake.calls.last, "disablesleep 0")
        XCTAssertEqual(h.notifier.posts.last?.title, "Session ended")
        XCTAssertTrue(h.notifier.posts.last?.body.contains("10%") ?? false)
    }

    func testThermalCriticalEndsSession() async throws {
        let m = h.makeManager()
        await m.start(duration: 3600)
        let driver = FloorRuleDriver(manager: m, notifier: h.notifier)
        await driver.run(percent: 80, isCharging: false, thermal: .critical, lidClosed: false)
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(try h.store.loadState(), RuntimeState.clean)
        XCTAssertEqual(h.guardFake.calls.last, "disablesleep 0")
        XCTAssertTrue(h.notifier.posts.last?.body.contains("critical") ?? false)
    }

    func testNoSessionDoesNothing() async throws {
        let m = h.makeManager()
        let driver = FloorRuleDriver(manager: m, notifier: h.notifier)
        await driver.run(percent: 5, isCharging: false, thermal: .critical, lidClosed: false)
        XCTAssertEqual(h.guardFake.calls, [])
        XCTAssertEqual(h.notifier.posts.count, 0)
    }

    func testLidOptionOffLeavesLowPowerAlone() async throws {
        let m = h.makeManager()
        m.config.lowPowerOnLidClose = false
        await m.start(duration: 3600)
        let driver = FloorRuleDriver(manager: m, notifier: h.notifier)
        await driver.run(percent: 80, isCharging: false, thermal: .nominal, lidClosed: true)
        XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 1"))
        XCTAssertEqual(try h.store.loadState()?.lowPowerSetByUs, false)
    }

    /// This build: no sudoers rule allows `pmset -b lowpowermode`, so no
    /// cause (battery, thermal, lid) ever reads or sets the mode, journals
    /// ownership or announces anything; the session ends with a clean journal.
    func testLowPowerModeIsNeverEnabled() async throws {
        let m = h.makeManager()
        await m.start(duration: 3600)
        let driver = FloorRuleDriver(manager: m, notifier: h.notifier)
        await driver.run(percent: 35, isCharging: false, thermal: .nominal, lidClosed: false)
        await driver.run(percent: 80, isCharging: false, thermal: .serious, lidClosed: false)
        await driver.run(percent: 80, isCharging: true, thermal: .nominal, lidClosed: true)
        let changed = await m.setLowPower(true)
        XCTAssertFalse(changed)

        XCTAssertTrue(m.isActive)
        XCTAssertEqual(h.guardFake.calls, ["disablesleep 1"])
        XCTAssertEqual(try h.store.loadState()?.lowPowerSetByUs, false)
        XCTAssertEqual(h.notifier.posts.count, 0)

        await m.end(reason: .user)
        XCTAssertEqual(h.guardFake.calls, ["disablesleep 1", "disablesleep 0"])
        XCTAssertEqual(try h.store.loadState(), RuntimeState.clean)
    }
}
