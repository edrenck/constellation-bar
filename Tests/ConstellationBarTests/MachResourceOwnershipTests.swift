import Darwin
import XCTest
@testable import ConstellationBar

final class MachResourceOwnershipTests: XCTestCase {
    func testRepeatedCPUReadsDoNotAccumulateHostPortSendReferences() throws {
        try assertBalanced(label: "CPU") { _ = try CPUCounters.current() }
    }

    func testRepeatedMemoryReadsDoNotAccumulateHostPortSendReferences() throws {
        let reader = HostMetricsReader()
        try assertBalanced(label: "Memory") { _ = try reader.memory() }
    }

    private func assertBalanced(label: String, read: () throws -> Void) throws {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        try read() // Establish any first-read initialization before measuring.
        let before = try sendReferences(host)
        for _ in 0..<1024 { try read() }
        let after = try sendReferences(host)
        // Keep a deliberately failing regression from retaining its leaked rights.
        defer { if after > before { for _ in before..<after { mach_port_deallocate(mach_task_self_, host) } } }
        print("MACH_RESOURCE_PROBE \(label) reads=1024 sendRefsBefore=\(before) sendRefsAfter=\(after) growth=\(Int(after)-Int(before))")
        XCTAssertEqual(after, before, "Every metrics read must release the host send right it acquires")
    }

    private func sendReferences(_ port: mach_port_t) throws -> mach_port_urefs_t {
        var count: mach_port_urefs_t = 0
        let result = mach_port_get_refs(mach_task_self_, port, mach_port_right_t(MACH_PORT_RIGHT_SEND), &count)
        guard result == KERN_SUCCESS else { throw NSError(domain: NSMachErrorDomain, code: Int(result)) }
        return count
    }
}
