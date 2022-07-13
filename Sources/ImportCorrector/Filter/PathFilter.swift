//
//  File.swift
//  
//
//  Created by Alan on 2022/7/13.
//

import Foundation

struct PathInfo {
    
    let rootFolderPath: String
    let path: String
    
    let fullPath: String
    let isExist: Bool
    let isDirectory: Bool
    
    init(rootFolderPath: String, path: String) {
        self.rootFolderPath = rootFolderPath
        self.path = path
        
        self.fullPath = rootFolderPath + "/" + path
        var isDir: ObjCBool = false
        let isExist = FileManager.default.fileExists(atPath: self.fullPath, isDirectory: &isDir)
        self.isExist = isExist
        self.isDirectory = isDir.boolValue
    }
}

protocol PathFilter {
    
    func shouldSkip(for pathInfo: PathInfo) -> Bool
}

struct PodsFilter: PathFilter {
    
    func shouldSkip(for pathInfo: PathInfo) -> Bool {
        return pathInfo.path.hasPrefix("Pods")
    }
}

struct OCFilter: PathFilter {
    
    func shouldSkip(for pathInfo: PathInfo) -> Bool {
        let path = pathInfo.path
        return !path.hasSuffix(".h") && !path.hasSuffix(".m") && !path.hasSuffix(".mm")
    }
}

struct ExcludedFolderFilter: PathFilter {
    
    let excludedDirs: [String]
    
    func shouldSkip(for pathInfo: PathInfo) -> Bool {
        return self.excludedDirs.contains(pathInfo.fullPath)
    }
}

struct RelativeExcludedFolderFilter: PathFilter {
    
    let relativeExcludedDirs: [String]
    
    func shouldSkip(for pathInfo: PathInfo) -> Bool {
        return self.relativeExcludedDirs.contains(where: { pathInfo.path.hasPrefix($0) })
    }
}
