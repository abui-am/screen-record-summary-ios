//
//  MLMultiArray+FloatArray.swift
//  iamge-detection
//

import CoreML

extension MLMultiArray {
    func floatArray() -> [Float] {
        let count = self.count
        var result = [Float](repeating: 0, count: count)
        let ptr = dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            result[i] = ptr[i]
        }
        return result
    }
}
