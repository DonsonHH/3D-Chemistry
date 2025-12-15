//
//  MoleculeScene.swift
//  3D-Chemistry
//
//  Created by ypx on 2025/11/12.
//

import SceneKit
import Foundation
import ObjectiveC.runtime
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd
import CoreGraphics

// 手动键信息
struct ManualBond: Equatable {
    let atomIndex1: Int  // 第一个原子的索引
    let atomIndex2: Int  // 第二个原子的索引
    let holeIndex1: Int  // 第一个原子的孔索引
    let holeIndex2: Int  // 第二个原子的孔索引
}

struct Atom {
    let id: UUID  // 唯一标识
    let element: String
    let position: SCNVector3
    let radius: CGFloat
    
    init(id: UUID = UUID(), element: String, position: SCNVector3, radius: CGFloat) {
        self.id = id
        self.element = element
        self.position = position
        self.radius = radius
    }
}

class MoleculeScene {
    
    // 使用元素库
    #if os(macOS)
    static func color(for element: String) -> NSColor {
        ElementLibrary.shared.getColor(for: element)
    }
    #else
    static func color(for element: String) -> UIColor {
        ElementLibrary.shared.getColor(for: element)
    }
    #endif

    static func defaultRadius(for element: String) -> CGFloat {
        ElementLibrary.shared.getVisualRadius(for: element)
    }

    static func makeScene(atoms: [Atom], manualBonds: [ManualBond] = [], selectedHole: (atomIndex: Int, holeIndex: Int)? = nil) -> SCNScene {
        let scene = SCNScene()
        let elementLib = ElementLibrary.shared
        
        guard !atoms.isEmpty else {
            // 空场景也添加相机
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 0, 6)
            scene.rootNode.addChildNode(cameraNode)
            return scene
        }
        
        // 添加原子（球体）并记录节点
        var atomNodes: [SCNNode] = []
        for (index, atom) in atoms.enumerated() {
            let sphere = SCNSphere(radius: atom.radius)
            sphere.firstMaterial?.diffuse.contents = color(for: atom.element)
#if os(macOS)
            sphere.firstMaterial?.specular.contents = NSColor(white: 0.9, alpha: 1)
#else
            sphere.firstMaterial?.specular.contents = UIColor(white: 0.9, alpha: 1)
#endif
            let node = SCNNode(geometry: sphere)
            node.position = atom.position
            node.name = "\(atom.element)#\(index)"
            node.templateMetadata = AtomTemplateMetadata(
                element: atom.element,
                index: index,
                targetPosition: atom.position
            )
            
            // 添加成键孔
            let maxBonds = elementLib.getMaxBonds(for: atom.element)
            let isSelectedAtom = selectedHole?.atomIndex == index
            let selectedHoleIndex = isSelectedAtom ? selectedHole?.holeIndex : nil
            addBondingHoles(to: node, atomIndex: index, maxBonds: maxBonds, atomRadius: atom.radius, selectedHoleIndex: selectedHoleIndex)
            
            atomNodes.append(node)
            scene.rootNode.addChildNode(node)
        }

        // 初始化成键计数
        var bondCounts = Array(repeating: 0, count: atoms.count)
        
