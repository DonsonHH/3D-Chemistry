//
//  ElementLibrary.swift
//  3D-Chemistry
//
//  Created by ypx on 2025/11/12.
//

import Foundation
import SceneKit

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

/// 元素信息结构体
struct ElementInfo {
    let symbol: String          // 元素符号
    let name: String            // 元素名称
    let atomicNumber: Int       // 原子序数
    let covalentRadius: Float   // 共价半径 (Å)
    let visualRadius: CGFloat   // 可视化半径
    let color: PlatformColor    // CPK 颜色
    let commonValences: [Int]   // 常见化合价
    let maxBonds: Int           // 最大成键数
}

/// 元素库
class ElementLibrary {
    static let shared = ElementLibrary()
    
    private var elements: [String: ElementInfo] = [:]
    
    private init() {
        setupElements()
    }
    
    private func setupElements() {
        // 非金属元素
        addElement(ElementInfo(
            symbol: "H", name: "氢", atomicNumber: 1,
            covalentRadius: 0.31, visualRadius: 0.20,
            color: PlatformColor.white,
            commonValences: [1], maxBonds: 1
        ))
        
        addElement(ElementInfo(
            symbol: "C", name: "碳", atomicNumber: 6,
            covalentRadius: 0.76, visualRadius: 0.33,
            color: PlatformColor.darkGray,
            commonValences: [4], maxBonds: 4
        ))
        
        addElement(ElementInfo(
            symbol: "N", name: "氮", atomicNumber: 7,
            covalentRadius: 0.71, visualRadius: 0.32,
            color: PlatformColor(red: 0.19, green: 0.31, blue: 0.97, alpha: 1.0),
            commonValences: [3, 5], maxBonds: 4  // 包括配位键
        ))
        
        addElement(ElementInfo(
            symbol: "O", name: "氧", atomicNumber: 8,
            covalentRadius: 0.66, visualRadius: 0.35,
            color: PlatformColor.red,
            commonValences: [2], maxBonds: 2
        ))
        
        addElement(ElementInfo(
            symbol: "F", name: "氟", atomicNumber: 9,
            covalentRadius: 0.57, visualRadius: 0.30,
            color: PlatformColor(red: 0.56, green: 0.88, blue: 0.31, alpha: 1.0),
            commonValences: [1], maxBonds: 1
        ))
        
        addElement(ElementInfo(
            symbol: "P", name: "磷", atomicNumber: 15,
            covalentRadius: 1.07, visualRadius: 0.36,
            color: PlatformColor.orange,
            commonValences: [3, 5], maxBonds: 5
        ))
        
        addElement(ElementInfo(
            symbol: "S", name: "硫", atomicNumber: 16,
            covalentRadius: 1.05, visualRadius: 0.38,
            color: PlatformColor.yellow,
            commonValences: [2, 4, 6], maxBonds: 6
        ))
        
        addElement(ElementInfo(
            symbol: "Cl", name: "氯", atomicNumber: 17,
            covalentRadius: 0.99, visualRadius: 0.34,
            color: PlatformColor.green,
            commonValences: [1, 3, 5, 7], maxBonds: 1
        ))
        
        addElement(ElementInfo(
            symbol: "Br", name: "溴", atomicNumber: 35,
            covalentRadius: 1.20, visualRadius: 0.40,
            color: PlatformColor(red: 0.65, green: 0.16, blue: 0.16, alpha: 1.0),
            commonValences: [1, 3, 5], maxBonds: 1
        ))
        
        addElement(ElementInfo(
            symbol: "I", name: "碘", atomicNumber: 53,
            covalentRadius: 1.39, visualRadius: 0.45,
            color: PlatformColor(red: 0.58, green: 0.0, blue: 0.58, alpha: 1.0),
            commonValences: [1, 3, 5, 7], maxBonds: 1
        ))
        
        // 金属元素
        addElement(ElementInfo(
            symbol: "Li", name: "锂", atomicNumber: 3,
            covalentRadius: 1.28, visualRadius: 0.42,
            color: PlatformColor(red: 0.8, green: 0.5, blue: 1.0, alpha: 1.0),
            commonValences: [1], maxBonds: 1
        ))
        
        addElement(ElementInfo(
            symbol: "Na", name: "钠", atomicNumber: 11,
            covalentRadius: 1.66, visualRadius: 0.48,
            color: PlatformColor(red: 0.67, green: 0.36, blue: 0.95, alpha: 1.0),
            commonValences: [1], maxBonds: 1
        ))
        
        addElement(ElementInfo(
            symbol: "Mg", name: "镁", atomicNumber: 12,
            covalentRadius: 1.41, visualRadius: 0.44,
            color: PlatformColor(red: 0.54, green: 1.0, blue: 0.0, alpha: 1.0),
            commonValences: [2], maxBonds: 2
        ))
        
        addElement(ElementInfo(
            symbol: "Al", name: "铝", atomicNumber: 13,
            covalentRadius: 1.21, visualRadius: 0.40,
            color: PlatformColor(red: 0.75, green: 0.65, blue: 0.65, alpha: 1.0),
            commonValences: [3], maxBonds: 3
        ))
        
        addElement(ElementInfo(
            symbol: "Si", name: "硅", atomicNumber: 14,
            covalentRadius: 1.11, visualRadius: 0.38,
            color: PlatformColor(red: 0.94, green: 0.78, blue: 0.63, alpha: 1.0),
            commonValences: [4], maxBonds: 4
        ))
        
        addElement(ElementInfo(
            symbol: "K", name: "钾", atomicNumber: 19,
            covalentRadius: 2.03, visualRadius: 0.54,
            color: PlatformColor(red: 0.56, green: 0.25, blue: 0.83, alpha: 1.0),
            commonValences: [1], maxBonds: 1
        ))
        
        addElement(ElementInfo(
            symbol: "Ca", name: "钙", atomicNumber: 20,
            covalentRadius: 1.76, visualRadius: 0.50,
            color: PlatformColor(red: 0.24, green: 1.0, blue: 0.0, alpha: 1.0),
            commonValences: [2], maxBonds: 2
        ))
        
        // 过渡金属
        addElement(ElementInfo(
            symbol: "Fe", name: "铁", atomicNumber: 26,
            covalentRadius: 1.32, visualRadius: 0.42,
            color: PlatformColor(red: 0.88, green: 0.4, blue: 0.2, alpha: 1.0),
            commonValences: [2, 3], maxBonds: 6
        ))
        
        addElement(ElementInfo(
            symbol: "Cu", name: "铜", atomicNumber: 29,
            covalentRadius: 1.32, visualRadius: 0.42,
            color: PlatformColor(red: 0.78, green: 0.5, blue: 0.2, alpha: 1.0),
            commonValences: [1, 2], maxBonds: 4
        ))
        
        addElement(ElementInfo(
            symbol: "Zn", name: "锌", atomicNumber: 30,
            covalentRadius: 1.22, visualRadius: 0.40,
            color: PlatformColor(red: 0.49, green: 0.50, blue: 0.69, alpha: 1.0),
            commonValences: [2], maxBonds: 2
        ))
        
        // 稀有气体（一般不成键）
        addElement(ElementInfo(
            symbol: "He", name: "氦", atomicNumber: 2,
            covalentRadius: 0.28, visualRadius: 0.18,
            color: PlatformColor(red: 0.85, green: 1.0, blue: 1.0, alpha: 1.0),
            commonValences: [0], maxBonds: 0
        ))
        
        addElement(ElementInfo(
            symbol: "Ne", name: "氖", atomicNumber: 10,
            covalentRadius: 0.58, visualRadius: 0.28,
            color: PlatformColor(red: 0.70, green: 0.89, blue: 0.96, alpha: 1.0),
            commonValences: [0], maxBonds: 0
        ))
        
        addElement(ElementInfo(
            symbol: "Ar", name: "氩", atomicNumber: 18,
            covalentRadius: 0.97, visualRadius: 0.35,
            color: PlatformColor(red: 0.50, green: 0.82, blue: 0.89, alpha: 1.0),
            commonValences: [0], maxBonds: 0
        ))
        
        // 特殊元素：硼
        addElement(ElementInfo(
            symbol: "B", name: "硼", atomicNumber: 5,
            covalentRadius: 0.84, visualRadius: 0.32,
            color: PlatformColor(red: 1.0, green: 0.71, blue: 0.71, alpha: 1.0),
            commonValences: [3], maxBonds: 3
        ))
    }
    
