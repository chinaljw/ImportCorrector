//
//  File.swift
//  
//
//  Created by Alan on 2022/7/13.
//

import Foundation

class ImportCorrector: Logable {
    
    enum Error: LocalizedError {
        
        case noExist(path: String)
        case noneFolder(path: String)
        case failedToCreateEnumerator(path: String)
    }
    
    let folders: [String]
    let importTable: ImportTable
    let fileFilters: [PathFilter]
    let folderFilters: [PathFilter]
    let lineFilters: [LineFilter]
    
    var testMode: Bool = false
    var log: Bool = false
    
    init(folders: [String],
         importTable: ImportTable,
         fileFilters: [PathFilter],
         folderFilters: [PathFilter],
         lineFilters: [LineFilter]) {
        self.folders = folders
        self.importTable = importTable
        self.fileFilters = fileFilters
        self.folderFilters = folderFilters
        self.lineFilters = lineFilters
    }
    
    func correct() throws {
        try self.folders.forEach { folderPath in
            // check folder available
            let enumerator = try self.enumerator(for: folderPath)
            // enumerate
            while let path = enumerator.nextObject() as? String {
                let pathInfo = PathInfo(rootFolderPath: folderPath, path: path)
                // filter
                guard self.filterPath(with: pathInfo, enumerator: enumerator) else {
                    continue
                }
                // do correct
                try self.correctFile(with: pathInfo)
            }
        }
    }
    
    func enumerator(for folderPath: String) throws -> FileManager.DirectoryEnumerator {
        var isDir: ObjCBool = false
        let isExist = FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir)
        guard isExist else {
            throw Error.noExist(path: folderPath)
        }
        guard isDir.boolValue else {
            throw Error.noneFolder(path: folderPath)
        }
        guard let enumerator = FileManager.default.enumerator(atPath: folderPath) else {
            throw Error.failedToCreateEnumerator(path: folderPath)
        }
        return enumerator
    }
    
    func filterPath(with pathInfo: PathInfo, enumerator: FileManager.DirectoryEnumerator) -> Bool {
        var shouldSkip = false
        
        for filter in pathInfo.isDirectory ? self.folderFilters : self.fileFilters {
            if filter.shouldSkip(for: pathInfo) {
                shouldSkip = true
                break;
            }
        }
        
        if shouldSkip || pathInfo.isDirectory {
            if shouldSkip && pathInfo.isDirectory {
                enumerator.skipDescendents()
            }
            return false
        } else {
            return true
        }
    }
    
    func filterLine(_ line: String, with pathInfo: PathInfo) -> Bool {
        for filter in self.lineFilters {
            if filter.shouldSkip(line, with: pathInfo) {
                return false
            }
        }
        return true
    }
    
    func correctFile(with pathInfo: PathInfo) throws {
        self.log("<<<<<<<<<<< \(pathInfo.path)")
        let filePath = pathInfo.fullPath
        let content = try String(contentsOfFile: filePath)
        var components = content.components(separatedBy: .newlines)
        var noImportCount = 0
        var changed = false
        for index in 0..<components.count {
            let line = components[index]
            self.log("line \(line)")
            guard self.filterLine(line, with: pathInfo) else {
                continue
            }
            if !line.contains("#import") {
                noImportCount += 1
                if noImportCount >= 2 {
                    break
                }
            } else {
                noImportCount = 0
                for element in self.importTable.enumerated() {
                    let value = element.element.value
                    if let match = value[line] {
                        changed = true
                        components[index] = match
                        self.log("match \(match)")
                        break
                    }
                }
            }
        }
        if changed {
            let new = components.joined(separator: "\n")
            if !self.testMode {
                try new.write(toFile: filePath, atomically: false, encoding: .utf8)
            }
        }
        self.log(">>>>>>>>>>>> \(pathInfo.path)")
    }
}