        // 首先创建手动键（优先级最高）
        var manualBondedPairs = Set<String>()
        for manualBond in manualBonds {
            let i = manualBond.atomIndex1
            let j = manualBond.atomIndex2
            
            guard i < atoms.count && j < atoms.count else { continue }
            
            let a = atoms[i], b = atoms[j]
            
#if os(macOS)
            let bondColor: NSColor = .cyan  // 手动键用青色区分
#else
            let bondColor: UIColor = .cyan
#endif
            let cylinder = cylinderBetweenPoints(
                pointA: a.position,
                pointB: b.position,
                radius: 0.10,  // 稍粗一点
                color: bondColor
            )
            cylinder.name = "manual-bond:\(i)-\(j)"
            scene.rootNode.addChildNode(cylinder)
            
            bondCounts[i] += 1
            bondCounts[j] += 1
            
            // 记录已成键的原子对
            let key = i < j ? "\(i)-\(j)" : "\(j)-\(i)"
            manualBondedPairs.insert(key)
            
            // 隐藏已使用的孔
            if i < atomNodes.count, let holeNode = atomNodes[i].childNode(withName: "hole_\(manualBond.holeIndex1)", recursively: false) {
                holeNode.isHidden = true
            }
            if j < atomNodes.count, let holeNode = atomNodes[j].childNode(withName: "hole_\(manualBond.holeIndex2)", recursively: false) {
                holeNode.isHidden = true
            }
        }
        
        // 自动判断键：基于共价半径与最大成键数（排除已手动成键的）
        for i in 0..<atoms.count {
            for j in (i+1)..<atoms.count {
                // 跳过已手动成键的原子对
                let key = "\(i)-\(j)"
                if manualBondedPairs.contains(key) {
                    continue
                }
                
                let a = atoms[i], b = atoms[j]
                let dx = a.position.x - b.position.x
                let dy = a.position.y - b.position.y
                let dz = a.position.z - b.position.z
                let dist = sqrt(dx*dx + dy*dy + dz*dz)
                let distance = Float(dist)
                let elementA = a.element
                let elementB = b.element

                let canForm = elementLib.canFormBond(
                    between: elementA,
                    and: elementB,
                    currentBonds1: bondCounts[i],
                    currentBonds2: bondCounts[j]
                )
                guard canForm else { continue }

                guard elementLib.isValidBondDistance(distance, between: elementA, and: elementB) else { continue }

#if os(macOS)
                let bondColor: NSColor = .lightGray
#else
                let bondColor: UIColor = .lightGray
#endif
                let cylinder = cylinderBetweenPoints(
                    pointA: a.position,
                    pointB: b.position,
                    radius: 0.08,
                    color: bondColor
                )
                cylinder.name = "bond:\(i)-\(j)"
                scene.rootNode.addChildNode(cylinder)
                bondCounts[i] += 1
                bondCounts[j] += 1
            }
        }

        // 相机
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    #if os(macOS)
    typealias SceneColor = NSColor
    #else
    typealias SceneColor = UIColor
    #endif

    static func cylinderBetweenPoints(pointA: SCNVector3, pointB: SCNVector3, radius: CGFloat, color: SceneColor) -> SCNNode {
        let vector = SCNVector3(pointB.x - pointA.x, pointB.y - pointA.y, pointB.z - pointA.z)
        let distance = sqrt(vector.x*vector.x + vector.y*vector.y + vector.z*vector.z)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: cylinder)

        // position: midpoint
        node.position = SCNVector3((pointA.x + pointB.x)/2, (pointA.y + pointB.y)/2, (pointA.z + pointB.z)/2)

