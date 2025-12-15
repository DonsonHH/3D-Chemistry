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
            
            // 原子选择面板
            if isAtomSelectorVisible {
                AtomSelectorPanel { selectedElement in
                    addAtomToScene(element: selectedElement)
                }
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
                
                // 右侧按钮（同心圆或折线）
                Button {
                    handleRightButton()
                } label: {
                    if isAtomSelectorVisible {
                        PolylineShape()
                            .stroke(Color.white, lineWidth: 2.5)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    } else {
                        ConcentricCirclesShape()
                            .stroke(Color.white, lineWidth: 2.5)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
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
        
        withAnimation {
            isAtomSelectorVisible.toggle()
        }
    }
    
    private func addAtomToScene(element: String) {
        // 在场景中心附近添加新原子
        let library = ElementLibrary.shared
        let newAtom = Atom(
            element: element,
            position: SCNVector3(
                Float.random(in: -0.5...0.5),
                Float.random(in: -0.5...0.5),
                Float.random(in: -0.5...0.5)
            ),
            radius: library.getVisualRadius(for: element)
        )
        atoms.append(newAtom)
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
    var onSelect: (String) -> Void
    
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
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.08))
                
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
