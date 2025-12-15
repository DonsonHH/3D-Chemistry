//
//  SceneKitView.swift
//  3D-Chemistry
//
//  Created by ypx on 2025/11/12.
//

import SwiftUI
import SceneKit
import QuartzCore

#if os(macOS)
struct SceneKitView: NSViewRepresentable {
    var atoms: [Atom]
    var manualBonds: [ManualBond]
    var selectedHole: (atomIndex: Int, holeIndex: Int)?
    var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
    var onHoleTap: ((Int, Int) -> Void)?  // atomIndex, holeIndex

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = MoleculeScene.makeScene(atoms: atoms, manualBonds: manualBonds)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .black
        
        // 添加点击手势（用于点击孔）
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        clickGesture.delegate = context.coordinator
        view.addGestureRecognizer(clickGesture)
        
        // 添加拖拽手势，设置为不阻止其他手势
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
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        // 在 atoms 数组或 manualBonds 变化时重建场景
        let atomsChanged = !atomsAreEqual(context.coordinator.lastAtoms, atoms)
        let bondsChanged = context.coordinator.lastManualBonds != manualBonds
        
        if atomsChanged || bondsChanged {
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
                // 提取旧场景中每个原子的当前位置
                for (index, atom) in updatedAtoms.enumerated() {
                    if let oldNode = scene.rootNode.childNode(withName: "\(atom.element)#\(index)", recursively: false) {
                        // 保留原子 id，防止标记丢失
                        updatedAtoms[index] = Atom(
                            id: atom.id,
                            element: atom.element,
                            position: oldNode.position,
                            radius: atom.radius
                        )
                    }
                }
            }
            
            nsView.scene = MoleculeScene.makeScene(atoms: updatedAtoms, manualBonds: manualBonds)
            
            // 恢复相机的位置和旋转
            if let newCamera = nsView.pointOfView,
               let position = savedCameraPosition,
               let eulerAngles = savedCameraEulerAngles {
                newCamera.position = position
                newCamera.eulerAngles = eulerAngles
            }
            
