//
//  XYZParser.swift
//  3D-Chemistry
//
//  Created by ypx on 2025/11/12.
//

import Foundation
import SceneKit

struct XYZParser {
    static func parse(_ text: String) -> [Atom] {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 3 else { return [] }
        // 第一行为原子数（可忽略）
        // 第二行为注释
        // 从第三行开始是元素和坐标
        var atoms: [Atom] = []
        for i in 2..<lines.count {
            let parts = lines[i].split(whereSeparator: { $0.isWhitespace }).map { String($0) }
            if parts.count >= 4 {
                let elem = parts[0]
                if let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                    let pos = SCNVector3(x, y, z)
                    let radius = MoleculeScene.defaultRadius(for: elem)
                    atoms.append(Atom(element: elem, position: pos, radius: radius))
                }
            }
        }
        return atoms
    }
}
