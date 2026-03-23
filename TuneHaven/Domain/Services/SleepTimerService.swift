import Foundation

@MainActor
final class SleepTimerService: ObservableObject {
    @Published private(set) var remaining: TimeInterval? = nil

    private let log = AppLogger.shared
    private var endDate: Date?
    private var timer: Timer?
    private var onExpired: (() -> Void)?

    func configure(onExpired: @escaping () -> Void) {
        self.onExpired = onExpired
    }

    var isActive: Bool { endDate != nil }

    var selectedMinutes: Int? {
        guard let endDate else { return nil }
        return Int(endDate.timeIntervalSince(Date()) / 60) + 1
    }

    func set(minutes: Int?) {
        log.info("设置睡眠定时: \(minutes ?? 0) 分钟")
        cancel()
        guard let minutes, minutes > 0 else { return }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        endDate = end

        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remaining = nil
    }

    func checkOnForeground() {
        guard let endDate, Date() >= endDate else { return }
        expire()
    }

    private func tick() {
        guard let endDate else { return }
        let r = endDate.timeIntervalSince(Date())
        if r <= 0 {
            expire()
        } else {
            remaining = r
        }
    }

    private func expire() {
        log.info("睡眠定时到期，暂停播放")
        cancel()
        onExpired?()
    }
}
