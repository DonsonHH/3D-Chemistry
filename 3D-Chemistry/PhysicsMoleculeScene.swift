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
        static let bondStiffness: CGFloat = 80.0    // 化学键弹簧刚度（增强）
        static let bondDamping: CGFloat = 5.0       // 化学键阻尼（增强以减少振荡）
        static let angleStiffness: Float = 25.0     // 键角弹簧刚度
        static let angleDamping: Float = 3.0        // 键角阻尼
        static let attractionStrength: Float = 2.0  // 可成键原子间吸引力
        static let repulsionStrength: Float = 0.3   // 原子间排斥力强度（降低）
        static let gravity: SCNVector3 = SCNVector3(0, 0, 0)  // 无重力（分子漂浮）
        static let airFriction: CGFloat = 0.5       // 空气阻力（增强以稳定）
        static let restitution: CGFloat = 0.3       // 弹性碰撞系数（降低）
        static let physicsUpdateInterval: Int = 3   // 每N帧更新一次物理（优化性能）
        static let bondCheckInterval: Int = 6       // 成键检测间隔（进一步降频）
    }
    
    // MARK: - 化学键结构
    struct ChemicalBond: Equatable {
        let atomNode1: SCNNode
        let atomNode2: SCNNode
        let idealLength: Float
        let cylinderNode: SCNNode
        
        static func == (lhs: ChemicalBond, rhs: ChemicalBond) -> Bool {
            return lhs.atomNode1 === rhs.atomNode1 && lhs.atomNode2 === rhs.atomNode2
        }
    }
    
    // 键角平面记忆结构（用于稳定分子构型）
    struct AnglePlaneMemory {
        let centerNode: SCNNode
        var planeNormal: SCNVector3  // 键角平面的法向量
        var isEstablished: Bool = false  // 是否已建立稳定的平面
    }
    
    private var bonds: [ChemicalBond] = []
    private var atomNodes: [SCNNode] = []
    private var bondCounts: [Int] = []  // 每个原子当前的成键数
    private var frameCounter: Int = 0   // 帧计数器（用于优化）
    private var anglePlaneMemories: [ObjectIdentifier: AnglePlaneMemory] = [:]  // 记忆每个中心原子的键角平面
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
        
        // 初始化成键计数
        manager.bondCounts = Array(repeating: 0, count: atoms.count)
        
        // 创建手动键（使用物理约束）
        var manualBondedPairs = Set<String>()
        for manualBond in manualBonds {
            let i = manualBond.atomIndex1
            let j = manualBond.atomIndex2
            
            guard i < atoms.count && j < atoms.count else { continue }
            
            let nodeA = manager.atomNodes[i]
            let nodeB = manager.atomNodes[j]
            
            let idealLength = elementLib.getIdealBondLength(between: atoms[i].element, and: atoms[j].element)
            
            // 创建化学键视觉效果和物理约束
            manager.createBondWithPhysics(
                nodeA: nodeA,
                nodeB: nodeB,
                idealLength: idealLength,
                color: .cyan,
                scene: scene
            )
            
            manager.bondCounts[i] += 1
            manager.bondCounts[j] += 1
            
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
        
        // 自动判断键
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
                
                let canForm = elementLib.canFormBond(
                    between: elementA,
                    and: elementB,
                    currentBonds1: manager.bondCounts[i],
                    currentBonds2: manager.bondCounts[j]
                )
                guard canForm else { continue }
                
                guard elementLib.isValidBondDistance(distance, between: elementA, and: elementB) else { continue }
                
                let idealLength = elementLib.getIdealBondLength(between: elementA, and: elementB)
                
                // 创建化学键（带物理约束）
                manager.createBondWithPhysics(
                    nodeA: manager.atomNodes[i],
                    nodeB: manager.atomNodes[j],
                    idealLength: idealLength,
                    color: .lightGray,
                    scene: scene
                )
                
                manager.bondCounts[i] += 1
                manager.bondCounts[j] += 1
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
        physicsBody.friction = 0.5
        physicsBody.restitution = PhysicsConfig.restitution
        physicsBody.damping = PhysicsConfig.airFriction
        physicsBody.angularDamping = 0.5
        
        // 碰撞类别设置
        physicsBody.categoryBitMask = 1  // 原子类别
        physicsBody.collisionBitMask = 1 // 与其他原子碰撞
        physicsBody.contactTestBitMask = 1
        
        node.physicsBody = physicsBody
        
        return node
    }
    
    // MARK: - 创建带物理约束的化学键
    
    private func createBondWithPhysics(nodeA: SCNNode, nodeB: SCNNode, idealLength: Float, color: SceneColor, scene: SCNScene) {
        // 创建视觉圆柱体
        let cylinderNode = MoleculeScene.cylinderBetweenPoints(
            pointA: nodeA.position,
            pointB: nodeB.position,
            radius: 0.08,
            color: color
        )
        scene.rootNode.addChildNode(cylinderNode)
        
        // 创建物理约束（距离约束 + 弹簧效果）
        // 使用 SCNPhysicsSliderJoint 或自定义弹簧力
        
        // 方法1：使用物理弹簧场
        // 这里我们使用一个自定义的方法：在每帧更新中应用弹簧力
        
        let bond = ChemicalBond(
            atomNode1: nodeA,
            atomNode2: nodeB,
            idealLength: idealLength,
            cylinderNode: cylinderNode
        )
        bonds.append(bond)
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
            // 更新化学键的弹簧力
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
        
        // 找出每个原子连接的所有键
        var atomBonds: [SCNNode: [ChemicalBond]] = [:]
        for bond in bonds {
            atomBonds[bond.atomNode1, default: []].append(bond)
            atomBonds[bond.atomNode2, default: []].append(bond)
        }
        
        // 对每个有多个键的原子应用键角约束
        for (centerNode, connectedBonds) in atomBonds {
            guard connectedBonds.count >= 2 else { continue }
            
            let centerElement = extractElement(from: centerNode)
            let idealAngle = elementLib.getIdealBondAngle(centerElement: centerElement, bondCount: connectedBonds.count)
            
            // 获取连接的邻居原子
            var neighbors: [SCNNode] = []
            for bond in connectedBonds {
                let neighbor = bond.atomNode1 === centerNode ? bond.atomNode2 : bond.atomNode1
                neighbors.append(neighbor)
            }
            
            // 对每对邻居应用角度约束
            for i in 0..<neighbors.count {
                for j in (i+1)..<neighbors.count {
                    applyAngleForce(
                        centerNode: centerNode,
                        neighbor1: neighbors[i],
                        neighbor2: neighbors[j],
                        idealAngle: idealAngle
                    )
                }
            }
        }
    }
    
    /// 计算并应用键角力（带平面稳定性）
    private func applyAngleForce(centerNode: SCNNode, neighbor1: SCNNode, neighbor2: SCNNode, idealAngle: Float) {
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
        
        // 计算当前角度（点积）
        let dotProduct = n1.x*n2.x + n1.y*n2.y + n1.z*n2.z
        let clampedDot = max(-1.0, min(1.0, dotProduct))
        let currentAngle = acos(clampedDot)
        
        // 计算当前平面的法向量（叉积）
        var currentNormal = SCNVector3(
            n1.y * n2.z - n1.z * n2.y,
            n1.z * n2.x - n1.x * n2.z,
            n1.x * n2.y - n1.y * n2.x
        )
        let normalLen = sqrt(currentNormal.x*currentNormal.x + currentNormal.y*currentNormal.y + currentNormal.z*currentNormal.z)
        
        guard normalLen > 0.001 else { return }
        
        currentNormal = SCNVector3(currentNormal.x/normalLen, currentNormal.y/normalLen, currentNormal.z/normalLen)
        
        // 获取或创建平面记忆
        let nodeId = ObjectIdentifier(centerNode)
        var memory = anglePlaneMemories[nodeId]
        
        if memory == nil {
            // 首次建立平面记忆
            memory = AnglePlaneMemory(centerNode: centerNode, planeNormal: currentNormal, isEstablished: false)
        }
        
        // 检查是否需要建立稳定平面（角度接近理想值时锁定）
        let angleDiff = currentAngle - idealAngle
        if !memory!.isEstablished && abs(angleDiff) < 0.1 {  // 约 5.7 度内锁定
            memory!.planeNormal = currentNormal
            memory!.isEstablished = true
        }
        
        // 使用记忆的平面法向量（如果已建立）
        var nNormal = memory!.isEstablished ? memory!.planeNormal : currentNormal
        
        // 检查当前法向量是否翻转了（点积为负说明在平面另一侧）
        var needsPlaneRestoration = false
        if memory!.isEstablished {
            let dotWithMemory = currentNormal.x * memory!.planeNormal.x +
                               currentNormal.y * memory!.planeNormal.y +
                               currentNormal.z * memory!.planeNormal.z
            
            if dotWithMemory < 0 {
                // 原子试图穿过平面，施加强烈的恢复力
                needsPlaneRestoration = true
                applyPlaneRestorationForce(
                    centerNode: centerNode,
                    neighbor1: neighbor1,
                    neighbor2: neighbor2,
                    body1: body1,
                    body2: body2,
                    centerBody: centerBody,
                    memoryNormal: memory!.planeNormal,
                    currentNormal: currentNormal,
                    len1: len1,
                    len2: len2,
                    n1: n1,
                    n2: n2
                )
                // 使用记忆的法向量来计算角度力（不是当前翻转的法向量）
                nNormal = memory!.planeNormal
            } else {
                // 缓慢更新记忆（允许整体旋转但保持稳定）
                let blendFactor: Float = 0.01
                memory!.planeNormal = SCNVector3(
                    memory!.planeNormal.x * (1 - blendFactor) + currentNormal.x * blendFactor,
                    memory!.planeNormal.y * (1 - blendFactor) + currentNormal.y * blendFactor,
                    memory!.planeNormal.z * (1 - blendFactor) + currentNormal.z * blendFactor
                )
                // 重新归一化
                let memLen = sqrt(memory!.planeNormal.x*memory!.planeNormal.x +
                                 memory!.planeNormal.y*memory!.planeNormal.y +
                                 memory!.planeNormal.z*memory!.planeNormal.z)
                if memLen > 0.001 {
                    memory!.planeNormal = SCNVector3(
                        memory!.planeNormal.x/memLen,
                        memory!.planeNormal.y/memLen,
                        memory!.planeNormal.z/memLen
                    )
                }
            }
        }
        
        // 保存记忆
        anglePlaneMemories[nodeId] = memory
        
        // 始终施加角度约束力（恢复时使用更强的力）
        let angleStrengthMultiplier: Float = needsPlaneRestoration ? 2.0 : 1.0
        
        // 如果角度接近正确且不需要恢复，不施加角度力
        if abs(angleDiff) <= 0.02 && !needsPlaneRestoration { return }  // 约 1 度容差
        
        // 力的大小（扭矩转换为切向力），恢复时加强
        let torqueMag = PhysicsConfig.angleStiffness * angleDiff * angleStrengthMultiplier
        
        // 对 neighbor1：力垂直于 v1 且在角度平面内
        let tan1 = SCNVector3(
            nNormal.y * n1.z - nNormal.z * n1.y,
            nNormal.z * n1.x - nNormal.x * n1.z,
            nNormal.x * n1.y - nNormal.y * n1.x
        )
        
        // 对 neighbor2：力垂直于 v2 且在角度平面内
        let tan2 = SCNVector3(
            nNormal.y * n2.z - nNormal.z * n2.y,
            nNormal.z * n2.x - nNormal.x * n2.z,
            nNormal.x * n2.y - nNormal.y * n2.x
        )
        
        // 根据角度是太大还是太小决定力的方向
        let sign: Float = angleDiff > 0 ? -1.0 : 1.0
        
        // 应用力（F = τ / r）
        let forceMag1 = sign * torqueMag / len1
        let forceMag2 = -sign * torqueMag / len2
        
        let force1 = SCNVector3(tan1.x * forceMag1, tan1.y * forceMag1, tan1.z * forceMag1)
        let force2 = SCNVector3(tan2.x * forceMag2, tan2.y * forceMag2, tan2.z * forceMag2)
        
        // 中心原子受到反作用力
        let forceCenter = SCNVector3(
            -(force1.x + force2.x),
            -(force1.y + force2.y),
            -(force1.z + force2.z)
        )
        
        body1.applyForce(force1, asImpulse: false)
        body2.applyForce(force2, asImpulse: false)
        centerBody.applyForce(forceCenter, asImpulse: false)
        
        // 添加角度阻尼（减少振荡）
        let vel1 = body1.velocity
        let vel2 = body2.velocity
        
        // 沿切向的速度分量
        let tangentVel1 = vel1.x*tan1.x + vel1.y*tan1.y + vel1.z*tan1.z
        let tangentVel2 = vel2.x*tan2.x + vel2.y*tan2.y + vel2.z*tan2.z
        
        let damp1 = SCNVector3(
            -tan1.x * tangentVel1 * PhysicsConfig.angleDamping,
            -tan1.y * tangentVel1 * PhysicsConfig.angleDamping,
            -tan1.z * tangentVel1 * PhysicsConfig.angleDamping
        )
        let damp2 = SCNVector3(
            -tan2.x * tangentVel2 * PhysicsConfig.angleDamping,
            -tan2.y * tangentVel2 * PhysicsConfig.angleDamping,
            -tan2.z * tangentVel2 * PhysicsConfig.angleDamping
        )
        
        body1.applyForce(damp1, asImpulse: false)
        body2.applyForce(damp2, asImpulse: false)
    }
    
    /// 当原子试图穿过键角平面时，施加恢复力
    private func applyPlaneRestorationForce(
        centerNode: SCNNode,
        neighbor1: SCNNode,
        neighbor2: SCNNode,
        body1: SCNPhysicsBody,
        body2: SCNPhysicsBody,
        centerBody: SCNPhysicsBody,
        memoryNormal: SCNVector3,
        currentNormal: SCNVector3,
        len1: Float,
        len2: Float,
        n1: SCNVector3,
        n2: SCNVector3
    ) {
        // 计算每个邻居原子相对于平面的位置
        // 使用记忆的法向量作为参考
        
        // 对于每个邻居，计算其在法向量方向上的分量
        // 如果在错误的一侧，推回去
        
        let restorationStrength: Float = PhysicsConfig.angleStiffness * 2.0
        
        // neighbor1 在法向量方向的分量
        let proj1 = n1.x * memoryNormal.x + n1.y * memoryNormal.y + n1.z * memoryNormal.z
        // neighbor2 在法向量方向的分量
        let proj2 = n2.x * memoryNormal.x + n2.y * memoryNormal.y + n2.z * memoryNormal.z
        
        // 如果两个原子在平面的同一侧（符号相同），一切正常
        // 如果在不同侧，或者整体翻转了，需要恢复
        
        // 施加力把原子推回平面的正确一侧
        // 力沿法向量方向，强度与偏离程度成正比
        
        let force1Normal = SCNVector3(
            -memoryNormal.x * proj1 * restorationStrength,
            -memoryNormal.y * proj1 * restorationStrength,
            -memoryNormal.z * proj1 * restorationStrength
        )
        
        let force2Normal = SCNVector3(
            -memoryNormal.x * proj2 * restorationStrength,
            -memoryNormal.y * proj2 * restorationStrength,
            -memoryNormal.z * proj2 * restorationStrength
        )
        
        body1.applyForce(force1Normal, asImpulse: false)
        body2.applyForce(force2Normal, asImpulse: false)
        
        // 强阻尼：减少法向量方向的速度
        let vel1 = body1.velocity
        let vel2 = body2.velocity
        
        let normalVel1 = vel1.x * memoryNormal.x + vel1.y * memoryNormal.y + vel1.z * memoryNormal.z
        let normalVel2 = vel2.x * memoryNormal.x + vel2.y * memoryNormal.y + vel2.z * memoryNormal.z
        
        let strongDamping: Float = PhysicsConfig.angleDamping * 3.0
        
        let damp1 = SCNVector3(
            -memoryNormal.x * normalVel1 * strongDamping,
            -memoryNormal.y * normalVel1 * strongDamping,
            -memoryNormal.z * normalVel1 * strongDamping
        )
        let damp2 = SCNVector3(
            -memoryNormal.x * normalVel2 * strongDamping,
            -memoryNormal.y * normalVel2 * strongDamping,
            -memoryNormal.z * normalVel2 * strongDamping
        )
        
        body1.applyForce(damp1, asImpulse: false)
        body2.applyForce(damp2, asImpulse: false)
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
                
                let idealLength = elementLib.getIdealBondLength(between: elementA, and: elementB)
                let maxBondDist = idealLength * 1.3  // 最大成键距离
                let minSafeDist = idealLength * 0.6  // 最小安全距离
                
                if hasBond {
                    // 已有键，只需检查是否需要断键（距离过远）
                    if dist > idealLength * 2.0 {
                        // 距离太远，断开化学键
                        removeBondInternal(between: nodeA, and: nodeB)
                    }
                    continue
                }
                
                // 检查两个原子是否都还能成键
                let canForm = elementLib.canFormBond(
                    between: elementA,
                    and: elementB,
                    currentBonds1: bondCounts[i],
                    currentBonds2: bondCounts[j]
                )
                
                if canForm && dist < maxBondDist && dist > minSafeDist {
                    // 在成键范围内，创建新键
                    createBondDynamic(nodeA: nodeA, nodeB: nodeB, indexA: i, indexB: j, idealLength: idealLength)
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
    
    private func createBondDynamic(nodeA: SCNNode, nodeB: SCNNode, indexA: Int, indexB: Int, idealLength: Float) {
        guard let scene = scene else { return }
        
        // 创建化学键
        createBondWithPhysics(
            nodeA: nodeA,
            nodeB: nodeB,
            idealLength: idealLength,
            color: .lightGray,
            scene: scene
        )
        
        // 更新成键计数
        if indexA < bondCounts.count {
            bondCounts[indexA] += 1
        }
        if indexB < bondCounts.count {
            bondCounts[indexB] += 1
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
                bond.cylinderNode.removeFromParentNode()
                // 更新成键计数
                if let ia = indexA, ia < bondCounts.count {
                    bondCounts[ia] = max(0, bondCounts[ia] - 1)
                }
                if let ib = indexB, ib < bondCounts.count {
                    bondCounts[ib] = max(0, bondCounts[ib] - 1)
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
        
        // 弹簧力 F = -k * (x - x0)
        let displacement = currentLength - bond.idealLength
        let forceMagnitude = Float(PhysicsConfig.bondStiffness) * displacement
        
        // 方向向量（归一化）
        let nx = dx / currentLength
        let ny = dy / currentLength
        let nz = dz / currentLength
        
        // 应用力（牛顿第三定律）
        let forceA = SCNVector3(nx * forceMagnitude, ny * forceMagnitude, nz * forceMagnitude)
        let forceB = SCNVector3(-nx * forceMagnitude, -ny * forceMagnitude, -nz * forceMagnitude)
        
        bodyA.applyForce(forceA, asImpulse: false)
        bodyB.applyForce(forceB, asImpulse: false)
        
        // 阻尼力（速度方向的阻力）
        let velA = bodyA.velocity
        let velB = bodyB.velocity
        
        let relVelX = velB.x - velA.x
        let relVelY = velB.y - velA.y
        let relVelZ = velB.z - velA.z
        
        // 沿连接方向的相对速度
        let relVelAlongBond = relVelX * nx + relVelY * ny + relVelZ * nz
        let dampingForce = Float(PhysicsConfig.bondDamping) * relVelAlongBond
        
        let dampA = SCNVector3(nx * dampingForce, ny * dampingForce, nz * dampingForce)
        let dampB = SCNVector3(-nx * dampingForce, -ny * dampingForce, -nz * dampingForce)
        
        bodyA.applyForce(dampA, asImpulse: false)
        bodyB.applyForce(dampB, asImpulse: false)
    }
    
    private func updateBondVisual(bond: ChemicalBond) {
        // 更新圆柱体位置和方向
        let posA = bond.atomNode1.presentation.position
        let posB = bond.atomNode2.presentation.position
        
        // 中点
        bond.cylinderNode.position = SCNVector3(
            (posA.x + posB.x) / 2,
            (posA.y + posB.y) / 2,
            (posA.z + posB.z) / 2
        )
        
        // 更新长度
        let dx = posB.x - posA.x
        let dy = posB.y - posA.y
        let dz = posB.z - posA.z
        let length = sqrt(dx*dx + dy*dy + dz*dz)
        
        if let cylinder = bond.cylinderNode.geometry as? SCNCylinder {
            cylinder.height = CGFloat(length)
        }
        
        // 更新方向
        let direction = SCNVector3(dx, dy, dz)
        let from = SCNVector3(0, 1, 0)
        let to = normalize(direction)
        let axis = cross(from, to)
        let dotv = dot(from, to)
        let angle = acos(max(min(dotv, 1), -1))
        
        if sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z) < 1e-6 {
            if dotv < 0 {
                bond.cylinderNode.rotation = SCNVector4(1, 0, 0, Float.pi)
            }
        } else {
            let axisN = normalize(axis)
            bond.cylinderNode.rotation = SCNVector4(axisN.x, axisN.y, axisN.z, angle)
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
                bond.cylinderNode.removeFromParentNode()
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
