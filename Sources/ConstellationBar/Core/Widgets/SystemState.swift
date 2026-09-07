import Foundation
import AppKit


struct SystemState: Equatable {
    var agents = AgentStatusState()
    var battery: BatteryState = BatteryState(percent: nil, isCharging: false)
    var vpn: VPNState = VPNState()
    var network: NetworkSpeedState = NetworkSpeedState(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
    var memory: MemoryState = MemoryState(usage: 0)
    var disk: DiskState = DiskState(usage: 0)
    var uptime: TimeInterval = 0
    var date: Date = Date()
    var cpu: CPUState = CPUState(usage: 0)
    var thermal: ThermalPressureState = .nominal
    var nowPlaying: NowPlayingState = .empty
    var weather: WeatherState = .unavailable
    func hidesNowPlaying(whenIdle: Bool) -> Bool { whenIdle && nowPlaying.source.isEmpty && !mediaNeedsAttention }
    var mediaNeedsAttention: Bool { providerStatuses.contains { $0.needsAttention && ["appleMusic", "browser"].contains($0.id) } }
    var mediaSessions: [MediaSession] = []
    var providerStatuses: [ProviderStatus] = []
    var audio = AudioState()
    var agenda = AgendaState()
    var topProcesses: [ProcessUsage] = []
}
