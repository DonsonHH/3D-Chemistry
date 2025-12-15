//
//  PhysicsSceneKitView.swift
//  3D-Chemistry
//
//  Created by ypx on 2025/11/26.
//

import SwiftUI
import SceneKit
import QuartzCore

#if os(macOS)
struct PhysicsSceneKitView: NSViewRepresentable {
    var atoms: [Atom]
    var manualBonds: [ManualBond]
    var selectedHole: (atomIndex: Int, holeIndex: Int)?
    var physicsEnabled: Bool
    var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
    var onHoleTap: ((Int, Int) -> Void)?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        
        // 创建物理场景
        let (scene, manager) = PhysicsMoleculeScene.makeScene(atoms: atoms, manualBonds: manualBonds, selectedHole: selectedHole)
        view.scene = scene
        context.coordinator.physicsManager = manager
        
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .black
        
        // 性能优化设置
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling2X  // 降低抗锯齿级别
        
        // 设置渲染代理以便每帧更新物理
        view.delegate = context.coordinator
        view.rendersContinuously = true  // 持续渲染
        view.isPlaying = true
        
        // 添加点击手势（用于点击孔）
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        clickGesture.delegate = context.coordinator
        view.addGestureRecognizer(clickGesture)
        
        // 添加拖拽手势
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        
        // 添加长按手势
        let longPressGesture = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = context.coordinator
        view.addGestureRecognizer(longPressGesture)
        
        context.coordinator.sceneView = view
        context.coordinator.onAtomLongPress = onAtomLongPress
        context.coordinator.onHoleTap = onHoleTap
        context.coordinator.physicsEnabled = physicsEnabled
        
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let atomsChanged = !atomsAreEqual(context.coordinator.lastAtoms, atoms)
        let bondsChanged = context.coordinator.lastManualBonds != manualBonds
        let holeChanged = context.coordinator.lastSelectedHole?.atomIndex != selectedHole?.atomIndex ||
                         context.coordinator.lastSelectedHole?.holeIndex != selectedHole?.holeIndex
        
        if atomsChanged || bondsChanged || holeChanged {
            // 保存相机的位置和旋转
            var savedCameraPosition: SCNVector3?
            var savedCameraEulerAngles: SCNVector3?
            if let oldCamera = nsView.pointOfView {
                savedCameraPosition = oldCamera.position
                savedCameraEulerAngles = oldCamera.eulerAngles
            }
            
            // 保留用户拖动后的原子位置
            var updatedAtoms = atoms
            if let scene = nsView.scene {
                for (index, atom) in updatedAtoms.enumerated() {
                    if let oldNode = scene.rootNode.childNode(withName: "\(atom.element)#\(index)", recursively: false) {
                        updatedAtoms[index] = Atom(
                            id: atom.id,
                            element: atom.element,
                            position: oldNode.presentation.position,
                            radius: atom.radius
                        )
                    }
                }
            }
            
            // 重建物理场景
            let (newScene, manager) = PhysicsMoleculeScene.makeScene(atoms: updatedAtoms, manualBonds: manualBonds, selectedHole: selectedHole)
            nsView.scene = newScene
            context.coordinator.physicsManager = manager
            
            // 恢复相机的位置和旋转
            if let newCamera = nsView.pointOfView,
               let position = savedCameraPosition,
               let eulerAngles = savedCameraEulerAngles {
                newCamera.position = position
                newCamera.eulerAngles = eulerAngles
            }
            
            context.coordinator.lastAtoms = atoms
            context.coordinator.lastManualBonds = manualBonds
            context.coordinator.lastSelectedHole = selectedHole
        }
        
        context.coordinator.sceneView = nsView
        context.coordinator.onAtomLongPress = onAtomLongPress
        context.coordinator.onHoleTap = onHoleTap
        context.coordinator.physicsEnabled = physicsEnabled
        
