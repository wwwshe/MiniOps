import SwiftUI
import MiniOpsKit

struct MetricsSparklineView: View {
    let points: [MetricsHistoryPoint]
    let keyPath: KeyPath<MetricsHistoryPoint, Double>
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let values = points.map { $0[keyPath: keyPath] }
            if values.count >= 2 {
                Path { path in
                    let maxValue = max(values.max() ?? 100, 1)
                    let stepX = geometry.size.width / CGFloat(values.count - 1)

                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = geometry.size.height * (1 - CGFloat(value / maxValue))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 1.5)
            } else {
                Text("히스토리 수집 중…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 44)
    }
}
