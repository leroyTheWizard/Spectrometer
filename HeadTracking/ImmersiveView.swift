import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

@Observable
final class SpectrometerViewModel {
    var showSpectrometer: Bool = true
    var sliderValue: Double = 0.5 // 0 = dunkel (S/W), 1 = hell (farbig)
    var tintAmount: Double = 0.0   // 0..1, Stärke der Farbtönung

    // Mapping für globale Effekte
    var colorSaturation: Double { 1.0 - sliderValue } // unten = S/W, oben = farbig
    var overlayOpacity: Double { tintAmount * 0.6 }   // kräftigere Tönung fürs Debuggen

    func setGaze(onCollapsed gazing: Bool) {
        showSpectrometer = gazing
    }
    
    var isDragging = false
    var focusedInColorSpectrum: Bool = false
}

struct ImmersiveView: View {
    @State private var largeSphere = ModelEntity.init(mesh: .generateSphere(radius: 30), materials: [SimpleMaterial(color: .clear, isMetallic: false)])
    @State private var vm = SpectrometerViewModel()

    @State private var timer: Timer?

    // Ein Entity als 2D-Container für beide Zustände (kein Hintergrund, kein Clipping)
    private let containerPanel = Entity()
    private let containerPanel2 = Entity()
    private let containerPanelArm = Entity()
    
    @State private var entityHummingbird: Entity?
    
    // HandTracking
    var model: AppModel = .init()
    @State var sceneContent: Entity?
    @State var contentHolder: (any RealityViewContentProtocol)?

