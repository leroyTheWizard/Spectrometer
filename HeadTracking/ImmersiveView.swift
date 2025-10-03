import SwiftUI
import RealityKit
import ARKit

final class SpectrometerViewModel: ObservableObject {
    enum State { case collapsedIdle, expanding, expanded, splitting, split }
    @Published var state: State = .collapsedIdle

    // Gaze-Tracking für Idle-Rückführung
    @Published var isGazingMain: Bool = false
    @Published var isGazingCollapsed: Bool = false

    private var idleWorkItem: DispatchWorkItem?
    let idleDuration: TimeInterval = 2.0

    func setGazeMain(_ gazing: Bool) {
        isGazingMain = gazing
        rescheduleIdleIfNeeded()
    }

    func setGazeCollapsed(_ gazing: Bool) {
        isGazingCollapsed = gazing
        rescheduleIdleIfNeeded()
    }

    private func rescheduleIdleIfNeeded() {
        // Wenn Blick auf einem der Fenster liegt, Timer abbrechen
        if isGazingMain || isGazingCollapsed {
            idleWorkItem?.cancel()
            idleWorkItem = nil
            return
        }
        // Nur in expanded/split zurückfallen
        guard state == .expanded || state == .split else { return }

        idleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if !(self.isGazingMain || self.isGazingCollapsed) && (self.state == .expanded || self.state == .split) {
                self.state = .collapsedIdle
            }
        }
        idleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleDuration, execute: work)
    }
}

struct ImmersiveView: View {
    @StateObject private var vm = SpectrometerViewModel()

    // Ein Entity als 2D-Container für beide Zustände (kein Hintergrund, kein Clipping)
    private let containerPanel = Entity()

    var body: some View {
        RealityView { content, attachments in
            // Head-locked Anchor (kontinuierlich, an den Kopf gebunden)
            let headAnchor = AnchorEntity(.head)
            headAnchor.anchoring.trackingMode = .continuous
            content.add(headAnchor)

            // Ein gemeinsamer Container für beide Zustände (2D-Logik)
            headAnchor.addChild(containerPanel)
            containerPanel.setPosition([0.53, 0.0, -0.6], relativeTo: headAnchor)

            // ⇨ Single Attachment für beide Fenster (kein Container-Hintergrund)
            if let containerEntity = attachments.entity(for: "spectrometer-container") {
                // Wichtig: Input für SwiftUI-Attachments aktivieren
                containerEntity.components.set(InputTargetComponent())
                containerPanel.addChild(containerEntity)
            }
        } attachments: {
            Attachment(id: "spectrometer-container") {
                SpectrometerContainerView()
                    .environmentObject(vm)
                    .frame(width: 110, height: 850) // groß genug für beide Panels (700 + 40 + 110)
            }
        }
    }
}

struct SpectrometerContainerView: View {
    @EnvironmentObject private var vm: SpectrometerViewModel

    private let mainPanelHeight: CGFloat = 700
    private let collapsedPanelHeight: CGFloat = 110
    private let splitGap: CGFloat = 40

    var body: some View {
        VStack {
            // Kein Hintergrund im Container, nur die beiden Panels
            ExamplePanelView()
                .frame(width: 110, height: mainPanelHeight)

            CollapsedSpectrometerView()
                .frame(width: 110, height: collapsedPanelHeight)
        }
        // Container groß genug, damit nichts abgeschnitten wird
        .frame(width: 110, height: mainPanelHeight + splitGap + collapsedPanelHeight)
        // Keine Clips/Masken am Container
    }
}

// MARK: - SwiftUI Panel mit custom spectrometer-style slider und Glas-Hintergrund
struct ExamplePanelView: View {
    @EnvironmentObject private var vm: SpectrometerViewModel
    @State private var value: Double = 0.5
    @State private var appear: Bool = false

    private let mainPanelHeight: CGFloat = 700
    private let collapsedPanelHeight: CGFloat = 110
    private let splitGap: CGFloat = 40
    private var splitOffsetY: CGFloat {
        (vm.state == .splitting || vm.state == .split) ? -((mainPanelHeight/2 + splitGap + collapsedPanelHeight/2)/2) : 0
    }

    var body: some View {
        ZStack {
                ZStack {
                    SpectrometerSlider(value: $value)
                        .padding(20)
                }
                .opacity(appear ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: appear)
                .offset(y: splitOffsetY)
                .animation(.easeInOut(duration: 0.5), value: vm.state)
                .onHover { hovering in
                    vm.setGazeMain(hovering)
                }
                .onAppear {
                    if vm.state != .collapsedIdle {
                        appear = true
                    }
                }
                .task(id: vm.state) {
                    switch vm.state {
                    case .expanding:
                        appear = true
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        if vm.state == .expanding {
                            vm.state = .expanded
                        }
                    case .expanded:
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        if vm.state == .expanded {
                            vm.state = .splitting
                        }
                    case .splitting:
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if vm.state == .splitting {
                            vm.state = .split
                        }
                    case .collapsedIdle:
                        appear = false
                    case .split:
                        break
                    }
                }
                .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(radius: 12)
                if vm.state == .collapsedIdle {
                    // Im Idle-State bleibt das große Fenster unsichtbar
                    Color.clear
                } else {}
            }
        // Wichtig: Wenn collapsed, darf dieses (große) Attachment keine Events abfangen
        .allowsHitTesting(vm.state != .collapsedIdle)
        .accessibilityHidden(vm.state == .collapsedIdle)
    }
}

