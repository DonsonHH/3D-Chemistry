//
//  ContentView.swift
//  3D-Chemistry
//
//  Created by ypx on 2025/11/12.
//

import SwiftUI
import SceneKit
import AVFoundation
import AudioToolbox

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @State private var atoms: [Atom] = []
    @State private var manualBonds: [ManualBond] = []  // 手动键
    @State private var selectedHole: (atomIndex: Int, holeIndex: Int)?  // 当前选中的孔
    @State private var isAtomSelectorVisible = false
    @State private var selectedAtomIndex: Int?
    @State private var selectedAtomPosition: SCNVector3 = SCNVector3Zero
    @State private var physicsEnabled = true  // 物理引擎开关
    
    // 预选原子暂存区
    @State private var stagedAtoms: [String] = []  // 暂存的元素符号列表
    
    private let soundPlayer = SoundPlayer()

    var body: some View {
        ZStack {
            Color.black.opacity(0.98)
                .ignoresSafeArea()
            
            // SceneKit 主视图（使用物理引擎版本）
            PhysicsSceneKitView(
                atoms: atoms,
                manualBonds: manualBonds,
                selectedHole: selectedHole,
                physicsEnabled: physicsEnabled,
                onAtomLongPress: { index, _, position in
                    handleAtomLongPress(index: index, position3D: position)
                },
                onHoleTap: { atomIndex, holeIndex in
                    handleHoleTap(atomIndex: atomIndex, holeIndex: holeIndex)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 背景遮罩层（点击关闭面板）
            if isAtomSelectorVisible || selectedAtomIndex != nil {
                Color.black.opacity(0.001) // 几乎透明但可点击
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isAtomSelectorVisible = false
                            selectedAtomIndex = nil
                        }
                    }
            }
            
            // 原子信息面板
            if let index = selectedAtomIndex, index < atoms.count {
                AtomInfoPanel(
                    atom: atoms[index],
                    atomPosition3D: selectedAtomPosition,
                    onDelete: {
                        deleteAtom(at: index)
                    },
                    onDismiss: {
                        selectedAtomIndex = nil
                    }
                )
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .allowsHitTesting(true) // 确保面板可以接收点击
            }
            
            // 原子选择面板（带预选功能）
            if isAtomSelectorVisible {
                AtomSelectorPanel(
                    stagedAtoms: $stagedAtoms,
                    onSelect: { element in
                        addToStaging(element: element)
                    },
                    onRemoveStaged: { index in
                        removeFromStaging(at: index)
                    },
                    onClearStaged: {
                        clearStaging()
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.3, anchor: .bottomTrailing)
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.3, anchor: .bottomTrailing)
                            .combined(with: .opacity)
                    )
                )
                .allowsHitTesting(true) // 确保面板可以接收点击
            }
            
            // 左右按钮悬浮层
            HStack {
                // 左侧三角形按钮（物理引擎开关）
                Button {
                    handleLeftButton()
                } label: {
                    ZStack {
                        if physicsEnabled {
                            // 物理引擎开启状态：显示波浪线（表示运动）
                            PhysicsWaveShape()
                                .stroke(Color.green, lineWidth: 2.5)
                                .frame(width: 48, height: 48)
                        } else {
                            // 物理引擎关闭状态：显示静止符号
                            TriangleStrokeShape()
                                .stroke(Color.white.opacity(0.5), lineWidth: 2.5)
                                .frame(width: 48, height: 48)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 32)
                
                Spacer()
                
                // 右侧按钮
                VStack(spacing: 8) {
                    Button {
                        handleRightButton()
                    } label: {
                        ZStack {
                            if isAtomSelectorVisible {
                                if stagedAtoms.isEmpty {
                                    // 没有预选原子时显示X
                                    PolylineShape()
                                        .stroke(Color.white, lineWidth: 2.5)
                                        .frame(width: 48, height: 48)
                                } else {
                                    // 有预选原子时显示勾号（表示确认组装）
                                    CheckmarkShape()
                                        .stroke(Color.cyan, lineWidth: 3)
                                        .frame(width: 48, height: 48)
                                }
                            } else {
                                ConcentricCirclesShape()
                                    .stroke(Color.white, lineWidth: 2.5)
                                    .frame(width: 48, height: 48)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // 预选原子数量提示
                    if isAtomSelectorVisible && !stagedAtoms.isEmpty {
                        Text("组装")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.trailing, 32)
            }
            .padding(.bottom, 40)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0), value: isAtomSelectorVisible)
    }
    
    private func handleLeftButton() {
        // 切换物理引擎开关
        soundPlayer.playKnobSound()
        withAnimation {
            physicsEnabled.toggle()
        }
        print("物理引擎: \(physicsEnabled ? "开启" : "关闭")")
    }
    
    private func handleRightButton() {
        // 播放旋钮音效
        soundPlayer.playKnobSound()
        
        if isAtomSelectorVisible {
            // 关闭面板时，将预选原子组装成分子
            assembleMoleculeFromStaged()
        }
        
        withAnimation {
            isAtomSelectorVisible.toggle()
        }
    }
    
    // MARK: - 预选原子管理
    
    private func addToStaging(element: String) {
        soundPlayer.playKnobSound()
        stagedAtoms.append(element)
    }
    
    private func removeFromStaging(at index: Int) {
        guard index < stagedAtoms.count else { return }
        soundPlayer.playKnobSound()
        stagedAtoms.remove(at: index)
    }
    
    private func clearStaging() {
        soundPlayer.playKnobSound()
        stagedAtoms.removeAll()
    }
    
    // MARK: - 分子组装
    
    /// 预测分子的几何类型
    private enum PredictedGeometry {
        case linear              // 线性（如 CO₂, HCN）
        case bent                // 弯曲（如 H₂O, H₂S）
        case trigonalPlanar      // 平面三角形（如 BH₃, CH₂O）
        case pyramidal           // 三角锥（如 NH₃）
        case tetrahedral         // 四面体（如 CH₄）
        case diatomic            // 双原子分子（如 H₂, O₂, CO）
        case undefined           // 无法预测
    }
    
    /// 根据原子组成预测分子几何
    private func predictMolecularGeometry(elements: [String]) -> PredictedGeometry {
        let library = ElementLibrary.shared
        
        // 统计各元素数量
        var elementCounts: [String: Int] = [:]
        for element in elements {
            elementCounts[element.lowercased(), default: 0] += 1
        }
        
        let totalAtoms = elements.count
        
        // 特殊分子检测
        // H₂O: 1个O + 2个H
        if elementCounts["o"] == 1 && elementCounts["h"] == 2 && totalAtoms == 3 {
            return .bent
        }
        
        // H₂S: 1个S + 2个H
        if elementCounts["s"] == 1 && elementCounts["h"] == 2 && totalAtoms == 3 {
            return .bent
        }
        
        // CO₂: 1个C + 2个O
        if elementCounts["c"] == 1 && elementCounts["o"] == 2 && totalAtoms == 3 {
            return .linear
        }
        
        // NH₃: 1个N + 3个H
        if elementCounts["n"] == 1 && elementCounts["h"] == 3 && totalAtoms == 4 {
            return .pyramidal
        }
        
        // CH₄: 1个C + 4个H
        if elementCounts["c"] == 1 && elementCounts["h"] == 4 && totalAtoms == 5 {
            return .tetrahedral
        }
        
        // BH₃: 1个B + 3个H
        if elementCounts["b"] == 1 && elementCounts["h"] == 3 && totalAtoms == 4 {
            return .trigonalPlanar
        }
        
        // HCN: 1个H + 1个C + 1个N
        if elementCounts["h"] == 1 && elementCounts["c"] == 1 && elementCounts["n"] == 1 && totalAtoms == 3 {
            return .linear
        }
        
        // 双原子分子
        if totalAtoms == 2 {
            return .diatomic
        }
        
        // 找到成键能力最高的原子作为中心
        var maxBondAtom = elements[0]
        var maxBonds = library.getMaxBonds(for: maxBondAtom)
        for element in elements {
            let bonds = library.getMaxBonds(for: element)
            if bonds > maxBonds {
                maxBonds = bonds
                maxBondAtom = element
            }
        }
        
        // 根据中心原子的成键能力和邻居数量推断
        let centerCount = elementCounts[maxBondAtom.lowercased()] ?? 0
        let neighborCount = totalAtoms - centerCount
        
        if neighborCount == 2 {
            // 可能是线性或弯曲
            let centerElement = maxBondAtom.lowercased()
            if centerElement == "o" || centerElement == "s" {
                return .bent
            }
            return .linear
        } else if neighborCount == 3 {
            let centerElement = maxBondAtom.lowercased()
            if centerElement == "n" || centerElement == "p" {
                return .pyramidal
            }
            return .trigonalPlanar
        } else if neighborCount == 4 {
            return .tetrahedral
        }
        
        return .undefined
    }
    
    /// 计算原子间应该形成的键级
    private func predictBondOrder(element1: String, element2: String, 
                                   remainingValence1: Int, remainingValence2: Int) -> Int {
        let minValence = min(remainingValence1, remainingValence2)
        
        // 特殊双键/三键组合
        let e1 = element1.lowercased()
        let e2 = element2.lowercased()
        
        // C=O 双键（在有机分子中）
        if (e1 == "c" && e2 == "o") || (e1 == "o" && e2 == "c") {
            if minValence >= 2 {
                return 2
            }
        }
        
        // C=C 双键
        if e1 == "c" && e2 == "c" && minValence >= 2 {
            return 2
        }
        
        // C≡N 三键
        if (e1 == "c" && e2 == "n") || (e1 == "n" && e2 == "c") {
            if minValence >= 3 {
                return 3
            }
        }
        
        // N≡N 三键
        if e1 == "n" && e2 == "n" && minValence >= 3 {
            return 3
        }
        
        // O=O 双键
        if e1 == "o" && e2 == "o" && minValence >= 2 {
            return 2
        }
        
        // 默认单键
        return 1
    }
    
    /// 将预选的原子组装成分子
    private func assembleMoleculeFromStaged() {
        guard !stagedAtoms.isEmpty else { return }
        
        let library = ElementLibrary.shared
        
        // 预测分子几何
        let geometry = predictMolecularGeometry(elements: stagedAtoms)
        
        // 计算各元素的成键能力
        var atomsWithBondCapacity: [(element: String, maxBonds: Int, index: Int)] = []
        for (index, element) in stagedAtoms.enumerated() {
            let maxBonds = library.getMaxBonds(for: element)
            atomsWithBondCapacity.append((element, maxBonds, index))
        }
        
        // 按成键能力降序排序（中心原子优先）
        atomsWithBondCapacity.sort { $0.maxBonds > $1.maxBonds }
        
        // 分离中心原子和端基原子
        let centerAtoms = atomsWithBondCapacity.filter { $0.maxBonds >= 2 }
        let terminalAtoms = atomsWithBondCapacity.filter { $0.maxBonds == 1 }
        let nobleGases = atomsWithBondCapacity.filter { $0.maxBonds == 0 }
        
        var newAtoms: [Atom] = []
        let baseX: Float = Float(atoms.count) * 0.5  // 偏移避免与现有原子重叠
        let baseSpacing: Float = 1.0  // 基础原子间距
        
        // 根据几何类型布局
        switch geometry {
        case .diatomic:
            // 双原子分子：水平排列，考虑键级
            let e1 = atomsWithBondCapacity[0].element
            let e2 = atomsWithBondCapacity[1].element
            let v1 = library.getMaxBonds(for: e1)
            let v2 = library.getMaxBonds(for: e2)
            let bondOrder = predictBondOrder(element1: e1, element2: e2, remainingValence1: v1, remainingValence2: v2)
            
            // 键级越高，距离越短
            let bondFactor: Float = bondOrder == 3 ? 0.78 : (bondOrder == 2 ? 0.86 : 1.0)
            let spacing = baseSpacing * bondFactor
            
            newAtoms.append(Atom(
                element: e1,
                position: SCNVector3(baseX, 0, 0),
                radius: library.getVisualRadius(for: e1)
            ))
            newAtoms.append(Atom(
                element: e2,
                position: SCNVector3(baseX + spacing, 0, 0),
                radius: library.getVisualRadius(for: e2)
            ))
            
        case .linear:
            // 线性分子（如 CO₂）：中心原子在中间，两个原子在两侧
            if let center = centerAtoms.first {
                let centerElement = center.element
                let centerPos = SCNVector3(baseX, 0, 0)
                
                // 计算与端基的键级
                var terminals = terminalAtoms.isEmpty ? 
                    centerAtoms.dropFirst().map { ($0.element, $0.maxBonds) } :
                    terminalAtoms.map { ($0.element, $0.maxBonds) }
                
                // 如果没有端基但有多个中心原子（如 CO₂ 中的 O）
                if terminals.isEmpty && centerAtoms.count > 1 {
                    terminals = centerAtoms.dropFirst().map { ($0.element, $0.maxBonds) }
                }
                
                newAtoms.append(Atom(
                    element: centerElement,
                    position: centerPos,
                    radius: library.getVisualRadius(for: centerElement)
                ))
                
                // 两侧放置原子
                for (i, terminal) in terminals.prefix(2).enumerated() {
                    let bondOrder = predictBondOrder(
                        element1: centerElement,
                        element2: terminal.0,
                        remainingValence1: center.maxBonds,
                        remainingValence2: terminal.1
                    )
                    let bondFactor: Float = bondOrder == 3 ? 0.78 : (bondOrder == 2 ? 0.86 : 1.0)
                    let spacing = baseSpacing * bondFactor
                    let direction: Float = i == 0 ? -1.0 : 1.0
                    
                    newAtoms.append(Atom(
                        element: terminal.0,
                        position: SCNVector3(centerPos.x + direction * spacing, 0, 0),
                        radius: library.getVisualRadius(for: terminal.0)
                    ))
                }
            }
            
        case .bent:
            // 弯曲分子（如 H₂O）：中心原子在中间，两个氢以 104.5° 角度排列
            // 在 XZ 平面布局，面向用户（Y轴朝向用户）
            if let center = centerAtoms.first {
                let centerElement = center.element
                let centerPos = SCNVector3(baseX, 0, 0)
                
                newAtoms.append(Atom(
                    element: centerElement,
                    position: centerPos,
                    radius: library.getVisualRadius(for: centerElement)
                ))
                
                // 104.5° 键角
                let bondAngle: Float = 104.5 * .pi / 180.0
                let halfAngle = bondAngle / 2.0
                let bondLength: Float = baseSpacing * 0.95  // 稍短的键长
                
                // 两个氢原子位置（在 XZ 平面，面向用户）
                let h1Pos = SCNVector3(
                    centerPos.x + bondLength * sin(halfAngle),
                    centerPos.y,
                    centerPos.z - bondLength * cos(halfAngle)
                )
                let h2Pos = SCNVector3(
                    centerPos.x - bondLength * sin(halfAngle),
                    centerPos.y,
                    centerPos.z - bondLength * cos(halfAngle)
                )
                
                for (i, terminal) in terminalAtoms.prefix(2).enumerated() {
                    let pos = i == 0 ? h1Pos : h2Pos
                    newAtoms.append(Atom(
                        element: terminal.element,
                        position: pos,
                        radius: library.getVisualRadius(for: terminal.element)
                    ))
                }
            }
            
        case .trigonalPlanar:
            // 平面三角形（如 BH₃）：中心原子在中间，三个原子以 120° 角度排列
            // 在 XZ 平面布局，面向用户
            if let center = centerAtoms.first {
                let centerElement = center.element
                let centerPos = SCNVector3(baseX, 0, 0)
                
                newAtoms.append(Atom(
                    element: centerElement,
                    position: centerPos,
                    radius: library.getVisualRadius(for: centerElement)
                ))
                
                let bondLength: Float = baseSpacing
                for i in 0..<min(3, terminalAtoms.count) {
                    let angle = Float(i) * 2.0 * .pi / 3.0 + .pi / 2.0  // 从上方开始
                    let pos = SCNVector3(
                        centerPos.x + bondLength * sin(angle),
                        centerPos.y,
                        centerPos.z - bondLength * cos(angle)
                    )
                    newAtoms.append(Atom(
                        element: terminalAtoms[i].element,
                        position: pos,
                        radius: library.getVisualRadius(for: terminalAtoms[i].element)
                    ))
                }
            }
            
        case .pyramidal:
            // 三角锥形（如 NH₃）：中心原子在上方，三个原子在下方
            // 在 XZ 平面布局，面向用户
            if let center = centerAtoms.first {
                let centerElement = center.element
                let centerPos = SCNVector3(baseX, 0, 0)
                
                newAtoms.append(Atom(
                    element: centerElement,
                    position: centerPos,
                    radius: library.getVisualRadius(for: centerElement)
                ))
                
                let bondLength: Float = baseSpacing * 0.95
                // NH₃ 键角约 107°，三个氢在下方形成三角形
                let heightOffset: Float = bondLength * 0.3  // 氢原子在 N 下方
                let projectedLength: Float = bondLength * 0.9  // 投影到 XZ 平面的长度
                
                for i in 0..<min(3, terminalAtoms.count) {
                    let angle = Float(i) * 2.0 * .pi / 3.0 + .pi / 6.0  // 30°偏移
                    let pos = SCNVector3(
                        centerPos.x + projectedLength * sin(angle),
                        centerPos.y - heightOffset,
                        centerPos.z - projectedLength * cos(angle)
                    )
                    newAtoms.append(Atom(
                        element: terminalAtoms[i].element,
                        position: pos,
                        radius: library.getVisualRadius(for: terminalAtoms[i].element)
                    ))
                }
            }
            
        case .tetrahedral:
            // 四面体（如 CH₄）
            // 面向用户的四面体布局
            if let center = centerAtoms.first {
                let centerElement = center.element
                let centerPos = SCNVector3(baseX, 0, 0)
                
                newAtoms.append(Atom(
                    element: centerElement,
                    position: centerPos,
                    radius: library.getVisualRadius(for: centerElement)
                ))
                
                // 四面体顶点位置（正四面体）
                let bondLength: Float = baseSpacing
                
                // 四面体的四个顶点，使一个顶点朝上
                // 使用标准四面体坐标
                let a: Float = bondLength / sqrt(3.0)  // 四面体边长相关参数
                let h: Float = bondLength * sqrt(2.0/3.0)  // 高度
                
                let positions: [SCNVector3] = [
                    SCNVector3(centerPos.x, centerPos.y + bondLength * 0.8, centerPos.z),  // 上
                    SCNVector3(centerPos.x + a, centerPos.y - bondLength * 0.3, centerPos.z - a * 0.5),  // 右前
                    SCNVector3(centerPos.x - a, centerPos.y - bondLength * 0.3, centerPos.z - a * 0.5),  // 左前
                    SCNVector3(centerPos.x, centerPos.y - bondLength * 0.3, centerPos.z + a)   // 后
                ]
                
                for i in 0..<min(4, terminalAtoms.count) {
                    newAtoms.append(Atom(
                        element: terminalAtoms[i].element,
                        position: positions[i],
                        radius: library.getVisualRadius(for: terminalAtoms[i].element)
                    ))
                }
            }
            
        case .undefined:
            // 未知几何，使用默认布局
            fallthrough
        default:
            // 默认布局：中心原子在中间，端基原子围绕
            var usedPositions: [SCNVector3] = []
            var remainingTerminals = terminalAtoms
            
            // 放置中心原子
            for (i, centerAtom) in centerAtoms.enumerated() {
                let position = SCNVector3(baseX + Float(i) * baseSpacing, 0, 0)
                newAtoms.append(Atom(
                    element: centerAtom.element,
                    position: position,
                    radius: library.getVisualRadius(for: centerAtom.element)
                ))
                usedPositions.append(position)
            }
            
            // 计算剩余成键位置
            var skeletonBondCounts = Array(repeating: 0, count: centerAtoms.count)
            for i in 0..<max(0, centerAtoms.count - 1) {
                skeletonBondCounts[i] += 1
                skeletonBondCounts[i + 1] += 1
            }
            
            // 分配端基原子
            var terminalIndex = 0
            for (skeletonIdx, skeletonAtom) in centerAtoms.enumerated() {
                let remainingBonds = skeletonAtom.maxBonds - skeletonBondCounts[skeletonIdx]
                let skeletonPos = usedPositions[skeletonIdx]
                
                for bondSlot in 0..<remainingBonds {
                    guard terminalIndex < remainingTerminals.count else { break }
                    
                    let terminal = remainingTerminals[terminalIndex]
                    let angle = Float(bondSlot + 1) * .pi / Float(remainingBonds + 1)
                    
                    let terminalPos = SCNVector3(
                        skeletonPos.x,
                        skeletonPos.y + sin(angle) * baseSpacing * 0.8,
                        skeletonPos.z + cos(angle) * baseSpacing * 0.5
                    )
                    
                    newAtoms.append(Atom(
                        element: terminal.element,
                        position: terminalPos,
                        radius: library.getVisualRadius(for: terminal.element)
                    ))
                    terminalIndex += 1
                }
            }
            
            // 剩余端基原子
            while terminalIndex < remainingTerminals.count {
                let terminal = remainingTerminals[terminalIndex]
                let position = SCNVector3(
                    baseX + Float(centerAtoms.count + terminalIndex) * baseSpacing,
                    1.5, 0
                )
                newAtoms.append(Atom(
                    element: terminal.element,
                    position: position,
                    radius: library.getVisualRadius(for: terminal.element)
                ))
                terminalIndex += 1
            }
        }
        
        // 稀有气体放在旁边
        for (i, noble) in nobleGases.enumerated() {
            let position = SCNVector3(
                baseX + Float(newAtoms.count + i) * baseSpacing,
                2.0, 0
            )
            newAtoms.append(Atom(
                element: noble.element,
                position: position,
                radius: library.getVisualRadius(for: noble.element)
            ))
        }
        
        // 添加到场景
        atoms.append(contentsOf: newAtoms)
        
        // 清空暂存区
        stagedAtoms.removeAll()
    }
    
    private func handleAtomLongPress(index: Int, position3D: SCNVector3) {
        selectedAtomIndex = index
        selectedAtomPosition = position3D
        soundPlayer.playKnobSound()
    }
    
    private func deleteAtom(at index: Int) {
        guard index < atoms.count else { return }
        
        // 删除与该原子相关的所有手动键
        manualBonds.removeAll { bond in
            bond.atomIndex1 == index || bond.atomIndex2 == index
        }
        
        // 更新其他手动键的索引（索引大于被删除原子的需要减1）
        manualBonds = manualBonds.compactMap { bond in
            var newBond = bond
            if bond.atomIndex1 > index {
                newBond = ManualBond(
                    atomIndex1: bond.atomIndex1 - 1,
                    atomIndex2: bond.atomIndex2,
                    holeIndex1: bond.holeIndex1,
                    holeIndex2: bond.holeIndex2
                )
            }
            if bond.atomIndex2 > index {
                newBond = ManualBond(
                    atomIndex1: newBond.atomIndex1,
                    atomIndex2: bond.atomIndex2 - 1,
                    holeIndex1: newBond.holeIndex1,
                    holeIndex2: newBond.holeIndex2
                )
            }
            return newBond
        }
        
        atoms.remove(at: index)
        selectedAtomIndex = nil
        soundPlayer.playKnobSound()
    }
    
    private func handleHoleTap(atomIndex: Int, holeIndex: Int) {
        soundPlayer.playKnobSound()
        
        if let firstHole = selectedHole {
            // 已有选中的孔，现在选择第二个孔
            if firstHole.atomIndex != atomIndex {
                // 两个不同原子的孔，创建手动键
                let newBond = ManualBond(
                    atomIndex1: firstHole.atomIndex,
                    atomIndex2: atomIndex,
                    holeIndex1: firstHole.holeIndex,
                    holeIndex2: holeIndex
                )
                
                // 检查是否已存在相同的键
                let bondExists = manualBonds.contains { bond in
                    (bond.atomIndex1 == newBond.atomIndex1 && bond.atomIndex2 == newBond.atomIndex2) ||
                    (bond.atomIndex1 == newBond.atomIndex2 && bond.atomIndex2 == newBond.atomIndex1)
                }
                
                if !bondExists {
                    manualBonds.append(newBond)
                }
                
                selectedHole = nil
            } else {
                // 同一个原子，切换选择
                selectedHole = (atomIndex, holeIndex)
            }
        } else {
            // 第一次选择孔
            selectedHole = (atomIndex, holeIndex)
        }
    }
}

// MARK: - 原子信息面板

struct AtomInfoPanel: View {
    let atom: Atom
    let atomPosition3D: SCNVector3
    let onDelete: () -> Void
    let onDismiss: () -> Void
    
    private let library = ElementLibrary.shared
    
    var body: some View {
        GeometryReader { geometry in
            let panelContent = makePanelContent()
            let screenPos = calculateScreenPosition(for: atomPosition3D, in: geometry.size)
            
            panelContent
                .position(x: screenPos.x, y: screenPos.y)
        }
    }
    
    @ViewBuilder
    private func makePanelContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 关闭按钮
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            if let elementInfo = library.getElement(atom.element) {
                VStack(spacing: 12) {
                    // 原子球体
                    Circle()
                        .fill(Color(elementInfo.color))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: Color(elementInfo.color).opacity(0.5), radius: 8, x: 0, y: 4)
                    
                    // 元素信息
                    VStack(spacing: 6) {
                        Text(elementInfo.symbol)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(elementInfo.name)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.vertical, 4)
                        
                        InfoRow(label: "原子序数", value: "\(elementInfo.atomicNumber)")
                        InfoRow(label: "共价半径", value: String(format: "%.2f Å", elementInfo.covalentRadius))
                        InfoRow(label: "最大成键数", value: "\(elementInfo.maxBonds)")
                        InfoRow(label: "常见化合价", value: elementInfo.commonValences.map { "\($0)" }.joined(separator: ", "))
                        
                        // 预留空位
                        InfoRow(label: "电负性", value: "—")
                        InfoRow(label: "原子量", value: "—")
                    }
                    .padding(.horizontal, 16)
                    
                    // 删除按钮
                    Button(action: onDelete) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("删除原子")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        )
    }
    
    private func calculateScreenPosition(for position3D: SCNVector3, in viewSize: CGSize) -> CGPoint {
        // 简化的投影：将3D坐标映射到屏幕中心附近
        // 实际应用中应该使用相机的投影矩阵，这里使用近似计算
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2
        
        // 将原子位置投影到2D (简单透视投影)
        let scale: CGFloat = 200 // 缩放因子
        let x = centerX + CGFloat(position3D.x) * scale
        let y = centerY - CGFloat(position3D.y) * scale // Y轴反转
        
        // 确保面板在原子右侧显示，避免遮挡原子
        let offsetX: CGFloat = 150 // 面板宽度的一半 + 间距
        let panelX = x + offsetX
        
        // 边界检测，确保不超出屏幕
        let finalX = min(max(panelX, 130), viewSize.width - 130)
        let finalY = min(max(y, 200), viewSize.height - 200)
        
        return CGPoint(x: finalX, y: finalY)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 原子选择面板

struct AtomSelectorPanel: View {
    @Binding var stagedAtoms: [String]
    var onSelect: (String) -> Void
    var onRemoveStaged: (Int) -> Void
    var onClearStaged: () -> Void
    
    private let library = ElementLibrary.shared
    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 16)
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text("选择原子")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    
                    // 显示预选数量
                    if !stagedAtoms.isEmpty {
                        Text("\(stagedAtoms.count) 个原子待添加")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.08))
                
                // 预选原子展示区
                if !stagedAtoms.isEmpty {
                    StagedAtomsView(
                        stagedAtoms: stagedAtoms,
                        onRemove: onRemoveStaged,
                        onClear: onClearStaged
                    )
                }
                
                // 元素网格
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(getAllElements(), id: \.symbol) { element in
                            AtomButton(element: element) {
                                onSelect(element.symbol)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: 360)
            .background(Color.black.opacity(0.92))
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1),
                alignment: .leading
            )
        }
    }
    
    private func getAllElements() -> [ElementInfo] {
        let symbols = library.getAllElementSymbols()
        return symbols.compactMap { library.getElement($0) }
            .sorted { $0.atomicNumber < $1.atomicNumber }
    }
}

