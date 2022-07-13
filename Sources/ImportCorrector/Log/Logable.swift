//
//  File.swift
//  
//
//  Created by Alan on 2022/7/13.
//

import Foundation

protocol Logable {
    
    var testMode: Bool { get }
    var log: Bool { get }
}

extension Logable {
    
    var shouldLog: Bool { self.log || self.testMode }
    
    func log(_ content: @autoclosure () -> CustomStringConvertible) {
        guard self.shouldLog else {
            return
        }
        print("[\(Self.self)] - " + content().description)
    }
}