    private func addElement(_ element: ElementInfo) {
        elements[element.symbol.lowercased()] = element
    }
    
    // MARK: - 公共访问方法
    
    func getElement(_ symbol: String) -> ElementInfo? {
        return elements[symbol.lowercased()]
    }
    
    func getCovalentRadius(for symbol: String) -> Float {
        return elements[symbol.lowercased()]?.covalentRadius ?? 0.7
    }
    
    func getVisualRadius(for symbol: String) -> CGFloat {
        return elements[symbol.lowercased()]?.visualRadius ?? 0.30
    }
    
    func getColor(for symbol: String) -> PlatformColor {
        return elements[symbol.lowercased()]?.color ?? .gray
    }
    
    func getMaxBonds(for symbol: String) -> Int {
        return elements[symbol.lowercased()]?.maxBonds ?? 4
    }
    
    func getCommonValences(for symbol: String) -> [Int] {
        return elements[symbol.lowercased()]?.commonValences ?? [1, 2, 3, 4]
    }
    
    /// 判断两个原子之间是否可以形成化学键
    func canFormBond(between element1: String, and element2: String, currentBonds1: Int, currentBonds2: Int) -> Bool {
        let maxBonds1 = getMaxBonds(for: element1)
        let maxBonds2 = getMaxBonds(for: element2)
        
        // 检查两个原子是否都还有成键能力
        return currentBonds1 < maxBonds1 && currentBonds2 < maxBonds2
    }
    