        // 更新物理模拟状态
        nsView.isPlaying = physicsEnabled
    }
    
    private func atomsAreEqual(_ lhs: [Atom], _ rhs: [Atom]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (index, atom) in lhs.enumerated() {
            let other = rhs[index]
            if atom.element != other.element || abs(atom.radius - other.radius) > 0.001 {
                return false
            }
        }
        return true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSGestureRecognizerDelegate, SCNSceneRendererDelegate {
        weak var sceneView: SCNView?
        var physicsManager: PhysicsMoleculeScene?
        var selectedNode: SCNNode?
        var isDragging = false
        var dragPlanePosition: SCNVector3?
        var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
        var onHoleTap: ((Int, Int) -> Void)?
        var lastAtoms: [Atom] = []
        var lastManualBonds: [ManualBond] = []
        var lastSelectedHole: (atomIndex: Int, holeIndex: Int)?
        var physicsEnabled = true
        
        // MARK: - SCNSceneRendererDelegate
        
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // 每帧更新物理
            if physicsEnabled {
                physicsManager?.updatePhysics()
            }
        }
        
        // MARK: - 手势识别
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            if gestureRecognizer is NSClickGestureRecognizer {
                return true
            }
            
            guard let view = gestureRecognizer.view as? SCNView else { return false }
            let location = gestureRecognizer.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            return hitResults.contains(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true })
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let location = gesture.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            
            for hit in hitResults {
                if let nodeName = hit.node.name, nodeName.starts(with: "hole_") {
                    let holeIndexStr = nodeName.replacingOccurrences(of: "hole_", with: "")
                    if let holeIndex = Int(holeIndexStr) {
                        if let atomNode = hit.node.parent,
                           let atomName = atomNode.name,
                           let atomIndex = extractAtomIndex(from: atomName) {
                            onHoleTap?(atomIndex, holeIndex)
                            return
                        }
                    }
                }
            }
        }
        
        private func extractAtomIndex(from nodeName: String) -> Int? {
            let parts = nodeName.split(separator: "#")
            guard parts.count == 2 else { return nil }
            return Int(parts[1])
        }
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let location = gesture.location(in: view)
            
            switch gesture.state {
            case .began:
                let hitResults = view.hitTest(location, options: [:])
                if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true }) {
                    selectedNode = hit.node
                    isDragging = true
                    dragPlanePosition = hit.node.position
                    view.allowsCameraControl = false
                    
                    // 开始拖拽时，将原子设为运动学物体
                    physicsManager?.dragAtom(hit.node, to: hit.node.position)
                }
                
            case .changed:
                guard isDragging, let node = selectedNode, let camera = view.pointOfView else { return }
                
                if let newPosition = unproject(point: location, onPlaneAt: dragPlanePosition ?? node.position, camera: camera, view: view) {
                    // 直接更新位置（物理管理器会处理）
                    physicsManager?.dragAtom(node, to: newPosition)
                }
                
            case .ended, .cancelled:
                if let node = selectedNode {
                    // 释放原子，恢复物理模拟
                    physicsManager?.releaseAtom(node)
                }
                
                isDragging = false
                selectedNode = nil
                dragPlanePosition = nil
                view.allowsCameraControl = true
                
            default:
                break
            }
        }
        
        @objc func handleLongPress(_ gesture: NSPressGestureRecognizer) {
            guard let view = gesture.view as? SCNView,
                  gesture.state == .began else { return }
            
            let location = gesture.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            
            if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true }),
               let scene = view.scene {
                let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere && $0.name?.starts(with: "hole_") != true }
                if let index = atomNodes.firstIndex(of: hit.node) {
                    let atomPosition = hit.node.presentation.position
                    onAtomLongPress?(index, location, atomPosition)
                }
            }
        }
        
        func unproject(point: CGPoint, onPlaneAt planePosition: SCNVector3, camera: SCNNode, view: SCNView) -> SCNVector3? {
            let cameraTransform = camera.transform
            let cameraForward = SCNVector3(-cameraTransform.m31, -cameraTransform.m32, -cameraTransform.m33)
            
            let nearPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let farPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            
            let rayDirection = SCNVector3(
                farPoint.x - nearPoint.x,
                farPoint.y - nearPoint.y,
                farPoint.z - nearPoint.z
            )
            
            let denom = dotProduct(rayDirection, cameraForward)
            guard abs(denom) > 1e-6 else { return nil }
            
            let diff = SCNVector3(
                planePosition.x - nearPoint.x,
                planePosition.y - nearPoint.y,
                planePosition.z - nearPoint.z
            )
            
            let t = dotProduct(diff, cameraForward) / denom
            
            return SCNVector3(
                nearPoint.x + rayDirection.x * t,
                nearPoint.y + rayDirection.y * t,
                nearPoint.z + rayDirection.z * t
            )
        }
        
        func dotProduct(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            return a.x * b.x + a.y * b.y + a.z * b.z
        }
    }
}

