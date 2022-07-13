//
//  File.swift
//  
//
//  Created by Alan on 2022/7/13.
//

import Foundation

typealias ImportTable = [String: [String: String]]

class ImportTableMaker: Logable {
    
    enum Error: LocalizedError {
        
        case noExist(path: String)
        case noneFolder(path: String)
        case failedToCreateEnumerator(path: String)
    }
    
    let publicHeaderFolders: [String]
    var excludeTables: [String] = []
    
    var testMode: Bool = false
    var log: Bool = false
    
    init(publicHeaderFolders: [String]) {
        self.publicHeaderFolders = publicHeaderFolders
    }
    
    func make() throws -> ImportTable {
        var result = ImportTable()
        try self.publicHeaderFolders.forEach { folderPath in
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
            while let element = enumerator.nextObject() as? String {
                if !self.excludeTables.isEmpty && self.excludeTables.contains(element) {
                    enumerator.skipDescendents()
                    continue
                }
                if !element.contains("/") {
                    result[element] = [String: String]()
                } else {
                    let elements = element.components(separatedBy: "/")
                    let module = elements[0]
                    let header = elements[1]
                    let correct = "#import <\(element)>"
                    result[module]?[#"#import ""# + header + #"""#] = correct
                    result[module]?["#import <\(header)>"] = correct
                }
            }
            enumerator.enumerated().forEach({ tuple in
                if let element = tuple.element as? String {
                    if !element.contains("/") {
                        result[element] = [String: String]()
                    } else {
                        let elements = element.components(separatedBy: "/")
                        let module = elements[0]
                        let header = elements[1]
                        let correct = "#import <\(element)>"
                        result[module]?[#"#import ""# + header + #"""#] = correct
                        result[module]?["#import <\(header)>"] = correct
                    }
                }
            })
        }
        
        if self.shouldLog {
            result.forEach { key, value in
                self.log("<<<<<<<< \(key)")
                value.forEach { key, value in
                    self.log("[key: \(key)] \t [value: \(value)]")
                }
                self.log(">>>>>>>> \(key)")
            }
        }
        
        return result
    }
}