    var body: some View {
        RealityView { content, attachments in
            // HandTracking root
            content.add(self.model.rootEntity)
            self.model.setUpChildEntities()
            //self.model.makeAllJointsInvisible()
            contentHolder = content

            // Anker am rechten Zeigefinger (Index Tip)
            let indexTip = self.model.getJoint("rightIndexKnuckle")
            let rightWrist = self.model.getJoint("rightWrist")

            // Ein gemeinsamer Container für beide Zustände (2D-Logik)
            indexTip.addChild(containerPanel)
            // Leichter Offset, damit das Panel nicht im Finger steckt
            containerPanel.setPosition([0.03, 0.0, 0.0], relativeTo: indexTip)
            // Optional: lokale Ausrichtung setzen, falls gewünscht
            containerPanel.setOrientation(simd_quatf(angle: .pi/2, axis: [0,0,1]), relativeTo: indexTip)
            
            indexTip.addChild(containerPanel2)
            containerPanel2.setPosition([0.03, 0.0, 0.0], relativeTo: indexTip)
            containerPanel2.setOrientation(simd_quatf(angle: .pi/2, axis: [0,0,1]), relativeTo: indexTip)
            containerPanel2.setOrientation(simd_quatf(angle: .pi/2, axis: [1,0,0]), relativeTo: indexTip)
            
            // ⇨ Single Attachment für beide Fenster (kein Container-Hintergrund)
            if let containerEntity = attachments.entity(for: "spectrometer-container") {
                // Wichtig: Input für SwiftUI-Attachments aktivieren
                containerEntity.components.set(InputTargetComponent())
                containerPanel.addChild(containerEntity)
            }

            if let containerEntity2 = attachments.entity(for: "spectrometer-container-2") {
                // Wichtig: Input für SwiftUI-Attachments aktivieren
                containerEntity2.components.set(InputTargetComponent())
//                containerEntity2.components.set(OpacityComponent(opacity: 1))
                containerPanel2.addChild(containerEntity2)
            }
            
            rightWrist.addChild(containerPanelArm)
            // TODO: set position to move it more towards elbow
            // TODO: rotate to appear at the top of elbow
            
            if let containerEntityArm = attachments.entity(for: "spectrometer-container-arm") {
                // Wichtig: Input für SwiftUI-Attachments aktivieren
                containerEntityArm.components.set(InputTargetComponent())
                containerPanelArm.addChild(containerEntityArm)
            }
            
            largeSphere.components.set(OpacityComponent.init(opacity: Float(0.5)))
            print(largeSphere.components[ModelComponent.self]?.materials)
            largeSphere.scale *= .init(x: -1, y: 1, z: 1) // make it point inward
            content.add(largeSphere)
            
            if let exhibitionEntity = try? await Entity(named: "Exhibition", in: realityKitContentBundle), let hummingbirdEntity = exhibitionEntity.findEntity(named: "Hummingbird") {
                self.entityHummingbird = hummingbirdEntity
                content.add(exhibitionEntity)
            }
        } attachments: {
            Attachment(id: "spectrometer-container") {
                SpectrometerContainerView()
                    .environment(vm)
                    //.frame(width: 140, height: 850) // groß genug für beide Panels (700 + 40 + 110)
            }
            
            Attachment(id: "spectrometer-container-2") {
//                SpectrometerContainerView()
//                    .environment(vm)
                    //.frame(width: 140, height: 850) // groß genug für beide Panels (700 + 40 + 110)
            }
            
            Attachment(id: "spectrometer-container-arm") {
//                SpectrometerContainerView()
//                    .environment(vm)
                    //.frame(width: 140, height: 850) // groß genug für beide Panels (700 + 40 + 110)
            }
        }
        //HandTracking
        .task { self.model.run() }
        .task { self.model.observeAuthorizationStatus() }
        .upperLimbVisibility(.hidden)
        
        .saturation(vm.colorSaturation)
        .overlay(
            Color.red
                .opacity(vm.overlayOpacity)
                .blendMode(.multiply)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.35), value: vm.colorSaturation)
        .animation(.easeInOut(duration: 0.35), value: vm.overlayOpacity)
        .onChange(of: vm.sliderValue) { _, newValue in
            print("asdf ", newValue)
//            largeSphere.components[OpacityComponent.self]?.opacity = Float(newValue)
            
            guard let mesh = largeSphere.model?.mesh else {
                print("could not find mesh from large sphere")
                return
            }
            
            if vm.focusedInColorSpectrum {
//                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { _ in
//                    if vm.isDragging {
                        setSphereVisibleColorAppearance(value: Float(newValue))
//                    }
//                })
            } else {
                setSphereVisibility(value: Float(newValue))
            }
        }
    }
    
    func setSphereVisibleColorAppearance(value newValue: Float) {
        guard let mesh = largeSphere.model?.mesh else {
            print("could not find mesh from large sphere")
            return
        }

        switch newValue {
        case 0.35..<0.40:
            print("spectrum: red")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .red, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
        case 0.40..<0.45:
            print("spectrum: orange")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .orange, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
        case 0.45..<0.50:
            print("spectrum: yellow")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
        case 0.50..<0.55:
            print("spectrum: green")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .green, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
        case 0.55..<0.60:
            print("spectrum: blue")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .blue, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
        case 0.60..<0.65:
            print("spectrum: purple")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .purple, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
        default:
            print("above spectrum — focus out")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .black, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
            vm.focusedInColorSpectrum = false
        }
    }
    
    func setSphereVisibility(value newValue: Float) {
        guard let mesh = largeSphere.model?.mesh else {
            print("could not find mesh from large sphere")
            return
        }
        
        entityHummingbird?.components[OpacityComponent.self]?.opacity = (0.2..<0.4).contains(newValue) ? 1 : 0

        switch newValue {
        case 0.0..<0.2:
            print("1 rest no map")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .black, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
            vm.focusedInColorSpectrum = false
        case 0.2..<0.4:
            print("2 rest no map")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .black, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
            vm.focusedInColorSpectrum = false
        case 0.4..<0.6:
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .clear, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent


            print("3 TODO: now map 0...0.2 to 0 to 100") // the mapped mapping
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { _ in
                print("after 1 sec change scale")
                
                vm.focusedInColorSpectrum = true
                // TODO: change color based on the mapped mapping
                if vm.isDragging {
                    
                    setSphereVisibleColorAppearance(value: Float(newValue))
                }
            })
        case 0.6..<0.8:
            print("4 rest do not map")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .black, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
            vm.focusedInColorSpectrum = false
        case 0.8...1.0:
            print("5 rest do not map")
            let newModelComponent = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .black, isMetallic: false)])
            largeSphere.components[ModelComponent.self] = newModelComponent
            vm.focusedInColorSpectrum = false
        default: break
        }


    }
}

struct SpectrometerContainerView: View {
    @Environment(SpectrometerViewModel.self) private var vm

    private let mainPanelHeight: CGFloat = 700
    private let collapsedPanelHeight: CGFloat = 140

    var body: some View {
        HStack{
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let speed = lerp(from: 0.2, to: 2.0, t: vm.sliderValue) // turns per second
                let phase = CGFloat(time * speed * 2 * .pi)
                SineWaveShape(
                    periods: CGFloat(lerp(from: 0.5, to: 12.0, t: vm.sliderValue)),
                    phase: phase
                )
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .frame(width: 80, height: 700)
            }
            
            VStack {
                Group {
                    if vm.showSpectrometer {
                        Spectrometer()
                            .frame(width: collapsedPanelHeight, height: mainPanelHeight)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity),
                                    removal: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity)
                                )
                            )
                    } else {
                        Color.clear
                            .frame(width: collapsedPanelHeight, height: mainPanelHeight)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: vm.showSpectrometer)
                
                FrequencyCategorie()
                    .frame(width: collapsedPanelHeight, height: collapsedPanelHeight)
            }
            .frame(width: collapsedPanelHeight, height: mainPanelHeight + collapsedPanelHeight)
        }}
}
    

