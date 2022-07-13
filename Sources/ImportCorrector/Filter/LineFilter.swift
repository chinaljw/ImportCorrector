//
//  File.swift
//  
//
//  Created by Alan on 2022/7/13.
//

import Foundation

protocol LineFilter {
    
    func shouldSkip(_ line: String, with pathInfo: PathInfo) -> Bool
}

struct CommonLineFilter: LineFilter {
    
    func shouldSkip(_ line: String, with pathInfo: PathInfo) -> Bool {
        return line.hasPrefix("//")
            || line.trimmingCharacters(in: .whitespaces).isEmpty
            || (!pathInfo.isDirectory && (line.contains("#ifndef ") || line.contains("#define ")))
            
    }
}