struct CollapsedSpectrometerView: View {
    @EnvironmentObject private var vm: SpectrometerViewModel
    @State private var isHovering = false
    @State private var dwellWorkItem: DispatchWorkItem?

    private let dwellDuration: TimeInterval = 0.8

    private let mainPanelHeight: CGFloat = 700
    private let collapsedPanelHeight: CGFloat = 110
    private let splitGap: CGFloat = 40

    private var splitOffsetY: CGFloat {
        (vm.state == .splitting || vm.state == .split) ? ((mainPanelHeight/2 + splitGap + collapsedPanelHeight/2)/2) : 0
    }

    var body: some View {
        Group {
            // Sichtbar in collapsedIdle und im finalen split-Zustand
            if vm.state == .collapsedIdle || vm.state == .split || vm.state == .splitting {
                ZStack {
                    // Hintergrund: standard glass
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.clear)
                        .glassBackgroundEffect()

                    // Inhalt: "GAMMA RAYS" + konzentrische Linien (vereinfachte Darstellung)
                    ZStack {
                        ForEach(0..<6, id: \.self) { i in
                            Circle()
                                .stroke(Color.white.opacity(0.35 - Double(i) * 0.04), lineWidth: 1)
                                .scaleEffect(0.35 + CGFloat(i) * 0.1)
                                .blur(radius: i == 0 ? 0 : 0.2)
                        }
                        Text("GAMMA\nRAYS")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .offset(y: splitOffsetY)
                .animation(.easeInOut(duration: 0.5), value: vm.state)
                .onHover { hovering in
                    isHovering = hovering
                    vm.setGazeCollapsed(hovering)
                    if hovering {
                        startDwell()
                    } else {
                        cancelDwell()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if vm.state == .collapsedIdle {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            vm.state = .expanding
                        }
                    }
                }
            } else {
                Color.clear
            }
        }
    }

    private func startDwell() {
        cancelDwell()
        let work = DispatchWorkItem {
            if isHovering && vm.state == .collapsedIdle {
                withAnimation(.easeInOut(duration: 0.6)) {
                    vm.state = .expanding
                }
            }
        }
        dwellWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dwellDuration, execute: work)
    }

    private func cancelDwell() {
        dwellWorkItem?.cancel()
        dwellWorkItem = nil
    }
}

struct SpectrometerSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 24
            let trackWidth: CGFloat = 80
            let trackHeight: CGFloat = geo.size.height - inset * 2
            let trackCorner: CGFloat = 26
            let knobDiameter: CGFloat = 64
            let knobRadius: CGFloat = knobDiameter / 2
            let centerX: CGFloat = geo.size.width / 2
            let trackRect = CGRect(
                x: centerX - trackWidth / 2,
                y: inset,
                width: trackWidth,
                height: trackHeight
            )

            ZStack {
                // Dunkler, schmaler Slot
                RoundedRectangle(cornerRadius: trackCorner)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: trackRect.width, height: trackRect.height)
                    .position(x: trackRect.midX, y: trackRect.midY)
                    .overlay(
                        // Glanzband in der Mitte (vertikaler Verlauf)
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.35),
                                .init(color: .white.opacity(0.35), location: 0.5),
                                .init(color: .clear, location: 0.65)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: trackCorner))
                        .frame(width: trackRect.width, height: trackRect.height)
                        .position(x: trackRect.midX, y: trackRect.midY)
                    )
                    .overlay(
                        // Sine-Wave im Slot
                        SineWaveShape(periods: 6)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            .frame(width: trackRect.width - 28, height: trackRect.height - 28)
                            .position(x: trackRect.midX, y: trackRect.midY)
                    )

                // Unsichtbarer, aber interaktiver Slider (drehen)
                VerticalSlider(value: $value)
                    .frame(width: trackRect.width, height: trackRect.height)
                    .position(x: trackRect.midX, y: trackRect.midY)
                    .opacity(0.01)

                // Knopf-Position basierend auf value (oben = 1, unten = 0)
                let yRange = (trackRect.minY + knobRadius) ... (trackRect.maxY - knobRadius)
                let yPos = CGFloat(1.0 - value) * (yRange.upperBound - yRange.lowerBound) + yRange.lowerBound

                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
                    .overlay(
                        Circle()
                            .fill(
                                RadialGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.05)], center: .topLeading, startRadius: 2, endRadius: knobDiameter)
                            )
                            .blur(radius: 0.5)
                    )
                    .position(x: trackRect.midX, y: yPos)
                    .allowsHitTesting(false) // Interaktion geht an den Slider darunter
            }
        }
    }
}

struct SineWaveShape: Shape {
    var periods: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let amplitude = rect.width * 0.33
        let twoPi = CGFloat.pi * 2

        path.move(to: CGPoint(x: midX, y: rect.minY))
        let steps = Int(rect.height)
        for i in 0...steps {
            let y = rect.minY + CGFloat(i)
            let t = (y - rect.minY) / rect.height
            let x = midX + sin(t * periods * twoPi) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

struct VerticalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil

    @ViewBuilder
    private var baseSlider: some View {
        if let step, step > 0 {
            Slider(value: $value, in: range, step: step)
        } else {
            Slider(value: $value, in: range)
        }
    }

    var body: some View {
        // Trick: erst breite festlegen, dann rotieren, dann Ziel-Frame setzen
        baseSlider
            .frame(width: 260)            // Länge der "Bahn" vor der Rotation
            .rotationEffect(.degrees(-90))
            .frame(width: 44, height: 260) // finaler vertikaler Frame
            .contentShape(Rectangle())     // zuverlässigere Hit-Tests nach Rotation
    }
}
