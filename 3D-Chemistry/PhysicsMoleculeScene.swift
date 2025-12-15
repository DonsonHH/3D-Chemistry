//
//  PhysicsMoleculeScene.swift
//  3D-Chemistry
//
//  Created by ypx on 2025/11/26.
//

import SceneKit
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 原子物理模型 - 使用 SceneKit 物理引擎
class PhysicsMoleculeScene {
    
    // MARK: - 类型别名
    #if os(macOS)
    typealias SceneColor = NSColor
    #else
    typealias SceneColor = UIColor
    #endif
    
    // MARK: - 物理参数
    struct PhysicsConfig {
        static let atomMass: CGFloat = 1.0          // 原子质量
        static let bondStiffness: CGFloat = 100.0   // 化学键弹簧刚度（增强）
        static let bondDamping: CGFloat = 15.0      // 化学键阻尼（大幅增强）
        static let angleStiffness: Float = 40.0     // 键角弹簧刚度（增强）
        static let angleDamping: Float = 8.0        // 键角阻尼（大幅增强）
        static let attractionStrength: Float = 2.0  // 可成键原子间吸引力
        static let repulsionStrength: Float = 0.3   // 原子间排斥力强度（降低）
        static let gravity: SCNVector3 = SCNVector3(0, 0, 0)  // 无重力（分子漂浮）
        static let airFriction: CGFloat = 0.8       // 空气阻力（大幅增强）
        static let restitution: CGFloat = 0.1       // 弹性碰撞系数（降低）
        static let physicsUpdateInterval: Int = 2   // 每N帧更新一次物理
        static let bondCheckInterval: Int = 6       // 成键检测间隔
    }
    
    // MARK: - 化学键结构
    struct ChemicalBond: Equatable {
        let atomNode1: SCNNode
        let atomNode2: SCNNode
        let idealLength: Float
        let bondOrder: Int  // 键级：1=单键, 2=双键, 3=三键
        let cylinderNodes: [SCNNode]  // 多个圆柱体用于显示双键/三键
        
        static func == (lhs: ChemicalBond, rhs: ChemicalBond) -> Bool {
            return lhs.atomNode1 === rhs.atomNode1 && lhs.atomNode2 === rhs.atomNode2
        }
    }
    
    // 分子几何构型类型
    enum MolecularGeometry {
        case linear         // 线性 (180°, sp杂化)
        case trigonalPlanar // 平面三角形 (120°, sp²杂化)
        case tetrahedral    // 四面体 (109.5°, sp³杂化)
        case bentSp3        // 弯曲型 sp³ (如H₂O, ~104.5°)
        case pyramidal      // 三角锥形 (如NH₃, ~107°)
    }
    
    private var bonds: [ChemicalBond] = []
    private var atomNodes: [SCNNode] = []
    private var bondCounts: [Int] = []  // 每个原子当前的成键数（按电子对计算，双键计为2）
    private var frameCounter: Int = 0   // 帧计数器（用于优化）
    private var atomBondOrders: [[Int: Int]] = []  // 每个原子与其他原子之间的键级 [原子索引][邻居索引] = 键级
    weak var scene: SCNScene?
    
    // MARK: - 创建物理场景
    
    static func makeScene(atoms: [Atom], manualBonds: [ManualBond] = [], selectedHole: (atomIndex: Int, holeIndex: Int)? = nil) -> (SCNScene, PhysicsMoleculeScene) {
        let scene = SCNScene()
        let manager = PhysicsMoleculeScene()
        manager.scene = scene
        
        // 配置物理世界
        scene.physicsWorld.gravity = PhysicsConfig.gravity
        scene.physicsWorld.speed = 1.0
        
        guard !atoms.isEmpty else {
            // 空场景也添加相机
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 0, 6)
            scene.rootNode.addChildNode(cameraNode)
            return (scene, manager)
        }
        
        let elementLib = ElementLibrary.shared
        
        // 添加原子（带物理属性的球体）
        for (index, atom) in atoms.enumerated() {
            let atomNode = manager.createPhysicsAtom(atom: atom, index: index, elementLib: elementLib)
            manager.atomNodes.append(atomNode)
            scene.rootNode.addChildNode(atomNode)
            
            // 添加成键孔
            let maxBonds = elementLib.getMaxBonds(for: atom.element)
            let isSelectedAtom = selectedHole?.atomIndex == index
            let selectedHoleIndex = isSelectedAtom ? selectedHole?.holeIndex : nil
            MoleculeScene.addBondingHoles(to: atomNode, atomIndex: index, maxBonds: maxBonds, atomRadius: atom.radius, selectedHoleIndex: selectedHoleIndex)
        }
        
        // 初始化成键计数和键级记录
        manager.bondCounts = Array(repeating: 0, count: atoms.count)
        manager.atomBondOrders = Array(repeating: [:], count: atoms.count)
        
        // 创建手动键（使用物理约束）- 手动键默认为单键
        var manualBondedPairs = Set<String>()
        for manualBond in manualBonds {
            let i = manualBond.atomIndex1
            let j = manualBond.atomIndex2
            
            guard i < atoms.count && j < atoms.count else { continue }
            
            let nodeA = manager.atomNodes[i]
            let nodeB = manager.atomNodes[j]
            
            let idealLength = elementLib.getIdealBondLength(between: atoms[i].element, and: atoms[j].element, bondOrder: 1)
            
            // 创建化学键视觉效果和物理约束
            manager.createBondWithPhysics(
                nodeA: nodeA,
                nodeB: nodeB,
                idealLength: idealLength,
                bondOrder: 1,
                color: .cyan,
                scene: scene
            )
            
            manager.bondCounts[i] += 1
            manager.bondCounts[j] += 1
            manager.atomBondOrders[i][j] = 1
            manager.atomBondOrders[j][i] = 1
            
            let key = i < j ? "\(i)-\(j)" : "\(j)-\(i)"
            manualBondedPairs.insert(key)
            
            // 隐藏已使用的孔
            if let holeNode = nodeA.childNode(withName: "hole_\(manualBond.holeIndex1)", recursively: false) {
                holeNode.isHidden = true
            }
            if let holeNode = nodeB.childNode(withName: "hole_\(manualBond.holeIndex2)", recursively: false) {
                holeNode.isHidden = true
            }
        }
        
        // 自动判断键（支持多重键）
        for i in 0..<atoms.count {
            for j in (i+1)..<atoms.count {
                let key = "\(i)-\(j)"
                if manualBondedPairs.contains(key) {
                    continue
                }
                
                let a = atoms[i], b = atoms[j]
                let distance = manager.distance(a.position, b.position)
                let elementA = a.element
                let elementB = b.element
                
                // 计算剩余成键能力
                let maxBonds1 = elementLib.getMaxBonds(for: elementA)
                let maxBonds2 = elementLib.getMaxBonds(for: elementB)
                let remainingBonds1 = maxBonds1 - manager.bondCounts[i]
                let remainingBonds2 = maxBonds2 - manager.bondCounts[j]
                
                guard remainingBonds1 > 0 && remainingBonds2 > 0 else { continue }
                
                // 计算应该形成的键级
                let bondOrder = elementLib.calculateBondOrder(
                    element1: elementA,
                    element2: elementB,
                    remainingBonds1: remainingBonds1,
                    remainingBonds2: remainingBonds2
                )
                
                guard bondOrder > 0 else { continue }
                
                // 根据键级获取理想键长
                let idealLength = elementLib.getIdealBondLength(between: elementA, and: elementB, bondOrder: bondOrder)
                
                // 验证距离是否在合理范围（对于双键三键，允许更短的距离）
                let bondLengthTolerance: Float = bondOrder > 1 ? 1.5 : 1.3
                guard distance <= idealLength * bondLengthTolerance else { continue }
                
                // 创建化学键（带物理约束）
                manager.createBondWithPhysics(
                    nodeA: manager.atomNodes[i],
                    nodeB: manager.atomNodes[j],
                    idealLength: idealLength,
                    bondOrder: bondOrder,
                    color: .lightGray,
                    scene: scene
                )
                
                // 更新成键计数（双键计为2，三键计为3）
                manager.bondCounts[i] += bondOrder
                manager.bondCounts[j] += bondOrder
                manager.atomBondOrders[i][j] = bondOrder
                manager.atomBondOrders[j][i] = bondOrder
            }
        }
        