#else
// MARK: - iOS Version

struct PhysicsSceneKitView: UIViewRepresentable {
    var atoms: [Atom]
    var manualBonds: [ManualBond]
    var selectedHole: (atomIndex: Int, holeIndex: Int)?
    var physicsEnabled: Bool
    var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
    var onHoleTap: ((Int, Int) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        
        let (scene, manager) = PhysicsMoleculeScene.makeScene(atoms: atoms, manualBonds: manualBonds, selectedHole: selectedHole)
        view.scene = scene
        context.coordinator.physicsManager = manager
        
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .black
        
        // 性能优化设置
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling2X  // 降低抗锯齿级别
        
        view.delegate = context.coordinator
        view.rendersContinuously = true
        view.isPlaying = true
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        view.addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = context.coordinator
        view.addGestureRecognizer(longPressGesture)
        
        context.coordinator.sceneView = view
        context.coordinator.onAtomLongPress = onAtomLongPress
        context.coordinator.onHoleTap = onHoleTap
        context.coordinator.physicsEnabled = physicsEnabled
        
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let atomsChanged = !atomsAreEqual(context.coordinator.lastAtoms, atoms)
        let bondsChanged = context.coordinator.lastManualBonds != manualBonds
        let holeChanged = context.coordinator.lastSelectedHole?.atomIndex != selectedHole?.atomIndex ||
                         context.coordinator.lastSelectedHole?.holeIndex != selectedHole?.holeIndex
        
        if atomsChanged || bondsChanged || holeChanged {
            var savedCameraPosition: SCNVector3?
            var savedCameraEulerAngles: SCNVector3?
            if let oldCamera = uiView.pointOfView {
                savedCameraPosition = oldCamera.position
                savedCameraEulerAngles = oldCamera.eulerAngles
            }
            
            var updatedAtoms = atoms
            if let scene = uiView.scene {
                for (index, atom) in updatedAtoms.enumerated() {
                    if let oldNode = scene.rootNode.childNode(withName: "\(atom.element)#\(index)", recursively: false) {
                        updatedAtoms[index] = Atom(
                            id: atom.id,
                            element: atom.element,
                            position: oldNode.presentation.position,
                            radius: atom.radius
                        )
                    }
                }
            }
            
            let (newScene, manager) = PhysicsMoleculeScene.makeScene(atoms: updatedAtoms, manualBonds: manualBonds, selectedHole: selectedHole)
            uiView.scene = newScene
            context.coordinator.physicsManager = manager
            
            if let newCamera = uiView.pointOfView,
               let position = savedCameraPosition,
               let eulerAngles = savedCameraEulerAngles {
                newCamera.position = position
                newCamera.eulerAngles = eulerAngles
            }
            
            context.coordinator.lastAtoms = atoms
            context.coordinator.lastManualBonds = manualBonds
            context.coordinator.lastSelectedHole = selectedHole
        }
        
        context.coordinator.sceneView = uiView
        context.coordinator.onAtomLongPress = onAtomLongPress
        context.coordinator.onHoleTap = onHoleTap
        context.coordinator.physicsEnabled = physicsEnabled
        
        uiView.isPlaying = physicsEnabled
    }
    