    /// 计算两个原子之间的理想键长
    func getIdealBondLength(between element1: String, and element2: String) -> Float {
        let r1 = getCovalentRadius(for: element1)
        let r2 = getCovalentRadius(for: element2)
        return r1 + r2
    }
    
    /// 判断给定距离是否在合理的成键范围内
    func isValidBondDistance(_ distance: Float, between element1: String, and element2: String) -> Bool {
        let idealLength = getIdealBondLength(between: element1, and: element2)
        let minLength = idealLength * 0.7  // 最短 70%
        let maxLength = idealLength * 1.3  // 最长 130%
        return distance >= minLength && distance <= maxLength
    }
    
    /// 获取所有已注册的元素符号
    func getAllElementSymbols() -> [String] {
        return Array(elements.keys).sorted()
    }
    
    // MARK: - 键角数据
    
    /// 理想键角（根据 VSEPR 理论）
    /// 返回中心原子周围的理想键角（弧度）
    func getIdealBondAngle(centerElement: String, bondCount: Int) -> Float {
        let element = centerElement.lowercased()
        
        // 根据中心原子和成键数确定杂化方式及键角
        switch element {
        case "o":
            // 氧：sp³ 杂化，有两对孤电子对
            // H₂O: 实际 104.5°
            if bondCount == 2 {
                return 104.5 * Float.pi / 180.0
            }
            return 109.5 * Float.pi / 180.0
            
        case "n":
            // 氮：sp³ 杂化，有一对孤电子对
            // NH₃: 实际 107°
            if bondCount == 3 {
                return 107.0 * Float.pi / 180.0
            }
            return 109.5 * Float.pi / 180.0
            
        case "c":
            // 碳：根据成键数
            switch bondCount {
            case 4:
                // sp³ 杂化，如 CH₄: 109.5°
                return 109.5 * Float.pi / 180.0
            case 3:
                // sp² 杂化，如 C=C: 120°
                return 120.0 * Float.pi / 180.0
            case 2:
                // sp 杂化，如 C≡C: 180°
                return 180.0 * Float.pi / 180.0
            default:
                return 109.5 * Float.pi / 180.0
            }
            
        case "s":
            // 硫：类似氧
            if bondCount == 2 {
                return 92.0 * Float.pi / 180.0  // H₂S
            }
            return 109.5 * Float.pi / 180.0
            
        case "p":
            // 磷
            if bondCount == 3 {
                return 93.5 * Float.pi / 180.0  // PH₃
            }
            return 109.5 * Float.pi / 180.0
            
        case "si":
            // 硅：sp³ 杂化
            return 109.5 * Float.pi / 180.0
            
        case "b":
            // 硼：sp² 杂化
            return 120.0 * Float.pi / 180.0
            
        default:
            // 默认四面体角度
            return 109.5 * Float.pi / 180.0
        }
    }
}
