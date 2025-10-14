/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The model containing the root entities and the functions to toggle between following and launching at the head position.
*/

import SwiftUI
import RealityKit
import ARKit

/// Maintains the app-wide state.
@MainActor
@Observable
class AppModel {
    private(set) var authorizationStatus: ARKitSession.AuthorizationStatus?
    var presentPanel: 🛠️Panel? = nil
    var selectedLeft: Bool = false
    var selectedRight: Bool = false
    
    // Public var that maintains each hand's last handAnchor + joints
    var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }
    
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    
    let rootEntity = Entity()
    
    // Take only 3 joints per finger + wrist (except thumb has two)
        // Labeled in blue
    let majorHandJoints: [HandSkeleton.JointName] = [
        .thumbIntermediateBase, .thumbTip,
        .indexFingerIntermediateBase, .indexFingerKnuckle, .indexFingerTip,
        .middleFingerIntermediateBase, .middleFingerKnuckle, .middleFingerTip,
        .ringFingerIntermediateBase, .ringFingerKnuckle, .ringFingerTip,
        .littleFingerIntermediateBase, .littleFingerKnuckle, .littleFingerTip,
        .wrist
    ]
    
    // Labeled in green
    let minorHandJoints: [HandSkeleton.JointName] = [
        .thumbKnuckle, .thumbIntermediateTip,
        .indexFingerMetacarpal, .indexFingerIntermediateTip,
        .middleFingerMetacarpal, .middleFingerIntermediateTip,
        .ringFingerMetacarpal, .ringFingerIntermediateTip,
        .littleFingerMetacarpal, .littleFingerIntermediateTip,
        .forearmArm, .forearmWrist
    ]

    // only one duplicate, the thumbIntermediateBase
    
    let majorBalls: [Entity] = 🧩Entity.majorBalls(numBalls: 30);
    let minorBalls: [Entity] = 🧩Entity.minorBalls(numBalls: 24);

    
    func setUpChildEntities() {
        self.majorBalls.forEach { self.rootEntity.addChild($0) }
        self.minorBalls.forEach { self.rootEntity.addChild($0) }
    }
    
    // Check that we have ARKit authorization for hand and head tracking
    func observeAuthorizationStatus() {
        Task {
            self.authorizationStatus = await self.session.queryAuthorization(for: [.handTracking])[.handTracking]
            
            for await update in self.session.events {
                if case .authorizationChanged(let type, let status) = update {
                    if type == .handTracking { self.authorizationStatus = status }
                } else {
                    print("Another session event \(update).")
                }
            }
        }
    }
    
    func run() {
        Task { @MainActor in
            do {
                try await self.session.run([self.handTracking])
                await self.processHandUpdates()
            } catch {
                print(error)
            }
        }
    }

    // Add function that detects custom tap gestures
    func detectCustomTaps() -> Int? {
        // Make sure both hands are tracked rn
        guard let leftHandAnchor = latestHandTracking.left,
              let rightHandAnchor = latestHandTracking.right,
              leftHandAnchor.isTracked, rightHandAnchor.isTracked else {
            return nil
        }
        
        if (touching("rightThumbTip", "leftThumbTip")){
            colorJoint("rightThumbTip")
            colorJoint("leftThumbTip")
        } else{
            colorJoint("rightThumbTip")
            colorJoint("leftThumbTip")
        }
         
        return 0
    }
    
    public var leftPosition: SIMD3<Float> {
        self.majorBalls[5].position
    }
    
    public var rightPosition: SIMD3<Float> {
        self.majorBalls[21].position
    }
    
    
    
    // Variables that determine "close" and "touching" for joints
    var closeToThresh: Float = 0.05;
    var touchingThresh: Float = 0.015;

    let rightHandOffset = 15;
    var jointMapping: [String: Int] = [:]
    
    init() {
        jointMapping = [
            "leftThumbBase": 0, "leftThumbTip": 1,
            "leftIndexBase": 2, "leftIndexKnuckle": 3, "leftIndexTip": 4,
            "leftMiddleBase": 5, "leftMiddleKnuckle": 6, "leftMiddleTip": 7,
            "leftRingBase": 8, "leftRingKnuckle": 9, "leftRingTip": 10,
            "leftPinkyBase": 11, "leftPinkyKnuckle": 12, "leftPinkyTip": 13,
            "leftWrist": 14,
            "rightThumbBase": rightHandOffset + 0, "rightThumbTip": rightHandOffset + 1,
            "rightIndexBase": rightHandOffset + 2, "rightIndexKnuckle": rightHandOffset + 3, "rightIndexTip": rightHandOffset + 4,
            "rightMiddleBase": rightHandOffset + 5, "rightMiddleKnuckle": rightHandOffset + 6, "rightMiddleTip": rightHandOffset + 7,
            "rightRingBase": rightHandOffset + 8, "rightRingKnuckle": rightHandOffset + 9, "rightRingTip": rightHandOffset + 10,
            "rightPinkyBase": rightHandOffset + 11, "rightPinkyKnuckle": rightHandOffset + 12, "rightPinkyTip": rightHandOffset + 13,
            "rightWrist": rightHandOffset + 14
        ]
        
//        lighter = await 🧩Entity.lighter()!;
    }
    
    
    /// Keeps track of whether the toggle is in head-position or follow mode.
    var headTrackState: HeadTrackState = .headPosition
    
    /// Keeps track of whether the immersive space is open.
    var isImmersiveSpaceOpen: Bool = false
    
    /// Track the state of the toggle.
    /// Follow: Uses `queryDeviceAnchor` to follow the device's position.
    /// HeadPosition: Uses `AnchorEntity` to launch at the head position in front of the wearer.
    enum HeadTrackState: String, CaseIterable {
        case follow
        case headPosition = "head-position"
    }
}