    private func atomsAreEqual(_ lhs: [Atom], _ rhs: [Atom]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (index, atom) in lhs.enumerated() {
            let other = rhs[index]
            if atom.element != other.element || abs(atom.radius - other.radius) > 0.001 {
                return false
            }
        }
        return true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate, SCNSceneRendererDelegate {
        weak var sceneView: SCNView?
        var physicsManager: PhysicsMoleculeScene?
        var selectedNode: SCNNode?
        var isDragging = false
        var dragPlanePosition: SCNVector3?
        var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
        var onHoleTap: ((Int, Int) -> Void)?
        var lastAtoms: [Atom] = []
        var lastManualBonds: [ManualBond] = []
        var lastSelectedHole: (atomIndex: Int, holeIndex: Int)?
        var physicsEnabled = true
        
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if physicsEnabled {
                physicsManager?.updatePhysics()
            }
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UITapGestureRecognizer {
                return true
            }
            
            guard let view = gestureRecognizer.view as? SCNView else { return false }
            let location = gestureRecognizer.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            return hitResults.contains(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true })
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let location = gesture.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            
            for hit in hitResults {
                if let nodeName = hit.node.name, nodeName.starts(with: "hole_") {
                    let holeIndexStr = nodeName.replacingOccurrences(of: "hole_", with: "")
                    if let holeIndex = Int(holeIndexStr) {
                        if let atomNode = hit.node.parent,
                           let atomName = atomNode.name,
                           let atomIndex = extractAtomIndex(from: atomName) {
                            onHoleTap?(atomIndex, holeIndex)
                            return
                        }
                    }
                }
            }
        }
        
        private func extractAtomIndex(from nodeName: String) -> Int? {
            let parts = nodeName.split(separator: "#")
            guard parts.count == 2 else { return nil }
            return Int(parts[1])
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let location = gesture.location(in: view)
            
            switch gesture.state {
            case .began:
                let hitResults = view.hitTest(location, options: [:])
                if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true }) {
                    selectedNode = hit.node
                    isDragging = true
                    dragPlanePosition = hit.node.position
                    view.allowsCameraControl = false
                    
                    physicsManager?.dragAtom(hit.node, to: hit.node.position)
                }
                
            case .changed:
                guard isDragging, let node = selectedNode, let camera = view.pointOfView else { return }
                
                if let newPosition = unproject(point: location, onPlaneAt: dragPlanePosition ?? node.position, camera: camera, view: view) {
                    physicsManager?.dragAtom(node, to: newPosition)
                }
                
            case .ended, .cancelled:
                if let node = selectedNode {
                    physicsManager?.releaseAtom(node)
                }
                
                isDragging = false
                selectedNode = nil
                dragPlanePosition = nil
                view.allowsCameraControl = true
                
            default:
                break
            }
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view as? SCNView,
                  gesture.state == .began else { return }
            
            let location = gesture.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            
            if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true }),
               let scene = view.scene {
                let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere && $0.name?.starts(with: "hole_") != true }
                if let index = atomNodes.firstIndex(of: hit.node) {
                    let atomPosition = hit.node.presentation.position
                    onAtomLongPress?(index, location, atomPosition)
                }
            }
        }
        
        func unproject(point: CGPoint, onPlaneAt planePosition: SCNVector3, camera: SCNNode, view: SCNView) -> SCNVector3? {
            let cameraTransform = camera.transform
            let cameraForward = SCNVector3(-cameraTransform.m31, -cameraTransform.m32, -cameraTransform.m33)
            
            let nearPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let farPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            
            let rayDirection = SCNVector3(
                farPoint.x - nearPoint.x,
                farPoint.y - nearPoint.y,
                farPoint.z - nearPoint.z
            )
            
            let denom = dotProduct(rayDirection, cameraForward)
            guard abs(denom) > 1e-6 else { return nil }
            
            let diff = SCNVector3(
                planePosition.x - nearPoint.x,
                planePosition.y - nearPoint.y,
                planePosition.z - nearPoint.z
            )
            
            let t = dotProduct(diff, cameraForward) / denom
            
            return SCNVector3(
                nearPoint.x + rayDirection.x * t,
                nearPoint.y + rayDirection.y * t,
                nearPoint.z + rayDirection.z * t
            )
        }
        
        func dotProduct(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            return a.x * b.x + a.y * b.y + a.z * b.z
        }
    }
}
#endif