            context.coordinator.lastAtoms = atoms
            context.coordinator.lastManualBonds = manualBonds
        }
        context.coordinator.sceneView = nsView
        context.coordinator.onAtomLongPress = onAtomLongPress
        context.coordinator.onHoleTap = onHoleTap
    }
    
    private func atomsAreEqual(_ lhs: [Atom], _ rhs: [Atom]) -> Bool {
        // 首先检查数量是否相同
        guard lhs.count == rhs.count else { return false }
        
        // 如果数量相同，逐个比较元素类型和半径
        // 注意：我们不比较position，因为用户可以拖动原子改变位置
        for (index, atom) in lhs.enumerated() {
            let other = rhs[index]
            if atom.element != other.element || 
               abs(atom.radius - other.radius) > 0.001 {
                return false
            }
        }
        return true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSGestureRecognizerDelegate {
        weak var sceneView: SCNView?
        var selectedNode: SCNNode?
        var isDragging = false
        var dragPlanePosition: SCNVector3?
        var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
        var onHoleTap: ((Int, Int) -> Void)?
        var lastAtoms: [Atom] = []
        var lastManualBonds: [ManualBond] = []
        
        // 手势识别器代理方法：只有在点击到原子时才开始识别拖拽
        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            // 点击手势始终允许
            if gestureRecognizer is NSClickGestureRecognizer {
                return true
            }
            
            guard let view = gestureRecognizer.view as? SCNView else { return false }
            let location = gestureRecognizer.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            // 只有点击到球体（原子）时才允许拖拽手势开始
            return hitResults.contains(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true })
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let location = gesture.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            
            // 检查是否点击了孔
            for hit in hitResults {
                if let nodeName = hit.node.name, nodeName.starts(with: "hole_") {
                    // 找到孔的索引
                    let holeIndexStr = nodeName.replacingOccurrences(of: "hole_", with: "")
                    if let holeIndex = Int(holeIndexStr) {
                        // 找到原子索引（孔的父节点是原子）
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
            // 从 "Element#Index" 格式提取索引
            let parts = nodeName.split(separator: "#")
            guard parts.count == 2 else { return nil }
            return Int(parts[1])
        }
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let location = gesture.location(in: view)
            
            switch gesture.state {
            case .began:
                // 检测点击的节点
                let hitResults = view.hitTest(location, options: [:])
                if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere }) {
                    selectedNode = hit.node
                    isDragging = true
                    dragPlanePosition = hit.node.position
                    // 暂时禁用相机控制
                    view.allowsCameraControl = false
                }
                
            case .changed:
                guard isDragging, let node = selectedNode, let camera = view.pointOfView else { return }
                
                // 将屏幕坐标转换为3D空间坐标
                if let newPosition = unproject(point: location, onPlaneAt: dragPlanePosition ?? node.position, camera: camera, view: view) {
                    node.position = newPosition
                }
                
                // 实时更新与该原子相连的键
                updateBonds(for: node, in: view.scene!, temporary: true)
                
            case .ended, .cancelled:
                if let node = selectedNode, let scene = view.scene {
                    // 松开后尝试自动吸附成键
                    snapToNearbyAtoms(node: node, in: scene)
                }
                
                isDragging = false
                selectedNode = nil
                dragPlanePosition = nil
                // 重新启用相机控制
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
            
            if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere }),
               let scene = view.scene {
                let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere }
                if let index = atomNodes.firstIndex(of: hit.node) {
                    let atomPosition = hit.node.position
                    onAtomLongPress?(index, location, atomPosition)
                }
            }
        }
        
        // 将屏幕坐标投影到3D平面
        func unproject(point: CGPoint, onPlaneAt planePosition: SCNVector3, camera: SCNNode, view: SCNView) -> SCNVector3? {
            // 获取相机的前向向量（法线）
            let cameraTransform = camera.transform
            let cameraForward = SCNVector3(-cameraTransform.m31, -cameraTransform.m32, -cameraTransform.m33)
            
            // 将屏幕坐标转换为3D射线
            let nearPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let farPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            
            // 射线方向
            let rayDirection = SCNVector3(
                farPoint.x - nearPoint.x,
                farPoint.y - nearPoint.y,
                farPoint.z - nearPoint.z
            )
            
            // 计算射线与平面的交点（平面过planePosition，法线为cameraForward）
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
        
        // 自动吸附到附近的原子以形成合理的键
        func snapToNearbyAtoms(node: SCNNode, in scene: SCNScene) {
            let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere }
            guard let movingIndex = atomNodes.firstIndex(of: node) else { return }
            var bestSnapTarget: (node: SCNNode, position: SCNVector3, distanceScore: Float)?
            let library = ElementLibrary.shared
            let bondCounts = computeExistingBondCounts(for: atomNodes, in: scene)
            let movingSymbol = elementSymbol(for: node)
            
            for (index, otherNode) in atomNodes.enumerated() where otherNode != node {
                let currentDistance = distance(node.position, otherNode.position)
                let otherSymbol = elementSymbol(for: otherNode)
                let canForm = library.canFormBond(
                    between: movingSymbol,
                    and: otherSymbol,
                    currentBonds1: bondCounts[movingIndex],
                    currentBonds2: bondCounts[index]
                )
                guard canForm else { continue }
                
                let idealBondLength = library.getIdealBondLength(between: movingSymbol, and: otherSymbol)
                guard library.isValidBondDistance(currentDistance, between: movingSymbol, and: otherSymbol) else { continue }
                
                let distanceScore = abs(currentDistance - idealBondLength)
                if distanceScore < 0.4 {
                    let direction = normalize(SCNVector3(
                        node.position.x - otherNode.position.x,
                        node.position.y - otherNode.position.y,
                        node.position.z - otherNode.position.z
                    ))
                    let snapPosition = SCNVector3(
                        otherNode.position.x + direction.x * idealBondLength,
                        otherNode.position.y + direction.y * idealBondLength,
                        otherNode.position.z + direction.z * idealBondLength
                    )
                    if bestSnapTarget == nil || distanceScore < (bestSnapTarget?.distanceScore ?? .greatestFiniteMagnitude) {
                        bestSnapTarget = (otherNode, snapPosition, distanceScore)
                    }
                }
            }
            
            if let snapTarget = bestSnapTarget {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                node.position = snapTarget.position
                SCNTransaction.completionBlock = { [weak self, weak scene] in
                    guard let self = self, let scene = scene else { return }
                    if !self.smoothAlignToTemplateIfNeeded(node: node, in: scene) {
                        self.updateBonds(for: node, in: scene, temporary: false)
                    }
                }
                SCNTransaction.commit()
                return
            }
            
            if !smoothAlignToTemplateIfNeeded(node: node, in: scene) {
                updateBonds(for: node, in: scene, temporary: false)
            }
        }
        
        func dotProduct(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            return a.x * b.x + a.y * b.y + a.z * b.z
        }
        
        func normalize(_ v: SCNVector3) -> SCNVector3 {
            let len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
            guard len > 0 else { return SCNVector3(0, 0, 0) }
            return SCNVector3(v.x/len, v.y/len, v.z/len)
        }
        
        func updateBonds(for _: SCNNode, in scene: SCNScene, temporary: Bool) {
            scene.rootNode.childNodes.filter { $0.geometry is SCNCylinder }.forEach { $0.removeFromParentNode() }
            let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere }
            let library = ElementLibrary.shared
            var bondCounts = Array(repeating: 0, count: atomNodes.count)
            
            for i in 0..<atomNodes.count {
                for j in (i+1)..<atomNodes.count {
                    let nodeA = atomNodes[i]
                    let nodeB = atomNodes[j]
                    let distanceValue = distance(nodeA.position, nodeB.position)
                    let elementA = elementSymbol(for: nodeA)
                    let elementB = elementSymbol(for: nodeB)
                    
                    guard library.canFormBond(
                        between: elementA,
                        and: elementB,
                        currentBonds1: bondCounts[i],
                        currentBonds2: bondCounts[j]
                    ) else { continue }
                    
                    guard library.isValidBondDistance(distanceValue, between: elementA, and: elementB) else { continue }
                    
                    var bondColor: NSColor = .lightGray
                    if temporary && isDragging {
                        let idealLength = library.getIdealBondLength(between: elementA, and: elementB)
                        if abs(distanceValue - idealLength) < idealLength * 0.15 {
                            bondColor = NSColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 0.8)
                        }
                    }
                    
                    let cylinder = MoleculeScene.cylinderBetweenPoints(
                        pointA: nodeA.position,
                        pointB: nodeB.position,
                        radius: 0.08,
                        color: bondColor
                    )
                    cylinder.name = "bond:\(i)-\(j)"
                    scene.rootNode.addChildNode(cylinder)
                    bondCounts[i] += 1
                    bondCounts[j] += 1
                }
            }
        }
        
        func elementSymbol(for node: SCNNode) -> String {
            if let metadata = node.templateMetadata {
                return metadata.element
            }
            if let name = node.name, let symbol = name.split(separator: "#").first {
                return String(symbol)
            }
            return "C"
        }
        
        func targetPosition(for node: SCNNode) -> SCNVector3? {
            return node.templateMetadata?.targetPosition
        }
        
        func computeExistingBondCounts(for atomNodes: [SCNNode], in scene: SCNScene) -> [Int] {
            var counts = Array(repeating: 0, count: atomNodes.count)
            let bondNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNCylinder }
            for bond in bondNodes {
                guard let name = bond.name, name.hasPrefix("bond:") else { continue }
                let indexes = name.dropFirst(5).split(separator: "-")
                if indexes.count == 2,
                   let first = Int(indexes[0]),
                   let second = Int(indexes[1]),
                   first < counts.count, second < counts.count {
                    counts[first] += 1
                    counts[second] += 1
                }
            }
            return counts
        }

        @discardableResult
        func smoothAlignToTemplateIfNeeded(node: SCNNode, in scene: SCNScene) -> Bool {
            guard let target = targetPosition(for: node) else { return false }
            let displacement = distance(node.position, target)
            guard displacement > 0.01, displacement < 0.6 else { return false }
            let duration = Double(min(max(displacement * 1.1, 0.45), 1.6))
            let start = node.position
            let alignAction = SCNAction.customAction(duration: CGFloat(duration)) { [weak self, weak scene] _, elapsed in
                guard let self = self, let scene = scene else { return }
                let progress = Float(elapsed) / Float(duration)
                let eased = self.easeOutCubic(min(max(progress, 0), 1))
                let slowed = self.applyEndSlowdown(eased)
                node.position = self.interpolate(from: start, to: target, t: slowed)
                self.updateBonds(for: node, in: scene, temporary: true)
            }
            let finalize = SCNAction.run { [weak self, weak scene] _ in
                guard let self = self, let scene = scene else { return }
                node.position = target
                self.updateBonds(for: node, in: scene, temporary: false)
            }
            node.removeAction(forKey: "template-align")
            node.runAction(SCNAction.sequence([alignAction, finalize]), forKey: "template-align")
            return true
        }
        
        func easeOutCubic(_ t: Float) -> Float {
            let clamped = min(max(t, 0), 1)
            return 1 - pow(1 - clamped, 3)
        }

        func applyEndSlowdown(_ t: Float) -> Float {
            let clamped = min(max(t, 0), 1)
            let tailStart: Float = 0.65
            guard clamped > tailStart else { return clamped }
            let tailProgress = (clamped - tailStart) / (1 - tailStart)
            let slowedTail = pow(tailProgress, 1.85)
            return tailStart + slowedTail * (1 - tailStart)
        }
        
        func interpolate(from start: SCNVector3, to end: SCNVector3, t: Float) -> SCNVector3 {
            SCNVector3(
                start.x + (end.x - start.x) * t,
                start.y + (end.y - start.y) * t,
                start.z + (end.z - start.z) * t
            )
        }

        func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            let dx = a.x - b.x
            let dy = a.y - b.y
            let dz = a.z - b.z
            return sqrt(dx*dx + dy*dy + dz*dz)
        }
    }
}
#else
struct SceneKitView: UIViewRepresentable {
    var atoms: [Atom]
    var manualBonds: [ManualBond]
    var selectedHole: (atomIndex: Int, holeIndex: Int)?
    var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
    var onHoleTap: ((Int, Int) -> Void)?  // atomIndex, holeIndex

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = MoleculeScene.makeScene(atoms: atoms, manualBonds: manualBonds)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .black
        