// MARK: - SwiftUI Panel mit custom spectrometer-style slider und Glas-Hintergrund
struct Spectrometer: View {
    @Environment(SpectrometerViewModel.self) private var vm

    private let mainPanelHeight: CGFloat = 700

    var body: some View {
        @Bindable var vm = self.vm
        ZStack {
            SpectrometerSlider(value: $vm.sliderValue)
                .padding(20)
                .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(radius: 12)
            VStack {
                Spacer()
                Text(String(format: "Slider: %.2f", vm.sliderValue))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
            }
            .allowsHitTesting(false)
#if targetEnvironment(simulator)
                .contentShape(Rectangle())
                .onTapGesture {
                    vm.setGaze(onCollapsed: false)
                }
#endif
        }
    }
}

struct FrequencyCategorie: View {
    @Environment(SpectrometerViewModel.self) private var vm

    private let collapsedPanelHeight: CGFloat = 110

    var body: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering in
//            vm.setGaze(onCollapsed: hovering)
        }
#if targetEnvironment(simulator)
        .onTapGesture {
            vm.setGaze(onCollapsed: true)
        }
        .onLongPressGesture {
            vm.tintAmount = (vm.tintAmount == 0) ? 1 : 0
        }
#endif
        .contentShape(Rectangle())
    }
}

struct SpectrometerSlider: View {
    @Environment(SpectrometerViewModel.self) private var vm
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 24
            let trackWidth: CGFloat = 52
            let trackHeight: CGFloat = geo.size.height - inset * 2
            let trackCorner: CGFloat = 60
            let knobDiameter: CGFloat = 44
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
                    .fill(Color.black.opacity(0.8))
                    .frame(width: trackRect.width, height: trackRect.height)
                    .position(x: trackRect.midX, y: trackRect.midY)
                    .overlay(
                        // Glanzband in der Mitte (vertikaler Verlauf)
                        LinearGradient(
                            gradient: Gradient(stops: vm.focusedInColorSpectrum ? [
                                .init(color: .clear, location: 0.35),
                                .init(color: .white.opacity(0.5), location: 0.5),
                                .init(color: .clear, location: 0.65)
                            ] : [
                                .init(color: .clear, location: 0.45),
                                .init(color: .white.opacity(0.5), location: 0.5),
                                .init(color: .clear, location: 0.55)
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
                        Group {
                            if vm.focusedInColorSpectrum {
                                // Farbverlauf exakt nur im Bereich 0.35..0.65 (ohne Mask), breiter für seitliches Bleeding
                                let bandHeight = trackRect.height * 0.30 // 0.65 - 0.35 = 0.30
                                let bandCenterY = trackRect.minY + trackRect.height * 0.50 // Mitte bei 0.5
                                LinearGradient(
                                    colors: [
                                        Color.purple.opacity(0.5),
                                        Color.blue.opacity(0.5),
                                        Color.green.opacity(0.5),
                                        Color.yellow.opacity(0.5),
                                        Color.orange.opacity(0.5),
                                        Color.red.opacity(0.5)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .blur(radius: 20)
                                .opacity(0.9)
                                .frame(width: trackRect.width + 40, height: bandHeight)
                                .position(x: trackRect.midX, y: bandCenterY)
                            }
                        }
                    )
                    .overlay(
                        TimelineView(.animation) { context in
                            let time = context.date.timeIntervalSinceReferenceDate
                            let speed = lerp(from: 0.2, to: 2.0, t: vm.sliderValue) // turns per second
                            let phase = CGFloat(time * speed * 2 * .pi)
                            SineWaveShape(
                                periods: CGFloat(lerp(from: 0.5, to: 12.0, t: vm.sliderValue)),
                                phase: phase
                            )
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            .frame(width: trackRect.width - 28, height: trackRect.height - 28)
                            .position(x: trackRect.midX, y: trackRect.midY)
                        }
                    )

                // Interaktionsfläche mit Drag-Geste (keine Rotation nötig)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: trackRect.width, height: trackRect.height)
                    .position(x: trackRect.midX, y: trackRect.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let locationY = gesture.location.y
                                let clampedY = min(max(locationY, trackRect.minY), trackRect.maxY)
                                let t = (clampedY - trackRect.minY) / (trackRect.height)
                                let newValue = Double(1.0 - t)
                                self.value = min(max(newValue, 0.0), 1.0)
                                print("still dragging")
                                vm.isDragging = true
                            }
                            .onEnded({ _ in
                                print("drag ended")
                                vm.isDragging = false
                            })
                    )

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

@inline(__always)
func lerp(from a: Double, to b: Double, t: Double) -> Double {
    return a + (b - a) * t
}

struct SineWaveShape: Shape {
    var periods: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

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
            let x = midX + sin(t * periods * twoPi + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