// We're gonna write the natural language hand query type stuff here. Optional threshold param
extension AppModel {
    func getJoint(_ jointname: String) -> Entity {
        return self.majorBalls[jointMapping[jointname]!]
    }
    
    func positionOfJoint(_ jointName: String) -> simd_float3? {
//        return jointMapping[jointName].flatMap { self.majorBalls[$0].position }
        return self.majorBalls[jointMapping[jointName]!].position
    }

    func jointDist(_ joint1: String, _ joint2: String) -> Float {
        let pos1 = self.positionOfJoint(joint1)!
        let pos2 = self.positionOfJoint(joint2)!
        return distance(pos1, pos2)
    }

    func closeTo(_ joint1: String, _ joint2: String, thresh: Float = -1) -> Bool {
        let thresh = thresh < 0 ? closeToThresh : thresh
        return jointDist(joint1, joint2) < thresh
    }

    func closeTo(_ joints: [String], thresh: Float = -1) -> Bool {
        let positions = joints.compactMap { positionOfJoint($0) }
        let dists = zip(positions, positions[1...]).map { distance($0, $1) }
        return dists.allSatisfy { $0 < thresh }
    }

    func touching(_ joint1: String, _ joint2: String, thresh: Float = -1) -> Bool {
        let thresh = thresh < 0 ? touchingThresh : thresh
        return jointDist(joint1, joint2) < thresh
    }

    // Currently this finds the avg of distances from first joint to all others. This is not preferred (I wanted pair-wise avg min jointdist) but kinda works for now.
    func touching(_ joints: [String], thresh: Float = -1) -> Bool {
        let thresh = thresh < 0 ? touchingThresh : thresh
        let positions = joints.compactMap { positionOfJoint($0) }
         let dists = zip(positions, positions[1...]).map { distance($0, $1) }
        return dists.reduce(0, +) / Float(dists.count) < thresh
    }

    func makeAllJointsInvisible() {
        for ball in self.majorBalls {
            ball.components.set(OpacityComponent(opacity:0))
        }
        for ball in self.minorBalls {
            ball.components.set(OpacityComponent(opacity:0))
        }
    }
    
    
    // Convenience function to change the color of a joint ball
    func colorJointI(_ jointIndex: Int, _ color: UIColor = .clear) {
//        self.majorBalls[jointIndex].components.set(ModelComponent(mesh: .generateSphere(radius: 0.005), materials: [UnlitMaterial(color: color)]))
    }

    func colorJoint(_ jointName: String, _ color: UIColor = .clear) {
        colorJointI(jointMapping[jointName]!, color)
    }

    func colorJoints(_ jointNames: [String], _ color: UIColor = .clear) {
         for jointName in jointNames {
             colorJoint(jointName, color)
         }
    }
}


private extension AppModel {
    private func processHandUpdates() async {
        for await update in self.handTracking.anchorUpdates {
            let handAnchor = update.anchor
            guard handAnchor.isTracked else { continue }
            
            // Update published hand pose
            if handAnchor.chirality == .left {
                latestHandTracking.left = handAnchor
            } else if handAnchor.chirality == .right { // Update right hand info.
                latestHandTracking.right = handAnchor
            }

            // Update ball positions for each joint. If it's the left hand, start at 0, if it's the right hand, start at 16.
            var start = handAnchor.chirality == .left ? 0 : majorHandJoints.count
            for i in 0..<(majorHandJoints.count) {
                let pos = handAnchor.handSkeleton?.joint(majorHandJoints[i])
                let worldPos = handAnchor.originFromAnchorTransform * pos!.anchorFromJointTransform
                self.majorBalls[i + start].setTransformMatrix(worldPos, relativeTo:nil)
            }
            // Minor joints now
            start = handAnchor.chirality == .left ? 0 : minorHandJoints.count
            for i in 0..<(minorHandJoints.count) {
                let pos = handAnchor.handSkeleton?.joint(minorHandJoints[i])
                let worldPos = handAnchor.originFromAnchorTransform * pos!.anchorFromJointTransform
                self.minorBalls[i + start].setTransformMatrix(worldPos, relativeTo:nil)
            }
        }
    }
}