        // orientation: 旋转 cylinder 的 y 轴与向量对齐
        let from = SCNVector3(0, 1, 0)
        let to = normalize(vector)
        let axis = cross(from, to)
        let dotv = dot(from, to)
        let angle = acos(max(min(dotv, 1), -1))
        if sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z) < 1e-6 {
            // 平行或反向
            if dotv < 0 {
                node.rotation = SCNVector4(1, 0, 0, Float.pi)
            }
        } else {
            let axisN = normalize(axis)
            node.rotation = SCNVector4(axisN.x, axisN.y, axisN.z, angle)
        }
        return node
    }

    // 向量工具
    static func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float { a.x*b.x + a.y*b.y + a.z*b.z }
    static func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
    }
    static func normalize(_ v: SCNVector3) -> SCNVector3 {
        let len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
        guard len > 0 else { return SCNVector3(0,0,0) }
        return SCNVector3(v.x/len, v.y/len, v.z/len)
    }

    // MARK: - 法线贴图生成器（用于凹槽细节）
    static func generateConcaveNormalMap(size: Int = 64, strength: Float = 0.6) -> CGImage? {
        let width = size
        let height = size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // 填充像素：以圆形凹陷为基础，计算法线向量
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        let cx = Float(width) / 2.0
        let cy = Float(height) / 2.0
        let radius = min(cx, cy) * 0.95

        for y in 0..<height {
            for x in 0..<width {
                let fx = Float(x)
                let fy = Float(y)
                let dx = (fx - cx) / radius
                let dy = (fy - cy) / radius
                let dist2 = dx*dx + dy*dy

                var nx: Float = 0.0
                var ny: Float = 0.0
                var nz: Float = 1.0

                if dist2 <= 1.0 {
                    // 凹槽曲率：z = sqrt(1 - (dx^2+dy^2) * k)
                    let k = max(0.0, min(1.0, strength))
                    let dz = sqrt(max(0.0, 1.0 - dist2 * k))
                    // 原法线为 (dx, dy, dz) 然后归一化
                    var vx = dx * k
                    var vy = dy * k
                    var vz = dz
                    let len = sqrt(vx*vx + vy*vy + vz*vz)
                    if len > 0 {
                        vx /= len
                        vy /= len
                        vz /= len
                    }
                    nx = vx
                    ny = vy
                    nz = vz
                } else {
                    // 平坦区域，z向上
                    nx = 0.0
                    ny = 0.0
                    nz = 1.0
                }

                // 法线转换到 [0,255]
                let r = UInt8(max(0, min(255, Int((nx * 0.5 + 0.5) * 255.0))))
                let g = UInt8(max(0, min(255, Int((ny * 0.5 + 0.5) * 255.0))))
                let b = UInt8(max(0, min(255, Int((nz * 0.5 + 0.5) * 255.0))))
                let a: UInt8 = 255

                let offset = (y * width + x) * bytesPerPixel
                ptr[offset + 0] = r
                ptr[offset + 1] = g
                ptr[offset + 2] = b
                ptr[offset + 3] = a
            }
        }

        return ctx.makeImage()
    }

    static func loadHoleNormalMap() -> CGImage? {
#if os(macOS)
        if let ns = NSImage(named: "HoleNormal"), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
#else
        if let ui = UIImage(named: "HoleNormal"), let cg = ui.cgImage {
            return cg
        }
#endif
        return generateConcaveNormalMap(size: 128, strength: 0.6)
    }
    
    // MARK: - 成键孔
    
    /// 在原子表面添加成键孔（小球体标记）
    static func addBondingHoles(to atomNode: SCNNode, atomIndex: Int, maxBonds: Int, atomRadius: CGFloat, selectedHoleIndex: Int? = nil) {
        guard maxBonds > 0 else { return }
        
        // 根据最大成键数计算孔的位置（使用正四面体、正八面体等几何分布）
        let holePositions = calculateHolePositions(maxBonds: maxBonds)
        
        for (index, direction) in holePositions.enumerated() {
            // 孔的半径相对较小
            let holeRadius: CGFloat = atomRadius * 0.15

            // 使用短圆柱（扁平）放在球体内侧，视觉上表现为凹槽
            let holeDepth: Float = Float(holeRadius) * 0.9 // 凹进深度
            let cylinder = SCNCylinder(radius: holeRadius, height: CGFloat(holeDepth))

            // 高亮选中的孔
            let isSelected = selectedHoleIndex == index
#if os(macOS)
            cylinder.firstMaterial?.diffuse.contents = isSelected ? NSColor.systemRed.withAlphaComponent(0.9) : NSColor(white: 0.12, alpha: 1.0)
            cylinder.firstMaterial?.specular.contents = NSColor.black
            cylinder.firstMaterial?.emission.contents = isSelected ? NSColor.systemRed.withAlphaComponent(0.35) : NSColor.black.withAlphaComponent(0.05)
#else
            cylinder.firstMaterial?.diffuse.contents = isSelected ? UIColor.systemRed.withAlphaComponent(0.9) : UIColor(white: 0.12, alpha: 1.0)
            cylinder.firstMaterial?.specular.contents = UIColor.black
            cylinder.firstMaterial?.emission.contents = isSelected ? UIColor.systemRed.withAlphaComponent(0.35) : UIColor.black.withAlphaComponent(0.05)
#endif
            // 载入或生成法线贴图，增强凹陷视觉
            if let normalCG = loadHoleNormalMap() {
                cylinder.firstMaterial?.normal.contents = normalCG
            }

            let holeNode = SCNNode(geometry: cylinder)

            // 将短圆柱沿 direction 方向放置在原子表面之内一点，形成凹陷效果
            let posDistance = Float(atomRadius) - (holeDepth / 2.0) - Float(holeRadius) * 0.05
            holeNode.position = SCNVector3(
                direction.x * posDistance,
                direction.y * posDistance,
                direction.z * posDistance
            )

            // 旋转短圆柱，使其轴线与 direction 对齐（默认圆柱沿 Y 轴）
            let from = SCNVector3(0, 1, 0)
            let to = normalize(direction)
            let axis = cross(from, to)
            let dotv = dot(from, to)
            let angle = acos(max(min(dotv, 1), -1))
            if sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z) < 1e-6 {
                if dotv < 0 {
                    holeNode.rotation = SCNVector4(1, 0, 0, Float.pi)
                }
            } else {
                let axisN = normalize(axis)
                holeNode.rotation = SCNVector4(axisN.x, axisN.y, axisN.z, angle)
            }

            holeNode.name = "hole_\(index)"
            holeNode.templateMetadata = AtomTemplateMetadata(
                element: "hole",
                index: index,
                targetPosition: holeNode.position
            )

            atomNode.addChildNode(holeNode)

            // 在孔外表面添加一个非常扁平的盖子，遮盖中间原子颜色泄露，使凹陷看起来更完整
            let coverRadius = holeRadius * 0.65
            let coverHeight: Float = max(0.005, holeDepth * 0.2)
            let coverCylinder = SCNCylinder(radius: coverRadius, height: CGFloat(coverHeight))
            // 使用物理光照模型并降低高光，使盖子更像遮罩而不是高亮表面
            coverCylinder.firstMaterial?.lightingModel = .physicallyBased
#if os(macOS)
            coverCylinder.firstMaterial?.diffuse.contents = isSelected ? NSColor.systemRed.withAlphaComponent(0.95) : NSColor.black
            coverCylinder.firstMaterial?.roughness.contents = NSNumber(value: 0.92)
            coverCylinder.firstMaterial?.metalness.contents = NSNumber(value: 0.0)
#else
            coverCylinder.firstMaterial?.diffuse.contents = isSelected ? UIColor.systemRed.withAlphaComponent(0.95) : UIColor.black
            coverCylinder.firstMaterial?.roughness.contents = NSNumber(value: 0.92)
            coverCylinder.firstMaterial?.metalness.contents = NSNumber(value: 0.0)
#endif
            if let normalCG = loadHoleNormalMap() {
                coverCylinder.firstMaterial?.normal.contents = normalCG
            }

            let coverNode = SCNNode(geometry: coverCylinder)
            // 放置在原子表面稍外侧，覆盖中心
            let coverDistance = Float(atomRadius) - Float(coverHeight) / 2.0 + 0.002
            coverNode.position = SCNVector3(
                direction.x * coverDistance,
                direction.y * coverDistance,
                direction.z * coverDistance
            )
            // 与孔对齐
            if sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z) < 1e-6 {
                if dotv < 0 {
                    coverNode.rotation = SCNVector4(1, 0, 0, Float.pi)
                }
            } else {
                let axisN = normalize(axis)
                coverNode.rotation = SCNVector4(axisN.x, axisN.y, axisN.z, angle)
            }
            coverNode.name = "hole_cover_\(index)"
            atomNode.addChildNode(coverNode)
        }
    }
    
    /// 计算成键孔的方向向量
    static func calculateHolePositions(maxBonds: Int) -> [SCNVector3] {
        switch maxBonds {
        case 1:
            // 单键：一个方向
            return [SCNVector3(1, 0, 0)]
            
        case 2:
            // 双键：线性，180度
            return [
                SCNVector3(1, 0, 0),
                SCNVector3(-1, 0, 0)
            ]
            
        case 3:
            // 三键：平面三角形，120度
            let angle = Float.pi * 2.0 / 3.0
            return [
                SCNVector3(1, 0, 0),
                SCNVector3(cos(angle), sin(angle), 0),
                SCNVector3(cos(2 * angle), sin(2 * angle), 0)
            ]
            
        case 4:
            // 四键：正四面体
            let a: Float = 1.0 / sqrt(3.0)
            return [
                SCNVector3(1, 1, 1).normalized(),
                SCNVector3(1, -1, -1).normalized(),
                SCNVector3(-1, 1, -1).normalized(),
                SCNVector3(-1, -1, 1).normalized()
            ]
            
        case 5:
            // 五键：三角双锥
            let angle = Float.pi * 2.0 / 3.0
            return [
                SCNVector3(0, 1, 0),  // 顶端
                SCNVector3(0, -1, 0), // 底端
                SCNVector3(1, 0, 0),
                SCNVector3(cos(angle), 0, sin(angle)),
                SCNVector3(cos(2 * angle), 0, sin(2 * angle))
            ]
            
        case 6:
            // 六键：正八面体
            return [
                SCNVector3(1, 0, 0),
                SCNVector3(-1, 0, 0),
                SCNVector3(0, 1, 0),
                SCNVector3(0, -1, 0),
                SCNVector3(0, 0, 1),
                SCNVector3(0, 0, -1)
            ]
            
        default:
            // 默认：随机分布在球面上
            var positions: [SCNVector3] = []
            for i in 0..<maxBonds {
                let theta = Float.pi * Float(i) / Float(maxBonds)
                let phi = Float.pi * 2.0 * Float(i) / Float(maxBonds)
                positions.append(SCNVector3(
                    sin(theta) * cos(phi),
                    sin(theta) * sin(phi),
                    cos(theta)
                ))
            }
            return positions
        }
    }
}