// MARK: - 预选原子展示区

struct StagedAtomsView: View {
    let stagedAtoms: [String]
    let onRemove: (Int) -> Void
    let onClear: () -> Void
    
    private let library = ElementLibrary.shared
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 12) {
            // 分子式预览
            HStack {
                Text("分子式：")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
                Text(molecularFormula)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .contentTransition(.numericText())
                
                Spacer()
                
                // 清空按钮
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        onClear()
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            // 预选原子球展示（可滑动）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(stagedAtoms.enumerated()), id: \.offset) { index, element in
                        StagedAtomBubble(
                            element: element,
                            index: index,
                            onRemove: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    onRemove(index)
                                }
                            }
                        )
                        .id("\(index)-\(element)")
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(y: 20)),
                                removal: .scale(scale: 0.3).combined(with: .opacity)
                            )
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .frame(height: 68)
            .padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cyan.opacity(0.08))
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
    
    /// 生成分子式（如 H2O, CO2 等）
    private var molecularFormula: String {
        var counts: [String: Int] = [:]
        for element in stagedAtoms {
            counts[element, default: 0] += 1
        }
        
        // 按照常见顺序排序：C, H, 其他按字母
        let order = ["C", "H", "O", "N", "S", "P", "F", "Cl", "Br", "I"]
        let sortedElements = counts.keys.sorted { e1, e2 in
            let i1 = order.firstIndex(of: e1) ?? 100
            let i2 = order.firstIndex(of: e2) ?? 100
            if i1 != i2 { return i1 < i2 }
            return e1 < e2
        }
        
        var formula = ""
        for element in sortedElements {
            let count = counts[element]!
            formula += element
            if count > 1 {
                formula += toSubscript(count)
            }
        }
        return formula
    }
    
    /// 将数字转换为下标形式
    private func toSubscript(_ n: Int) -> String {
        let subscripts = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
        return String(n).map { subscripts[Int(String($0))!] }.joined()
    }
}