        // 添加点击手势（用于点击孔）
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        view.addGestureRecognizer(tapGesture)
        
        // 添加拖拽手势，设置为不阻止其他手势
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        
        // 添加长按手势
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = context.coordinator
        view.addGestureRecognizer(longPressGesture)
        
        context.coordinator.sceneView = view
        context.coordinator.onAtomLongPress = onAtomLongPress
        context.coordinator.onHoleTap = onHoleTap
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // 在 atoms 数组或 manualBonds 变化时重建场景
        let atomsChanged = !atomsAreEqual(context.coordinator.lastAtoms, atoms)
        let bondsChanged = context.coordinator.lastManualBonds != manualBonds
        
        if atomsChanged || bondsChanged {
            // 保存相机的位置和旋转
            var savedCameraPosition: SCNVector3?
            var savedCameraEulerAngles: SCNVector3?
            if let oldCamera = uiView.pointOfView {
                savedCameraPosition = oldCamera.position
                savedCameraEulerAngles = oldCamera.eulerAngles
            }
            
            // 保留用户拖动后的原子位置
            var updatedAtoms = atoms
            if let scene = uiView.scene {
                // 提取旧场景中每个原子的当前位置
                for (index, atom) in updatedAtoms.enumerated() {
                    if let oldNode = scene.rootNode.childNode(withName: "\(atom.element)#\(index)", recursively: false) {
                        // 保留原子 id，防止标记丢失
                        updatedAtoms[index] = Atom(
                            id: atom.id,
                            element: atom.element,
                            position: oldNode.position,
                            radius: atom.radius
                        )
                    }
                }
            }
            
            uiView.scene = MoleculeScene.makeScene(atoms: updatedAtoms, manualBonds: manualBonds)
            
            // 恢复相机的位置和旋转
            if let newCamera = uiView.pointOfView,
               let position = savedCameraPosition,
               let eulerAngles = savedCameraEulerAngles {
                newCamera.position = position
                newCamera.eulerAngles = eulerAngles
            }
            
            context.coordinator.lastAtoms = atoms
            context.coordinator.lastManualBonds = manualBonds
        }
        context.coordinator.sceneView = uiView
        context.coordinator.onAtomLongPress = onAtomLongPress
        context.coordinator.onHoleTap = onHoleTap
    }
    
    private func atomsAreEqual(_ lhs: [Atom], _ rhs: [Atom]) -> Bool {
        // 首先检查数量是否相同
        guard lhs.count == rhs.count else { return false }
        
        // 如果数量相同，逐个比较元素类型和半径
        // 注意：我们不比较position，因为用户可以拖动原子改变位置
        for (index, atom) in lhs.enumerated() {
            let other = rhs[index]
            if atom.element != other.element || 
               abs(atom.radius - other.radius) > 0.001 {
                return false
            }
        }
        return true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var sceneView: SCNView?
        var selectedNode: SCNNode?
        var isDragging = false
        var dragPlanePosition: SCNVector3?
        var onAtomLongPress: ((Int, CGPoint, SCNVector3) -> Void)?
        var onHoleTap: ((Int, Int) -> Void)?
        var lastAtoms: [Atom] = []
        var lastManualBonds: [ManualBond] = []
        
        // 手势识别器代理方法：只有在点击到原子时才开始识别拖拽
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // 点击手势始终允许
            if gestureRecognizer is UITapGestureRecognizer {
                return true
            }
            
            guard let view = gestureRecognizer.view as? SCNView else { return false }
            let location = gestureRecognizer.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            // 只有点击到球体（原子）时才允许拖拽手势开始
            return hitResults.contains(where: { $0.node.geometry is SCNSphere && $0.node.name?.starts(with: "hole_") != true })
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let location = gesture.location(in: view)
            let hitResults = view.hitTest(location, options: [:])
            
            // 检查是否点击了孔
            for hit in hitResults {
                if let nodeName = hit.node.name, nodeName.starts(with: "hole_") {
                    // 找到孔的索引
                    let holeIndexStr = nodeName.replacingOccurrences(of: "hole_", with: "")
                    if let holeIndex = Int(holeIndexStr) {
                        // 找到原子索引（孔的父节点是原子）
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
            // 从 "Element#Index" 格式提取索引
            let parts = nodeName.split(separator: "#")
            guard parts.count == 2 else { return nil }
            return Int(parts[1])
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let location = gesture.location(in: view)
            
            switch gesture.state {
            case .began:
                // 检测点击的节点
                let hitResults = view.hitTest(location, options: [:])
                if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere }) {
                    selectedNode = hit.node
                    isDragging = true
                    dragPlanePosition = hit.node.position
                    // 暂时禁用相机控制
                    view.allowsCameraControl = false
                }
                
            case .changed:
                guard isDragging, let node = selectedNode, let camera = view.pointOfView else { return }
                
                // 将屏幕坐标转换为3D空间坐标
                if let newPosition = unproject(point: location, onPlaneAt: dragPlanePosition ?? node.position, camera: camera, view: view) {
                    node.position = newPosition
                }
                
                // 实时更新与该原子相连的键
                updateBonds(for: node, in: view.scene!, temporary: true)
                
            case .ended, .cancelled:
                if let node = selectedNode, let scene = view.scene {
                    // 松开后尝试自动吸附成键
                    snapToNearbyAtoms(node: node, in: scene)
                }
                
                isDragging = false
                selectedNode = nil
                dragPlanePosition = nil
                // 重新启用相机控制
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
            
            if let hit = hitResults.first(where: { $0.node.geometry is SCNSphere }),
               let scene = view.scene {
                let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere }
                if let index = atomNodes.firstIndex(of: hit.node) {
                    let atomPosition = hit.node.position
                    onAtomLongPress?(index, location, atomPosition)
                }
            }
        }
        
        // 将屏幕坐标投影到3D平面
        func unproject(point: CGPoint, onPlaneAt planePosition: SCNVector3, camera: SCNNode, view: SCNView) -> SCNVector3? {
            // 获取相机的前向向量（法线）
            let cameraTransform = camera.transform
            let cameraForward = SCNVector3(-cameraTransform.m31, -cameraTransform.m32, -cameraTransform.m33)
            
            // 将屏幕坐标转换为3D射线
            let nearPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let farPoint = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            
            // 射线方向
            let rayDirection = SCNVector3(
                farPoint.x - nearPoint.x,
                farPoint.y - nearPoint.y,
                farPoint.z - nearPoint.z
            )
            
            // 计算射线与平面的交点（平面过planePosition，法线为cameraForward）
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
        
        // 自动吸附到附近的原子以形成合理的键
        func snapToNearbyAtoms(node: SCNNode, in scene: SCNScene) {
            let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere }
            guard let movingIndex = atomNodes.firstIndex(of: node) else { return }
            let library = ElementLibrary.shared
            let bondCounts = computeExistingBondCounts(for: atomNodes, in: scene)
            let movingSymbol = elementSymbol(for: node)
            var bestSnapTarget: (node: SCNNode, position: SCNVector3, distanceScore: Float)?
            
            for (index, otherNode) in atomNodes.enumerated() where otherNode != node {
                let otherSymbol = elementSymbol(for: otherNode)
                let canForm = library.canFormBond(
                    between: movingSymbol,
                    and: otherSymbol,
                    currentBonds1: bondCounts[movingIndex],
                    currentBonds2: bondCounts[index]
                )
                guard canForm else { continue }
                
                let currentDistance = distance(node.position, otherNode.position)
                guard library.isValidBondDistance(currentDistance, between: movingSymbol, and: otherSymbol) else { continue }
                let idealBondLength = library.getIdealBondLength(between: movingSymbol, and: otherSymbol)
                let distanceScore = abs(currentDistance - idealBondLength)
                if distanceScore < 0.4 {
                    let direction = normalize(SCNVector3(
                        node.position.x - otherNode.position.x,
                        node.position.y - otherNode.position.y,
                        node.position.z - otherNode.position.z
                    ))
                    let snapPosition = SCNVector3(
                        otherNode.position.x + direction.x * idealBondLength,
                        otherNode.position.y + direction.y * idealBondLength,
                        otherNode.position.z + direction.z * idealBondLength
                    )
                    if bestSnapTarget == nil || distanceScore < (bestSnapTarget?.distanceScore ?? .greatestFiniteMagnitude) {
                        bestSnapTarget = (otherNode, snapPosition, distanceScore)
                    }
                }
            }
            
            if let snapTarget = bestSnapTarget {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                node.position = snapTarget.position
                SCNTransaction.completionBlock = { [weak self, weak scene] in
                    guard let self = self, let scene = scene else { return }
                    if !self.smoothAlignToTemplateIfNeeded(node: node, in: scene) {
                        self.updateBonds(for: node, in: scene, temporary: false)
                    }
                }
                SCNTransaction.commit()
                return
            }
            
            if !smoothAlignToTemplateIfNeeded(node: node, in: scene) {
                updateBonds(for: node, in: scene, temporary: false)
            }
        }
        
        func dotProduct(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            return a.x * b.x + a.y * b.y + a.z * b.z
        }
        
        func normalize(_ v: SCNVector3) -> SCNVector3 {
            let len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
            guard len > 0 else { return SCNVector3(0, 0, 0) }
            return SCNVector3(v.x/len, v.y/len, v.z/len)
        }
        
        func updateBonds(for _: SCNNode, in scene: SCNScene, temporary: Bool) {
            scene.rootNode.childNodes.filter { $0.geometry is SCNCylinder }.forEach { $0.removeFromParentNode() }
            let atomNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNSphere }
            let library = ElementLibrary.shared
            var bondCounts = Array(repeating: 0, count: atomNodes.count)
            
            for i in 0..<atomNodes.count {
                for j in (i+1)..<atomNodes.count {
                    let nodeA = atomNodes[i]
                    let nodeB = atomNodes[j]
                    let distanceValue = distance(nodeA.position, nodeB.position)
                    let elementA = elementSymbol(for: nodeA)
                    let elementB = elementSymbol(for: nodeB)
                    
                    guard library.canFormBond(
                        between: elementA,
                        and: elementB,
                        currentBonds1: bondCounts[i],
                        currentBonds2: bondCounts[j]
                    ) else { continue }
                    
                    guard library.isValidBondDistance(distanceValue, between: elementA, and: elementB) else { continue }
                    
                    var bondColor: UIColor = .lightGray
                    if temporary && isDragging {
                        let idealLength = library.getIdealBondLength(between: elementA, and: elementB)
                        if abs(distanceValue - idealLength) < idealLength * 0.15 {
                            bondColor = UIColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 0.8)
                        }
                    }
                    
                    let cylinder = MoleculeScene.cylinderBetweenPoints(
                        pointA: nodeA.position,
                        pointB: nodeB.position,
                        radius: 0.08,
                        color: bondColor
                    )
                    cylinder.name = "bond:\(i)-\(j)"
                    scene.rootNode.addChildNode(cylinder)
                    bondCounts[i] += 1
                    bondCounts[j] += 1
                }
            }
        }
        
        func elementSymbol(for node: SCNNode) -> String {
            if let metadata = node.templateMetadata {
                return metadata.element
            }
            if let name = node.name, let symbol = name.split(separator: "#").first {
                return String(symbol)
            }
            return "C"
        }
        
        func targetPosition(for node: SCNNode) -> SCNVector3? {
            return node.templateMetadata?.targetPosition
        }
        
        func computeExistingBondCounts(for atomNodes: [SCNNode], in scene: SCNScene) -> [Int] {
            var counts = Array(repeating: 0, count: atomNodes.count)
            let bondNodes = scene.rootNode.childNodes.filter { $0.geometry is SCNCylinder }
            for bond in bondNodes {
                guard let name = bond.name, name.hasPrefix("bond:") else { continue }
                let indexes = name.dropFirst(5).split(separator: "-")
                if indexes.count == 2,
                   let first = Int(indexes[0]),
                   let second = Int(indexes[1]),
                   first < counts.count, second < counts.count {
                    counts[first] += 1
                    counts[second] += 1
                }
            }
            return counts
        }

        @discardableResult
        func smoothAlignToTemplateIfNeeded(node: SCNNode, in scene: SCNScene) -> Bool {
            guard let target = targetPosition(for: node) else { return false }
            let displacement = distance(node.position, target)
            guard displacement > 0.01, displacement < 0.6 else { return false }
            let duration = Double(min(max(displacement * 1.1, 0.45), 1.6))
            let start = node.position
            let alignAction = SCNAction.customAction(duration: CGFloat(duration)) { [weak self, weak scene] _, elapsed in
                guard let self = self, let scene = scene else { return }
                let progress = Float(elapsed) / Float(duration)
                let eased = self.easeOutCubic(min(max(progress, 0), 1))
                let slowed = self.applyEndSlowdown(eased)
                node.position = self.interpolate(from: start, to: target, t: slowed)
                self.updateBonds(for: node, in: scene, temporary: true)
            }
            let finalize = SCNAction.run { [weak self, weak scene] _ in
                guard let self = self, let scene = scene else { return }
                node.position = target
                self.updateBonds(for: node, in: scene, temporary: false)
            }
            node.removeAction(forKey: "template-align")
            node.runAction(SCNAction.sequence([alignAction, finalize]), forKey: "template-align")
            return true
        }
        
        func easeOutCubic(_ t: Float) -> Float {
            let clamped = min(max(t, 0), 1)
            return 1 - pow(1 - clamped, 3)
        }

        func applyEndSlowdown(_ t: Float) -> Float {
            let clamped = min(max(t, 0), 1)
            let tailStart: Float = 0.65
            guard clamped > tailStart else { return clamped }
            let tailProgress = (clamped - tailStart) / (1 - tailStart)
            let slowedTail = pow(tailProgress, 1.85)
            return tailStart + slowedTail * (1 - tailStart)
        }
        
        func interpolate(from start: SCNVector3, to end: SCNVector3, t: Float) -> SCNVector3 {
            SCNVector3(
                start.x + (end.x - start.x) * t,
                start.y + (end.y - start.y) * t,
                start.z + (end.z - start.z) * t
            )
        }

        func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            let dx = a.x - b.x
            let dy = a.y - b.y
            let dz = a.z - b.z
            return sqrt(dx*dx + dy*dy + dz*dz)
        }
    }
}
#endif