// MARK: - SCNVector3 扩展

extension SCNVector3 {
    func normalized() -> SCNVector3 {
        let len = sqrt(x*x + y*y + z*z)
        guard len > 0 else { return SCNVector3(0, 0, 0) }
        return SCNVector3(x/len, y/len, z/len)
    }
}

// MARK: - Atom Template Metadata

struct AtomTemplateMetadata {
    let element: String
    let index: Int
    let targetPosition: SCNVector3
}

private final class AtomTemplateMetadataBox: NSObject {
    let metadata: AtomTemplateMetadata
    init(metadata: AtomTemplateMetadata) {
        self.metadata = metadata
    }
}

private enum AtomTemplateAssociatedKeys {
    static var metadata = "scnnode.template.metadata.key"
}

extension SCNNode {
    var templateMetadata: AtomTemplateMetadata? {
        get {
            (objc_getAssociatedObject(self, &AtomTemplateAssociatedKeys.metadata) as? AtomTemplateMetadataBox)?.metadata
        }
        set {
            if let metadata = newValue {
                let box = AtomTemplateMetadataBox(metadata: metadata)
                objc_setAssociatedObject(self, &AtomTemplateAssociatedKeys.metadata, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else {
                objc_setAssociatedObject(self, &AtomTemplateAssociatedKeys.metadata, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
}