// MARK: - 预选原子气泡

struct StagedAtomBubble: View {
    let element: String
    let index: Int
    let onRemove: () -> Void
    
    private let library = ElementLibrary.shared
    
    @State private var isAppearing = false
    @State private var isPressed = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 原子球
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(library.getColor(for: element)).opacity(0.9),
                            Color(library.getColor(for: element))
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 48, height: 48)
                .overlay(
                    Text(element)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color(library.getColor(for: element)).opacity(0.6), radius: isAppearing ? 6 : 2, x: 0, y: isAppearing ? 3 : 1)
                .scaleEffect(isAppearing ? (isPressed ? 0.9 : 1.0) : 0.3)
                .opacity(isAppearing ? 1.0 : 0)
            
            // 删除按钮
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 16, height: 16)
                    )
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
            .scaleEffect(isAppearing ? 1.0 : 0)
            .opacity(isAppearing ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.05)) {
                isAppearing = true
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    isPressed = false
                }
            }
        }
    }
}

struct AtomButton: View {
    let element: ElementInfo
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // 原子球体
                Circle()
                    .fill(Color(element.color))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: Color(element.color).opacity(0.4), radius: 6, x: 0, y: 3)
                
                // 元素符号
                Text(element.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                // 元素名称
                Text(element.name)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 自定义图形

struct TriangleStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // 等边三角形，顶点朝上
        path.move(to: CGPoint(x: width / 2, y: height * 0.15))
        path.addLine(to: CGPoint(x: width * 0.85, y: height * 0.85))
        path.addLine(to: CGPoint(x: width * 0.15, y: height * 0.85))
        path.closeSubpath()
        
        return path
    }
}

