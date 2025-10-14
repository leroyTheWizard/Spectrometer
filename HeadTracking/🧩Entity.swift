import RealityKit
import ARKit
import SwiftUI

// Spawns the balls
enum 🧩Entity {
    static func majorBalls(numBalls: Int) -> [Entity] {
        let vals = (0..<numBalls).map { _ in Self.genericBall() }
        return vals
    }

    static func minorBalls(numBalls: Int) -> [Entity] {
        // should be green
        let vals = (0..<numBalls).map { _ in Self.genericBall() }
        return vals
    }
}

// Spawns each ball
private extension 🧩Entity {
    private static func genericBall(color: UIColor = .clear) -> Entity {
        let value = Entity()
//        let ball = ModelComponent(mesh: .generateSphere(radius: 0.005), materials: [UnlitMaterial(color: color)])
//        value.components.set([ball,
//                              OpacityComponent(opacity:0.6),
//                              CollisionComponent(shapes: [.generateSphere(radius:0.005)])])
        return value
    }
}