        // 相机
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        // 关闭 HDR 自动曝光，保持固定光照强度
        cameraNode.camera?.wantsHDR = false
        cameraNode.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(cameraNode)
        
        // 添加多层光照系统
        addLightingSystem(to: scene)
        
        // 添加空间参照系统
        addSpatialReference(to: scene)
        
        return (scene, manager)
    }
    
    // MARK: - 光照系统
    
    private static func addLightingSystem(to scene: SCNScene) {
        // 1. 柔和的环境光（整体提亮，但不太强）
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        #if os(macOS)
        ambientLight.light?.color = NSColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1.0)
        #else
        ambientLight.light?.color = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1.0)
        #endif
        ambientLight.light?.intensity = 200
        scene.rootNode.addChildNode(ambientLight)
        
        // 2. 主光源：从右上前方打来（模拟太阳/主光）
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        #if os(macOS)
        keyLight.light?.color = NSColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1.0)
        #else
        keyLight.light?.color = UIColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1.0)
        #endif
        keyLight.light?.intensity = 600
        keyLight.light?.castsShadow = true
        keyLight.light?.shadowMode = .deferred
        keyLight.light?.shadowColor = UIColor.black.withAlphaComponent(0.3)
        keyLight.light?.shadowRadius = 3
        keyLight.position = SCNVector3(5, 8, 10)
        keyLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(keyLight)
        
        // 3. 补光：从左下方，较冷的蓝色调
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        #if os(macOS)
        fillLight.light?.color = NSColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 1.0)
        #else
        fillLight.light?.color = UIColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 1.0)
        #endif
        fillLight.light?.intensity = 250
        fillLight.position = SCNVector3(-8, -3, 5)
        fillLight.eulerAngles = SCNVector3(Float.pi / 6, -Float.pi / 4, 0)
        scene.rootNode.addChildNode(fillLight)
        
        // 4. 背光/轮廓光：从后方，帮助区分前后
        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        #if os(macOS)
        rimLight.light?.color = NSColor(red: 0.4, green: 0.5, blue: 0.8, alpha: 1.0)
        #else
        rimLight.light?.color = UIColor(red: 0.4, green: 0.5, blue: 0.8, alpha: 1.0)
        #endif
        rimLight.light?.intensity = 300
        rimLight.position = SCNVector3(0, 2, -10)
        rimLight.eulerAngles = SCNVector3(0, Float.pi, 0)
        scene.rootNode.addChildNode(rimLight)
        
        // 5. 底部反射光：模拟地面反光，增强上下区分
        let groundReflection = SCNNode()
        groundReflection.light = SCNLight()
        groundReflection.light?.type = .directional
        #if os(macOS)
        groundReflection.light?.color = NSColor(red: 0.2, green: 0.25, blue: 0.4, alpha: 1.0)
        #else
        groundReflection.light?.color = UIColor(red: 0.2, green: 0.25, blue: 0.4, alpha: 1.0)
        #endif
        groundReflection.light?.intensity = 150
        groundReflection.position = SCNVector3(0, -10, 0)
        groundReflection.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)  // 向上照
        scene.rootNode.addChildNode(groundReflection)
    }
    
    // MARK: - 空间参照系统（极简高级版）
    
    private static func addSpatialReference(to scene: SCNScene) {
        // 1. 添加渐变穹顶背景
        addGradientDome(to: scene)
        
        // 2. 添加极简辉光环
        addGlowRing(to: scene)
        
        // 3. 添加深度层次平面（关键：增强前后感）
        addDepthPlanes(to: scene)
        
        // 4. 添加微弱的环境粒子
        addAmbientParticles(to: scene)
        
        // 5. 优化雾效果
        addAtmosphericFog(to: scene)
    }
    
    private static func addGradientDome(to scene: SCNScene) {
        // 创建一个大球体作为背景穹顶
        let domeRadius: CGFloat = 50.0
        let dome = SCNSphere(radius: domeRadius)
        dome.segmentCount = 48
        
        // 创建渐变材质 - 配合光照方向优化
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.diffuse.contents = createGradientImage()
        material.emission.contents = createGradientImage()
        material.emission.intensity = 0.2  // 降低自发光
        material.lightingModel = .constant
        
        dome.materials = [material]
        
        let domeNode = SCNNode(geometry: dome)
        domeNode.name = "gradient_dome"
        domeNode.position = SCNVector3(0, 0, 0)
        domeNode.scale = SCNVector3(-1, 1, 1)
        
        // 添加缓慢旋转动画
        let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 120)  // 2分钟转一圈
        domeNode.runAction(SCNAction.repeatForever(rotation))
        
        scene.rootNode.addChildNode(domeNode)
    }
    
    private static func createGradientImage() -> Any {
        let size = CGSize(width: 256, height: 256)  // 二维渐变
        
        #if os(macOS)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // 径向渐变：中心亮边缘暗（配合主光源方向）
        let gradient = NSGradient(colors: [
            NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0),  // 中心：稍亮的深蓝
            NSColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1.0),  // 中间
            NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0),  // 边缘：更暗
        ], atLocations: [0.0, 0.5, 1.0], colorSpace: .deviceRGB)
        
        gradient?.draw(in: NSRect(origin: .zero, size: size), relativeCenterPosition: NSPoint(x: 0.3, y: 0.6))
        image.unlockFocus()
        return image
        
        #else
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return UIColor.black
        }
        
        let colors = [
            UIColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0).cgColor,
            UIColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1.0).cgColor,
            UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0).cgColor,
        ]
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) {
            let center = CGPoint(x: size.width * 0.6, y: size.height * 0.4)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width, options: [])
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIColor.black
        #endif
    }
    
    // MARK: - 深度层次平面（增强前后空间感）
    
    private static func addDepthPlanes(to scene: SCNScene) {
        // 远处的半透明平面，帮助大脑感知深度
        
        // 后方平面 - 淡淡的蓝色光幕
        let backPlane = SCNPlane(width: 30, height: 20)
        let backMaterial = SCNMaterial()
        backMaterial.diffuse.contents = createDepthGradient(isBack: true)
        backMaterial.emission.contents = createDepthGradient(isBack: true)
        backMaterial.emission.intensity = 0.4
        backMaterial.lightingModel = .constant
        backMaterial.isDoubleSided = true
        backMaterial.blendMode = .add
        backMaterial.writesToDepthBuffer = false  // 不遮挡其他物体
        backPlane.materials = [backMaterial]
        
        let backNode = SCNNode(geometry: backPlane)
        backNode.name = "depth_back"
        backNode.position = SCNVector3(0, 0, -15)
        backNode.opacity = 0.15
        scene.rootNode.addChildNode(backNode)
        
        // 前方微弱的光晕（更近=更亮的暗示）
        let frontPlane = SCNPlane(width: 25, height: 18)
        let frontMaterial = SCNMaterial()
        frontMaterial.diffuse.contents = createDepthGradient(isBack: false)
        frontMaterial.emission.contents = createDepthGradient(isBack: false)
        frontMaterial.emission.intensity = 0.2
        frontMaterial.lightingModel = .constant
        frontMaterial.isDoubleSided = true
        frontMaterial.blendMode = .add
        frontMaterial.writesToDepthBuffer = false
        frontPlane.materials = [frontMaterial]
        
        let frontNode = SCNNode(geometry: frontPlane)
        frontNode.name = "depth_front"
        frontNode.position = SCNVector3(0, 0, 12)
        frontNode.opacity = 0.08
        scene.rootNode.addChildNode(frontNode)
    }
    
    private static func createDepthGradient(isBack: Bool) -> Any {
        let size = CGSize(width: 256, height: 256)
        
        #if os(macOS)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let colors: [NSColor]
        if isBack {
            // 后方：冷色调蓝紫
            colors = [
                NSColor(red: 0.15, green: 0.2, blue: 0.4, alpha: 0.6),
                NSColor(red: 0.1, green: 0.15, blue: 0.3, alpha: 0.3),
                NSColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 0.0),
            ]
        } else {
            // 前方：暖色调
            colors = [
                NSColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 0.4),
                NSColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 0.2),
                NSColor(red: 0.1, green: 0.08, blue: 0.05, alpha: 0.0),
            ]
        }
        
        let gradient = NSGradient(colors: colors, atLocations: [0.0, 0.5, 1.0], colorSpace: .deviceRGB)
        gradient?.draw(in: NSRect(origin: .zero, size: size), relativeCenterPosition: NSPoint(x: 0, y: 0))
        image.unlockFocus()
        return image
        
        #else
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return UIColor.clear
        }
        
        let colors: [CGColor]
        if isBack {
            colors = [
                UIColor(red: 0.15, green: 0.2, blue: 0.4, alpha: 0.6).cgColor,
                UIColor(red: 0.1, green: 0.15, blue: 0.3, alpha: 0.3).cgColor,
                UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 0.0).cgColor,
            ]
        } else {
            colors = [
                UIColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 0.4).cgColor,
                UIColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 0.2).cgColor,
                UIColor(red: 0.1, green: 0.08, blue: 0.05, alpha: 0.0).cgColor,
            ]
        }
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIColor.clear
        #endif
    }
    
    private static func addGlowRing(to scene: SCNScene) {
        let ringY: Float = -2.5  // 地平线位置
        
        // 主光环
        let ringRadius: CGFloat = 8.0
        let ringTube: CGFloat = 0.015
        let ring = SCNTorus(ringRadius: ringRadius, pipeRadius: ringTube)
        
        #if os(macOS)
        let ringColor = NSColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 0.6)
        let glowColor = NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.3)
        #else
        let ringColor = UIColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 0.6)
        let glowColor = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.3)
        #endif
        
        let ringMaterial = SCNMaterial()
        ringMaterial.diffuse.contents = ringColor
        ringMaterial.emission.contents = glowColor
        ringMaterial.emission.intensity = 1.5
        ringMaterial.lightingModel = .constant
        ring.materials = [ringMaterial]
        
        let ringNode = SCNNode(geometry: ring)
        ringNode.name = "glow_ring"
        ringNode.position = SCNVector3(0, ringY, 0)
        ringNode.eulerAngles = SCNVector3(0, 0, 0)  // 水平放置
        
        scene.rootNode.addChildNode(ringNode)
        
        // 外层淡光环（辉光效果）
        let outerRing = SCNTorus(ringRadius: ringRadius, pipeRadius: 0.08)
        
        #if os(macOS)
        let outerGlow = NSColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 0.1)
        #else
        let outerGlow = UIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 0.1)
        #endif
        
        let outerMaterial = SCNMaterial()
        outerMaterial.diffuse.contents = outerGlow
        outerMaterial.emission.contents = outerGlow
        outerMaterial.emission.intensity = 0.8
        outerMaterial.lightingModel = .constant
        outerMaterial.blendMode = .add
        outerRing.materials = [outerMaterial]
        
        let outerNode = SCNNode(geometry: outerRing)
        outerNode.position = SCNVector3(0, ringY, 0)
        scene.rootNode.addChildNode(outerNode)
        
        // 内层细光环
        let innerRing = SCNTorus(ringRadius: 4.0, pipeRadius: 0.008)
        
        #if os(macOS)
        let innerColor = NSColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 0.3)
        #else
        let innerColor = UIColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 0.3)
        #endif
        
        let innerMaterial = SCNMaterial()
        innerMaterial.diffuse.contents = innerColor
        innerMaterial.emission.contents = innerColor
        innerMaterial.emission.intensity = 1.0
        innerMaterial.lightingModel = .constant
        innerRing.materials = [innerMaterial]
        
        let innerNode = SCNNode(geometry: innerRing)
        innerNode.position = SCNVector3(0, ringY + 0.01, 0)
        scene.rootNode.addChildNode(innerNode)
    }
    
    private static func addAmbientParticles(to scene: SCNScene) {
        // 添加微小的星尘粒子（减少数量优化性能）
        let particleCount = 40
        let particleNode = SCNNode()
        particleNode.name = "ambient_particles"
        
        for _ in 0..<particleCount {
            // 在球形区域随机分布
            let theta = Float.random(in: 0...(2 * .pi))
            let phi = Float.random(in: 0...Float.pi)
            let radius = Float.random(in: 8...25)
            
            let x = radius * sin(phi) * cos(theta)
            let y = radius * sin(phi) * sin(theta) - 5  // 稍微偏下
            let z = radius * cos(phi)
            
            let particleSize: CGFloat = CGFloat.random(in: 0.01...0.03)
            let particle = SCNSphere(radius: particleSize)
            
            #if os(macOS)
            let brightness = CGFloat.random(in: 0.3...0.8)
            let particleColor = NSColor(white: brightness, alpha: CGFloat.random(in: 0.2...0.5))
            #else
            let brightness = CGFloat.random(in: 0.3...0.8)
            let particleColor = UIColor(white: brightness, alpha: CGFloat.random(in: 0.2...0.5))
            #endif
            
            let material = SCNMaterial()
            material.diffuse.contents = particleColor
            material.emission.contents = particleColor
            material.emission.intensity = 0.5
            material.lightingModel = .constant
            particle.materials = [material]
            
            let node = SCNNode(geometry: particle)
            node.position = SCNVector3(x, y, z)
            particleNode.addChildNode(node)
        }
        
        // 添加粒子整体缓慢旋转（与穹顶反向，产生层次感）
        let rotation = SCNAction.rotateBy(x: 0, y: -CGFloat.pi * 2, z: 0, duration: 90)  // 1.5分钟转一圈，反向
        particleNode.runAction(SCNAction.repeatForever(rotation))
        
        scene.rootNode.addChildNode(particleNode)
    }
    
    private static func addAtmosphericFog(to scene: SCNScene) {
        // 深度雾效：后方物体更暗，增强前后区分
        #if os(macOS)
        // 使用偏蓝的雾色，与背光协调
        scene.fogColor = NSColor(red: 0.03, green: 0.04, blue: 0.10, alpha: 1.0)
        #else
        scene.fogColor = UIColor(red: 0.03, green: 0.04, blue: 0.10, alpha: 1.0)
        #endif
        scene.fogStartDistance = 5.0   // 更近开始，增强近处清晰感
        scene.fogEndDistance = 25.0
        scene.fogDensityExponent = 1.5  // 指数衰减，后方更快变暗
    }
    
    private func createPhysicsAtom(atom: Atom, index: Int, elementLib: ElementLibrary) -> SCNNode {
        let sphere = SCNSphere(radius: atom.radius)
        sphere.firstMaterial?.diffuse.contents = MoleculeScene.color(for: atom.element)
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
        
        // 添加物理属性
        let physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: sphere, options: nil))
        physicsBody.mass = PhysicsConfig.atomMass
        physicsBody.friction = 1.0  // 最大摩擦
        physicsBody.restitution = 0.0  // 无弹性
        physicsBody.damping = 0.95  // 接近最大线性阻尼
        physicsBody.angularDamping = 0.99  // 接近最大角阻尼
        
        // 碰撞类别设置
        physicsBody.categoryBitMask = 1  // 原子类别
        physicsBody.collisionBitMask = 1 // 与其他原子碰撞
        physicsBody.contactTestBitMask = 1
        
        node.physicsBody = physicsBody
        
        return node
    }
    
    // MARK: - 创建带物理约束的化学键
    
    private func createBondWithPhysics(nodeA: SCNNode, nodeB: SCNNode, idealLength: Float, bondOrder: Int = 1, color: SceneColor, scene: SCNScene) {
        // 根据键级创建不同数量的圆柱体
        var cylinderNodes: [SCNNode] = []
        
        let posA = nodeA.position
        let posB = nodeB.position
        
        if bondOrder == 1 {
            // 单键：一个圆柱体
            let cylinderNode = MoleculeScene.cylinderBetweenPoints(
                pointA: posA,
                pointB: posB,
                radius: 0.08,
                color: color
            )
            scene.rootNode.addChildNode(cylinderNode)
            cylinderNodes.append(cylinderNode)
        } else if bondOrder == 2 {
            // 双键：两个平行圆柱体
            let offset: Float = 0.06  // 双键间距
            let (offsetVec1, offsetVec2) = calculateBondOffsets(posA: posA, posB: posB, offset: offset)
            
            let cylinder1 = MoleculeScene.cylinderBetweenPoints(
                pointA: SCNVector3(posA.x + offsetVec1.x, posA.y + offsetVec1.y, posA.z + offsetVec1.z),
                pointB: SCNVector3(posB.x + offsetVec1.x, posB.y + offsetVec1.y, posB.z + offsetVec1.z),
                radius: 0.06,
                color: color
            )
            let cylinder2 = MoleculeScene.cylinderBetweenPoints(
                pointA: SCNVector3(posA.x + offsetVec2.x, posA.y + offsetVec2.y, posA.z + offsetVec2.z),
                pointB: SCNVector3(posB.x + offsetVec2.x, posB.y + offsetVec2.y, posB.z + offsetVec2.z),
                radius: 0.06,
                color: color
            )
            scene.rootNode.addChildNode(cylinder1)
            scene.rootNode.addChildNode(cylinder2)
            cylinderNodes.append(cylinder1)
            cylinderNodes.append(cylinder2)
        } else if bondOrder == 3 {
            // 三键：三个圆柱体
            let offset: Float = 0.07
            let (offsetVec1, offsetVec2) = calculateBondOffsets(posA: posA, posB: posB, offset: offset)
            
            // 中心键
            let cylinderCenter = MoleculeScene.cylinderBetweenPoints(
                pointA: posA,
                pointB: posB,
                radius: 0.05,
                color: color
            )
            // 两侧键
            let cylinder1 = MoleculeScene.cylinderBetweenPoints(
                pointA: SCNVector3(posA.x + offsetVec1.x, posA.y + offsetVec1.y, posA.z + offsetVec1.z),
                pointB: SCNVector3(posB.x + offsetVec1.x, posB.y + offsetVec1.y, posB.z + offsetVec1.z),
                radius: 0.05,
                color: color
            )
            let cylinder2 = MoleculeScene.cylinderBetweenPoints(
                pointA: SCNVector3(posA.x + offsetVec2.x, posA.y + offsetVec2.y, posA.z + offsetVec2.z),
                pointB: SCNVector3(posB.x + offsetVec2.x, posB.y + offsetVec2.y, posB.z + offsetVec2.z),
                radius: 0.05,
                color: color
            )
            scene.rootNode.addChildNode(cylinderCenter)
            scene.rootNode.addChildNode(cylinder1)
            scene.rootNode.addChildNode(cylinder2)
            cylinderNodes.append(cylinderCenter)
            cylinderNodes.append(cylinder1)
            cylinderNodes.append(cylinder2)
        }
        
        let bond = ChemicalBond(
            atomNode1: nodeA,
            atomNode2: nodeB,
            idealLength: idealLength,
            bondOrder: bondOrder,
            cylinderNodes: cylinderNodes
        )
        bonds.append(bond)
    }
    
    /// 计算双键/三键的偏移向量
    private func calculateBondOffsets(posA: SCNVector3, posB: SCNVector3, offset: Float) -> (SCNVector3, SCNVector3) {
        let dx = posB.x - posA.x
        let dy = posB.y - posA.y
        let dz = posB.z - posA.z
        
        // 键的方向向量
        let bondDir = normalize(SCNVector3(dx, dy, dz))
        
        // 找一个垂直于键方向的向量
        var perpVec: SCNVector3
        if abs(bondDir.y) < 0.9 {
            // 使用 (0, 1, 0) 作为参考
            perpVec = cross(bondDir, SCNVector3(0, 1, 0))
        } else {
            // 如果键接近垂直，使用 (1, 0, 0)
            perpVec = cross(bondDir, SCNVector3(1, 0, 0))
        }
        perpVec = normalize(perpVec)
        
        let offsetVec1 = SCNVector3(perpVec.x * offset, perpVec.y * offset, perpVec.z * offset)
        let offsetVec2 = SCNVector3(-perpVec.x * offset, -perpVec.y * offset, -perpVec.z * offset)
        
        return (offsetVec1, offsetVec2)
    }
    
    // MARK: - 物理更新（每帧调用）
    
    func updatePhysics() {
        frameCounter += 1
        
        // 每帧都更新化学键视觉（保持流畅）
        for bond in bonds {
            updateBondVisual(bond: bond)
        }
        
        // 物理力计算可以降频执行以优化性能
        if frameCounter % PhysicsConfig.physicsUpdateInterval == 0 {
            // 更新化学键的弹簧力（增强多重键的刚度）
            for bond in bonds {
                applySpringForce(bond: bond)
            }
            
            // 应用键角约束力
            applyAngleConstraints()
        }
        
        // 成键检测进一步降频（计算量较大）
        if frameCounter % PhysicsConfig.bondCheckInterval == 0 {
            checkAndCreateBonds()
        }
    }
    
    // MARK: - 键角约束
    
    /// 应用键角约束力，使分子保持正确的几何形状
    private func applyAngleConstraints() {
        let elementLib = ElementLibrary.shared
        
        // 找出每个原子连接的所有键及键级
        var atomBonds: [SCNNode: [(bond: ChemicalBond, bondOrder: Int)]] = [:]
        for bond in bonds {
            atomBonds[bond.atomNode1, default: []].append((bond, bond.bondOrder))
            atomBonds[bond.atomNode2, default: []].append((bond, bond.bondOrder))
        }
        
        // 对每个有多个键的原子应用键角约束
        for (centerNode, connectedBonds) in atomBonds {
            guard connectedBonds.count >= 2 else { continue }
            
            let centerElement = extractElement(from: centerNode)
            
            // 检查是否有多重键（影响杂化类型）
            let hasMultipleBond = connectedBonds.contains { $0.bondOrder > 1 }
            
            // 根据邻居数量和键级确定理想键角
            let neighborCount = connectedBonds.count
            let idealAngle = elementLib.getIdealBondAngleForConfiguration(
                centerElement: centerElement,
                neighborCount: neighborCount,
                hasMultipleBond: hasMultipleBond
            )
            
            // 获取连接的邻居原子
            var neighbors: [(node: SCNNode, bondOrder: Int)] = []
            for bondInfo in connectedBonds {
                let neighbor = bondInfo.bond.atomNode1 === centerNode ? bondInfo.bond.atomNode2 : bondInfo.bond.atomNode1
                neighbors.append((neighbor, bondInfo.bondOrder))
            }
            
            // 判断分子几何类型
            let geometry = determineGeometry(neighborCount: neighborCount, hasMultipleBond: hasMultipleBond, centerElement: centerElement)
            
            // 根据几何类型应用不同的约束策略
            switch geometry {
            case .linear:
                // 线性分子（如 CO₂）：强制 180 度角
                if neighbors.count == 2 {
                    applyLinearConstraint(
                        centerNode: centerNode,
                        neighbor1: neighbors[0].node,
                        neighbor2: neighbors[1].node
                    )
                }
                
            case .trigonalPlanar:
                // 平面三角形（如 BH₃, C=C双键周围）：所有角度 120 度，且在同一平面
                applyPlanarConstraint(
                    centerNode: centerNode,
                    neighbors: neighbors.map { $0.node },
                    idealAngle: idealAngle
                )
                
            case .bentSp3:
                // 弯曲型分子（如 H₂O, H₂S）：使用专门的弯曲约束
                if neighbors.count == 2 {
                    applyBentConstraint(
                        centerNode: centerNode,
                        neighbor1: neighbors[0].node,
                        neighbor2: neighbors[1].node,
                        idealAngle: idealAngle
                    )
                } else {
                    // 多于2个邻居时使用通用角度约束
                    for i in 0..<neighbors.count {
                        for j in (i+1)..<neighbors.count {
                            applyAngleForce(
                                centerNode: centerNode,
                                neighbor1: neighbors[i].node,
                                neighbor2: neighbors[j].node,
                                idealAngle: idealAngle,
                                geometry: geometry
                            )
                        }
                    }
                }
                
            case .tetrahedral, .pyramidal:
                // 四面体或三角锥：使用原有的角度约束
                for i in 0..<neighbors.count {
                    for j in (i+1)..<neighbors.count {
                        applyAngleForce(
                            centerNode: centerNode,
                            neighbor1: neighbors[i].node,
                            neighbor2: neighbors[j].node,
                            idealAngle: idealAngle,
                            geometry: geometry
                        )
                    }
                }
            }
        }
    }
    
    /// 判断分子几何类型
    private func determineGeometry(neighborCount: Int, hasMultipleBond: Bool, centerElement: String) -> MolecularGeometry {
        let element = centerElement.lowercased()
        
        // 2个邻居
        if neighborCount == 2 {
            // 氧和硫：弯曲型（sp³杂化，有孤对电子）
            // 这是 H₂O, H₂S 等分子的情况
            if element == "o" || element == "s" {
                // 只有当有多重键时才可能是线性（如 CO₂ 中的碳两边各有一个氧）
                // 但如果氧是中心原子且有2个邻居，一定是弯曲型
                return .bentSp3
            }
            
            // 碳、氮等：如果有多重键，是线性（sp杂化）
            if hasMultipleBond {
                // 如 CO₂ (O=C=O), HCN (H-C≡N)
                return .linear
            }
            
            // 默认2邻居无多重键：弯曲或线性取决于元素
            // 大多数情况下没有孤对电子的是线性
            return .linear
        }
        
        // 3个邻居
        if neighborCount == 3 {
            if hasMultipleBond || element == "b" {
                // 有双键或硼：平面三角形
                return .trigonalPlanar
            }
            if element == "n" || element == "p" {
                // 氮、磷：三角锥形（有一对孤对电子）
                return .pyramidal
            }
            return .trigonalPlanar
        }
        
        // 4个或更多邻居：四面体
        return .tetrahedral
    }
    
    /// 线性分子约束（强制 180 度）
    private func applyLinearConstraint(centerNode: SCNNode, neighbor1: SCNNode, neighbor2: SCNNode) {
        guard let centerBody = centerNode.physicsBody,
              let body1 = neighbor1.physicsBody,
              let body2 = neighbor2.physicsBody else { return }
        
        let centerPos = centerNode.presentation.position
        let pos1 = neighbor1.presentation.position
        let pos2 = neighbor2.presentation.position
        
        // 计算从中心到两个邻居的向量
        let v1 = SCNVector3(pos1.x - centerPos.x, pos1.y - centerPos.y, pos1.z - centerPos.z)
        let v2 = SCNVector3(pos2.x - centerPos.x, pos2.y - centerPos.y, pos2.z - centerPos.z)
        
        let len1 = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z)
        let len2 = sqrt(v2.x*v2.x + v2.y*v2.y + v2.z*v2.z)
        
        guard len1 > 0.001, len2 > 0.001 else { return }
        
        // 归一化向量
        let n1 = SCNVector3(v1.x/len1, v1.y/len1, v1.z/len1)
        let n2 = SCNVector3(v2.x/len2, v2.y/len2, v2.z/len2)
        
        // 对于线性分子，两个向量应该反向（点积 = -1）
        // 计算偏离程度
        let dotProduct = n1.x*n2.x + n1.y*n2.y + n1.z*n2.z
        
        // 理想情况 dotProduct = -1（180度）
        // 偏离量 = dotProduct - (-1) = dotProduct + 1
        let deviation = dotProduct + 1.0  // 越接近0越好
        
        if abs(deviation) < 0.01 { return }  // 已经足够直了
        
        // 强力约束：将两个原子推向共线位置
        let linearStrength: Float = PhysicsConfig.angleStiffness * 3.0  // 线性分子使用更强的约束
        
        // 找到理想位置：neighbor2 应该在 centerNode 相对于 neighbor1 的反方向
        let idealDir2 = SCNVector3(-n1.x, -n1.y, -n1.z)
        
        // 计算 neighbor2 当前方向与理想方向的差异
        let correction2 = SCNVector3(
            (idealDir2.x - n2.x) * linearStrength,
            (idealDir2.y - n2.y) * linearStrength,
            (idealDir2.z - n2.z) * linearStrength
        )
        
        // 类似地，neighbor1 应该在 centerNode 相对于 neighbor2 的反方向
        let idealDir1 = SCNVector3(-n2.x, -n2.y, -n2.z)
        let correction1 = SCNVector3(
            (idealDir1.x - n1.x) * linearStrength,
            (idealDir1.y - n1.y) * linearStrength,
            (idealDir1.z - n1.z) * linearStrength
        )
        
        body1.applyForce(correction1, asImpulse: false)
        body2.applyForce(correction2, asImpulse: false)
        
        // 中心原子受到反作用力，保持在中间
        let centerCorrection = SCNVector3(
            -(correction1.x + correction2.x) * 0.5,
            -(correction1.y + correction2.y) * 0.5,
            -(correction1.z + correction2.z) * 0.5
        )
        centerBody.applyForce(centerCorrection, asImpulse: false)
        
        // 添加强阻尼以稳定
        applyLinearDamping(body1: body1, body2: body2, n1: n1, n2: n2)
    }
    
    /// 线性分子的阻尼
    private func applyLinearDamping(body1: SCNPhysicsBody, body2: SCNPhysicsBody, n1: SCNVector3, n2: SCNVector3) {
        let dampingStrength: Float = PhysicsConfig.angleDamping * 2.0
        
        // 计算垂直于键轴的速度分量并阻尼
        let vel1 = body1.velocity
        let vel2 = body2.velocity
        
        // 对于 body1，阻尼掉垂直于 n1 的速度分量
        let velAlongN1 = vel1.x*n1.x + vel1.y*n1.y + vel1.z*n1.z
        let velPerp1 = SCNVector3(
            vel1.x - n1.x * velAlongN1,
            vel1.y - n1.y * velAlongN1,
            vel1.z - n1.z * velAlongN1
        )
        let damp1 = SCNVector3(
            -velPerp1.x * dampingStrength,
            -velPerp1.y * dampingStrength,
            -velPerp1.z * dampingStrength
        )
        
        let velAlongN2 = vel2.x*n2.x + vel2.y*n2.y + vel2.z*n2.z
        let velPerp2 = SCNVector3(
            vel2.x - n2.x * velAlongN2,
            vel2.y - n2.y * velAlongN2,
            vel2.z - n2.z * velAlongN2
        )
        let damp2 = SCNVector3(
            -velPerp2.x * dampingStrength,
            -velPerp2.y * dampingStrength,
            -velPerp2.z * dampingStrength
        )
        
        body1.applyForce(damp1, asImpulse: false)
        body2.applyForce(damp2, asImpulse: false)
    }
    
    /// 弯曲分子约束（如 H₂O，使用简单直接的角度约束）
    private func applyBentConstraint(centerNode: SCNNode, neighbor1: SCNNode, neighbor2: SCNNode, idealAngle: Float) {
        // 直接使用通用的角度约束，强度稍高
        applyAngleForce(
            centerNode: centerNode,
            neighbor1: neighbor1,
            neighbor2: neighbor2,
            idealAngle: idealAngle,
            geometry: .bentSp3
        )
    }
    
    /// 平面三角形约束
    private func applyPlanarConstraint(centerNode: SCNNode, neighbors: [SCNNode], idealAngle: Float) {
        guard neighbors.count >= 2 else { return }
        
        // 对每对邻居应用角度约束
        for i in 0..<neighbors.count {
            for j in (i+1)..<neighbors.count {
                applyAngleForce(
                    centerNode: centerNode,
                    neighbor1: neighbors[i],
                    neighbor2: neighbors[j],
                    idealAngle: idealAngle,
                    geometry: .trigonalPlanar
                )
            }
        }
        
        // 如果有3个邻居，额外施加平面约束
        if neighbors.count == 3 {
            applyPlanarityForce(centerNode: centerNode, neighbors: neighbors)
        }
    }
    
    /// 强制三个邻居保持在同一平面
    private func applyPlanarityForce(centerNode: SCNNode, neighbors: [SCNNode]) {
        guard neighbors.count == 3 else { return }
        guard let body0 = neighbors[0].physicsBody,
              let body1 = neighbors[1].physicsBody,
              let body2 = neighbors[2].physicsBody else { return }
        
        let centerPos = centerNode.presentation.position
        let pos0 = neighbors[0].presentation.position
        let pos1 = neighbors[1].presentation.position
        let pos2 = neighbors[2].presentation.position
        
        // 计算从中心到三个邻居的向量
        let v0 = SCNVector3(pos0.x - centerPos.x, pos0.y - centerPos.y, pos0.z - centerPos.z)
        let v1 = SCNVector3(pos1.x - centerPos.x, pos1.y - centerPos.y, pos1.z - centerPos.z)
        let v2 = SCNVector3(pos2.x - centerPos.x, pos2.y - centerPos.y, pos2.z - centerPos.z)
        
        // 计算平面法向量（使用前两个向量的叉积）
        let planeNormal = normalize(cross(v0, v1))
        
        // 计算第三个原子到平面的距离
        let distToPlane = v2.x * planeNormal.x + v2.y * planeNormal.y + v2.z * planeNormal.z
        
        // 如果距离太大，施加力将第三个原子拉回平面
        if abs(distToPlane) > 0.01 {
            let planarityStrength: Float = PhysicsConfig.angleStiffness * 0.5
            let force = SCNVector3(
                -planeNormal.x * distToPlane * planarityStrength,
                -planeNormal.y * distToPlane * planarityStrength,
                -planeNormal.z * distToPlane * planarityStrength
            )
            body2.applyForce(force, asImpulse: false)
        }
    }
    
    /// 计算并应用键角力（使用简单的位置约束方法）
    private func applyAngleForce(centerNode: SCNNode, neighbor1: SCNNode, neighbor2: SCNNode, idealAngle: Float, geometry: MolecularGeometry = .tetrahedral) {
        guard let centerBody = centerNode.physicsBody,
              let body1 = neighbor1.physicsBody,
              let body2 = neighbor2.physicsBody else { return }
        
        let centerPos = centerNode.presentation.position
        let pos1 = neighbor1.presentation.position
        let pos2 = neighbor2.presentation.position
        
        // 计算从中心到两个邻居的向量
        let v1 = SCNVector3(pos1.x - centerPos.x, pos1.y - centerPos.y, pos1.z - centerPos.z)
        let v2 = SCNVector3(pos2.x - centerPos.x, pos2.y - centerPos.y, pos2.z - centerPos.z)
        
        let len1 = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z)
        let len2 = sqrt(v2.x*v2.x + v2.y*v2.y + v2.z*v2.z)
        
        guard len1 > 0.001, len2 > 0.001 else { return }
        
        // 归一化向量
        let n1 = SCNVector3(v1.x/len1, v1.y/len1, v1.z/len1)
        let n2 = SCNVector3(v2.x/len2, v2.y/len2, v2.z/len2)
        
        // 计算当前角度
        let dotProduct = n1.x*n2.x + n1.y*n2.y + n1.z*n2.z
        let clampedDot = max(-1.0, min(1.0, dotProduct))
        let currentAngle = acos(clampedDot)
        
        // 如果角度已经非常接近，只施加阻尼
        let angleDiff = currentAngle - idealAngle
        if abs(angleDiff) < 0.02 {
            applyStrongDamping(body1: body1, body2: body2, centerBody: centerBody)
            return
        }
        
        // 使用极简方法：直接计算邻居间应有的距离
        // 余弦定理：d² = r1² + r2² - 2*r1*r2*cos(θ)
        let idealNeighborDist = sqrt(len1*len1 + len2*len2 - 2*len1*len2*cos(idealAngle))
        
        // 当前邻居间距离
        let dx = pos2.x - pos1.x
        let dy = pos2.y - pos1.y
        let dz = pos2.z - pos1.z
        let currentNeighborDist = sqrt(dx*dx + dy*dy + dz*dz)
        
        guard currentNeighborDist > 0.001 else { return }
        
        // 计算需要的位移
        let distError = currentNeighborDist - idealNeighborDist
        
        // 方向：从pos1指向pos2
        let dirX = dx / currentNeighborDist
        let dirY = dy / currentNeighborDist
        let dirZ = dz / currentNeighborDist
        
        // 力的大小 - 使用弹簧常数
        let forceMagnitude = PhysicsConfig.angleStiffness * distError * 0.3
        
        // neighbor1 朝向 neighbor2 移动（如果需要拉近）
        let force1 = SCNVector3(dirX * forceMagnitude, dirY * forceMagnitude, dirZ * forceMagnitude)
        let force2 = SCNVector3(-dirX * forceMagnitude, -dirY * forceMagnitude, -dirZ * forceMagnitude)
        
        body1.applyForce(force1, asImpulse: false)
        body2.applyForce(force2, asImpulse: false)
        
        // 施加强阻尼
        applyStrongDamping(body1: body1, body2: body2, centerBody: centerBody)
    }
    
    /// 对所有相关原子施加强阻尼
    private func applyStrongDamping(body1: SCNPhysicsBody, body2: SCNPhysicsBody, centerBody: SCNPhysicsBody) {
        let dampingStrength: Float = PhysicsConfig.angleDamping * 1.5
        
        // 直接阻尼所有速度
        let vel1 = body1.velocity
        let vel2 = body2.velocity
        let velC = centerBody.velocity
        
        body1.applyForce(SCNVector3(-vel1.x * dampingStrength, -vel1.y * dampingStrength, -vel1.z * dampingStrength), asImpulse: false)
        body2.applyForce(SCNVector3(-vel2.x * dampingStrength, -vel2.y * dampingStrength, -vel2.z * dampingStrength), asImpulse: false)
        centerBody.applyForce(SCNVector3(-velC.x * dampingStrength, -velC.y * dampingStrength, -velC.z * dampingStrength), asImpulse: false)
    }
    
    // MARK: - 动态成键检测
    
    private func checkAndCreateBonds() {
        let elementLib = ElementLibrary.shared
        
        for i in 0..<atomNodes.count {
            for j in (i+1)..<atomNodes.count {
                let nodeA = atomNodes[i]
                let nodeB = atomNodes[j]
                
                // 检查是否已经有化学键连接
                let hasBond = bonds.contains { bond in
                    (bond.atomNode1 === nodeA && bond.atomNode2 === nodeB) ||
                    (bond.atomNode1 === nodeB && bond.atomNode2 === nodeA)
                }
                
                let posA = nodeA.presentation.position
                let posB = nodeB.presentation.position
                let dist = distance(posA, posB)
                
                let elementA = extractElement(from: nodeA)
                let elementB = extractElement(from: nodeB)
                
                // 计算剩余成键能力
                let maxBonds1 = elementLib.getMaxBonds(for: elementA)
                let maxBonds2 = elementLib.getMaxBonds(for: elementB)
                let remainingBonds1 = max(0, maxBonds1 - bondCounts[i])
                let remainingBonds2 = max(0, maxBonds2 - bondCounts[j])
                
                // 计算应该形成的键级
                let potentialBondOrder = elementLib.calculateBondOrder(
                    element1: elementA,
                    element2: elementB,
                    remainingBonds1: remainingBonds1,
                    remainingBonds2: remainingBonds2
                )
                
                let idealLength = elementLib.getIdealBondLength(between: elementA, and: elementB, bondOrder: max(1, potentialBondOrder))
                let maxBondDist = idealLength * 1.4  // 最大成键距离（对多重键稍微放宽）
                let minSafeDist = idealLength * 0.5  // 最小安全距离
                
                if hasBond {
                    // 已有键，只需检查是否需要断键（距离过远）
                    if dist > idealLength * 2.5 {
                        // 距离太远，断开化学键
                        removeBondInternal(between: nodeA, and: nodeB)
                    }
                    continue
                }
                
                // 检查是否能成键
                let canForm = remainingBonds1 > 0 && remainingBonds2 > 0 && potentialBondOrder > 0
                
                if canForm && dist < maxBondDist && dist > minSafeDist {
                    // 在成键范围内，创建新键（支持多重键）
                    createBondDynamic(nodeA: nodeA, nodeB: nodeB, indexA: i, indexB: j, idealLength: idealLength, bondOrder: potentialBondOrder)
                } else if canForm && dist < idealLength * 2.5 && dist > maxBondDist {
                    // 在吸引范围内但还未成键，施加吸引力
                    applyAttractionForce(nodeA: nodeA, nodeB: nodeB, dist: dist, idealLength: idealLength)
                } else if dist < minSafeDist && dist > 0.01 {
                    // 距离太近，施加排斥力
                    applyRepulsionForce(nodeA: nodeA, nodeB: nodeB, dist: dist)
                }
            }
        }
    }
    
    private func createBondDynamic(nodeA: SCNNode, nodeB: SCNNode, indexA: Int, indexB: Int, idealLength: Float, bondOrder: Int = 1) {
        guard let scene = scene else { return }
        
        // 创建化学键（支持多重键）
        createBondWithPhysics(
            nodeA: nodeA,
            nodeB: nodeB,
            idealLength: idealLength,
            bondOrder: bondOrder,
            color: .lightGray,
            scene: scene
        )
        
        // 更新成键计数（按键级计算）
        if indexA < bondCounts.count {
            bondCounts[indexA] += bondOrder
        }
        if indexB < bondCounts.count {
            bondCounts[indexB] += bondOrder
        }
        
        // 记录键级
        if indexA < atomBondOrders.count && indexB < atomBondOrders.count {
            atomBondOrders[indexA][indexB] = bondOrder
            atomBondOrders[indexB][indexA] = bondOrder
        }
    }
    
    private func removeBondInternal(between nodeA: SCNNode, and nodeB: SCNNode) {
        // 找到对应的索引
        var indexA: Int?
        var indexB: Int?
        for (idx, node) in atomNodes.enumerated() {
            if node === nodeA { indexA = idx }
            if node === nodeB { indexB = idx }
        }
        
        bonds.removeAll { bond in
            let match = (bond.atomNode1 === nodeA && bond.atomNode2 === nodeB) ||
                       (bond.atomNode1 === nodeB && bond.atomNode2 === nodeA)
            if match {
                // 移除所有圆柱体节点
                for cylinderNode in bond.cylinderNodes {
                    cylinderNode.removeFromParentNode()
                }
                // 更新成键计数（考虑键级）
                if let ia = indexA, ia < bondCounts.count {
                    bondCounts[ia] = max(0, bondCounts[ia] - bond.bondOrder)
                }
                if let ib = indexB, ib < bondCounts.count {
                    bondCounts[ib] = max(0, bondCounts[ib] - bond.bondOrder)
                }
                // 清除键级记录
                if let ia = indexA, let ib = indexB {
                    atomBondOrders[ia][ib] = nil
                    atomBondOrders[ib][ia] = nil
                }
            }
            return match
        }
    }
    
    private func applyAttractionForce(nodeA: SCNNode, nodeB: SCNNode, dist: Float, idealLength: Float) {
        guard let bodyA = nodeA.physicsBody,
              let bodyB = nodeB.physicsBody else { return }
        
        let posA = nodeA.presentation.position
        let posB = nodeB.presentation.position
        
        let dx = posB.x - posA.x
        let dy = posB.y - posA.y
        let dz = posB.z - posA.z
        
        // 吸引力：距离越近越强（但不超过成键距离）
        let attractionFactor = (dist - idealLength) / idealLength
        let forceMagnitude = PhysicsConfig.attractionStrength * attractionFactor
        
        let nx = dx / dist
        let ny = dy / dist
        let nz = dz / dist
        
        // A 被拉向 B，B 被拉向 A
        let forceA = SCNVector3(nx * forceMagnitude, ny * forceMagnitude, nz * forceMagnitude)
        let forceB = SCNVector3(-nx * forceMagnitude, -ny * forceMagnitude, -nz * forceMagnitude)
        
        bodyA.applyForce(forceA, asImpulse: false)
        bodyB.applyForce(forceB, asImpulse: false)
    }
    
    private func applyRepulsionForce(nodeA: SCNNode, nodeB: SCNNode, dist: Float) {
        guard let bodyA = nodeA.physicsBody,
              let bodyB = nodeB.physicsBody else { return }
        
        let posA = nodeA.presentation.position
        let posB = nodeB.presentation.position
        
        let dx = posB.x - posA.x
        let dy = posB.y - posA.y
        let dz = posB.z - posA.z
        
        // 排斥力（类似库仑力）
        let forceMagnitude = PhysicsConfig.repulsionStrength / (dist * dist)
        
        let nx = dx / dist
        let ny = dy / dist
        let nz = dz / dist
        
        let forceA = SCNVector3(-nx * forceMagnitude, -ny * forceMagnitude, -nz * forceMagnitude)
        let forceB = SCNVector3(nx * forceMagnitude, ny * forceMagnitude, nz * forceMagnitude)
        
        bodyA.applyForce(forceA, asImpulse: false)
        bodyB.applyForce(forceB, asImpulse: false)
    }
    
    private func applySpringForce(bond: ChemicalBond) {
        guard let bodyA = bond.atomNode1.physicsBody,
              let bodyB = bond.atomNode2.physicsBody else { return }
        
        let posA = bond.atomNode1.presentation.position
        let posB = bond.atomNode2.presentation.position
        
        let dx = posB.x - posA.x
        let dy = posB.y - posA.y
        let dz = posB.z - posA.z
        let currentLength = sqrt(dx*dx + dy*dy + dz*dz)
        
        guard currentLength > 0.001 else { return }
        
        // 多重键使用更高的刚度
        let stiffnessMultiplier = Float(bond.bondOrder)
        
        // 弹簧力 F = -k * (x - x0)
        let displacement = currentLength - bond.idealLength
        let forceMagnitude = Float(PhysicsConfig.bondStiffness) * displacement * stiffnessMultiplier
        
        // 方向向量（归一化）
        let nx = dx / currentLength
        let ny = dy / currentLength
        let nz = dz / currentLength
        
        // 应用力（牛顿第三定律）
        let forceA = SCNVector3(nx * forceMagnitude, ny * forceMagnitude, nz * forceMagnitude)
        let forceB = SCNVector3(-nx * forceMagnitude, -ny * forceMagnitude, -nz * forceMagnitude)
        
        bodyA.applyForce(forceA, asImpulse: false)
        bodyB.applyForce(forceB, asImpulse: false)
        
        // 阻尼力 - 大幅增强以消除振荡
        let velA = bodyA.velocity
        let velB = bodyB.velocity
        
        let relVelX = velB.x - velA.x
        let relVelY = velB.y - velA.y
        let relVelZ = velB.z - velA.z
        
        // 沿连接方向的相对速度
        let relVelAlongBond = relVelX * nx + relVelY * ny + relVelZ * nz
        let dampingForce = Float(PhysicsConfig.bondDamping) * relVelAlongBond * stiffnessMultiplier
        
        let dampA = SCNVector3(nx * dampingForce, ny * dampingForce, nz * dampingForce)
        let dampB = SCNVector3(-nx * dampingForce, -ny * dampingForce, -nz * dampingForce)
        
        bodyA.applyForce(dampA, asImpulse: false)
        bodyB.applyForce(dampB, asImpulse: false)
        
        // 额外的全局阻尼 - 抑制所有运动
        let globalDamping: Float = 2.0
        bodyA.applyForce(SCNVector3(-velA.x * globalDamping, -velA.y * globalDamping, -velA.z * globalDamping), asImpulse: false)
        bodyB.applyForce(SCNVector3(-velB.x * globalDamping, -velB.y * globalDamping, -velB.z * globalDamping), asImpulse: false)
    }
    
    private func updateBondVisual(bond: ChemicalBond) {
        // 更新所有圆柱体位置和方向
        let posA = bond.atomNode1.presentation.position
        let posB = bond.atomNode2.presentation.position
        
        let dx = posB.x - posA.x
        let dy = posB.y - posA.y
        let dz = posB.z - posA.z
        let length = sqrt(dx*dx + dy*dy + dz*dz)
        
        // 计算方向和旋转
        let direction = SCNVector3(dx, dy, dz)
        let from = SCNVector3(0, 1, 0)
        let to = normalize(direction)
        let axis = cross(from, to)
        let dotv = dot(from, to)
        let angle = acos(max(min(dotv, 1), -1))
        
        var rotation: SCNVector4
        if sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z) < 1e-6 {
            rotation = dotv < 0 ? SCNVector4(1, 0, 0, Float.pi) : SCNVector4(0, 1, 0, 0)
        } else {
            let axisN = normalize(axis)
            rotation = SCNVector4(axisN.x, axisN.y, axisN.z, angle)
        }
        
        if bond.bondOrder == 1 {
            // 单键：简单更新
            guard let cylinderNode = bond.cylinderNodes.first else { return }
            cylinderNode.position = SCNVector3(
                (posA.x + posB.x) / 2,
                (posA.y + posB.y) / 2,
                (posA.z + posB.z) / 2
            )
            if let cylinder = cylinderNode.geometry as? SCNCylinder {
                cylinder.height = CGFloat(length)
            }
            cylinderNode.rotation = rotation
        } else {
            // 双键/三键：更新所有圆柱体，保持偏移
            let offset: Float = bond.bondOrder == 2 ? 0.06 : 0.07
            let (offsetVec1, offsetVec2) = calculateBondOffsets(posA: posA, posB: posB, offset: offset)
            
            for (index, cylinderNode) in bond.cylinderNodes.enumerated() {
                var cylinderPosA = posA
                var cylinderPosB = posB
                
                if bond.bondOrder == 2 {
                    // 双键：两个圆柱体分别偏移
                    if index == 0 {
                        cylinderPosA = SCNVector3(posA.x + offsetVec1.x, posA.y + offsetVec1.y, posA.z + offsetVec1.z)
                        cylinderPosB = SCNVector3(posB.x + offsetVec1.x, posB.y + offsetVec1.y, posB.z + offsetVec1.z)
                    } else {
                        cylinderPosA = SCNVector3(posA.x + offsetVec2.x, posA.y + offsetVec2.y, posA.z + offsetVec2.z)
                        cylinderPosB = SCNVector3(posB.x + offsetVec2.x, posB.y + offsetVec2.y, posB.z + offsetVec2.z)
                    }
                } else if bond.bondOrder == 3 {
                    // 三键：中心 + 两侧
                    if index == 0 {
                        // 中心保持原位
                    } else if index == 1 {
                        cylinderPosA = SCNVector3(posA.x + offsetVec1.x, posA.y + offsetVec1.y, posA.z + offsetVec1.z)
                        cylinderPosB = SCNVector3(posB.x + offsetVec1.x, posB.y + offsetVec1.y, posB.z + offsetVec1.z)
                    } else {
                        cylinderPosA = SCNVector3(posA.x + offsetVec2.x, posA.y + offsetVec2.y, posA.z + offsetVec2.z)
                        cylinderPosB = SCNVector3(posB.x + offsetVec2.x, posB.y + offsetVec2.y, posB.z + offsetVec2.z)
                    }
                }
                
                cylinderNode.position = SCNVector3(
                    (cylinderPosA.x + cylinderPosB.x) / 2,
                    (cylinderPosA.y + cylinderPosB.y) / 2,
                    (cylinderPosA.z + cylinderPosB.z) / 2
                )
                if let cylinder = cylinderNode.geometry as? SCNCylinder {
                    cylinder.height = CGFloat(length)
                }
                cylinderNode.rotation = rotation
            }
        }
    }
    
    // MARK: - 拖拽原子
    
    func dragAtom(_ node: SCNNode, to position: SCNVector3) {
        // 临时将原子设为运动学物体，直接控制位置
        if let body = node.physicsBody {
            body.type = .kinematic
            node.position = position
        }
    }
    
    func releaseAtom(_ node: SCNNode) {
        // 恢复为动态物体
        if let body = node.physicsBody {
            body.type = .dynamic
            body.velocity = SCNVector3Zero
            body.angularVelocity = SCNVector4Zero
        }
    }
    
    // MARK: - 添加新的化学键
    
    func addBond(between nodeA: SCNNode, and nodeB: SCNNode) {
        guard let scene = scene else { return }
        
        let elementA = extractElement(from: nodeA)
        let elementB = extractElement(from: nodeB)
        let idealLength = ElementLibrary.shared.getIdealBondLength(between: elementA, and: elementB)
        
        createBondWithPhysics(
            nodeA: nodeA,
            nodeB: nodeB,
            idealLength: idealLength,
            color: .cyan,
            scene: scene
        )
    }
    
    func removeBond(between nodeA: SCNNode, and nodeB: SCNNode) {
        bonds.removeAll { bond in
            let match = (bond.atomNode1 === nodeA && bond.atomNode2 === nodeB) ||
                       (bond.atomNode1 === nodeB && bond.atomNode2 === nodeA)
            if match {
                // 移除所有圆柱体节点
                for cylinderNode in bond.cylinderNodes {
                    cylinderNode.removeFromParentNode()
                }
            }
            return match
        }
    }
    
    // MARK: - 辅助方法
    
    private func extractElement(from node: SCNNode) -> String {
        if let metadata = node.templateMetadata {
            return metadata.element
        }
        if let name = node.name, let symbol = name.split(separator: "#").first {
            return String(symbol)
        }
        return "C"
    }
    
    private func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    private func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        a.x*b.x + a.y*b.y + a.z*b.z
    }
    
    private func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
    }
    
    private func normalize(_ v: SCNVector3) -> SCNVector3 {
        let len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
        guard len > 0 else { return SCNVector3(0, 0, 0) }
        return SCNVector3(v.x/len, v.y/len, v.z/len)
    }
}