struct PhysicsWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // 物理波浪线表示分子运动
        let centerY = height / 2
        let amplitude: CGFloat = height * 0.25
        let startX = width * 0.15
        let endX = width * 0.85
        
        path.move(to: CGPoint(x: startX, y: centerY))
        
        // 正弦波
        for x in stride(from: startX, through: endX, by: 1) {
            let progress = (x - startX) / (endX - startX)
            let y = centerY + sin(progress * .pi * 3) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        // 添加原子符号点
        path.move(to: CGPoint(x: width * 0.25, y: centerY))
        path.addEllipse(in: CGRect(x: width * 0.22, y: centerY - 4, width: 8, height: 8))
        
        path.move(to: CGPoint(x: width * 0.75, y: centerY))
        path.addEllipse(in: CGRect(x: width * 0.72, y: centerY - 4, width: 8, height: 8))
        
        return path
    }
}

struct ConcentricCirclesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        
        // 三个同心圆，由内到外
        for i in 1...3 {
            let radius = maxRadius * CGFloat(i) / 3.5
            path.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        
        return path
    }
}

struct PolylineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // X 形折线（关闭图标）
        path.move(to: CGPoint(x: width * 0.25, y: height * 0.25))
        path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.75))
        
        path.move(to: CGPoint(x: width * 0.75, y: height * 0.25))
        path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.75))
        
        return path
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // 勾号形状
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.5))
        path.addLine(to: CGPoint(x: width * 0.4, y: height * 0.7))
        path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.3))
        
        return path
    }
}

// MARK: - 音效播放器

class SoundPlayer {
    
    init() {
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("音频会话配置失败: \(error)")
        }
        #endif
    }
    
    func playKnobSound() {
        // 使用系统音效：机械齿轮转动的咔哒声
        #if os(iOS)
        // iOS 使用系统音效 ID
        // 1103: 锁定/解锁音效（清脆的咔哒声）
        // 1306: 按键音效（短促的咔声）
        // 1519: 相机快门音（机械感）
        AudioServicesPlaySystemSound(1306) // 短促的机械咔哒声
        #else
        // macOS 使用 NSSound - Tink 音效有机械感
        NSSound(named: "Tink")?.play()
        #endif
    }
}

#Preview {
    ContentView()
}
