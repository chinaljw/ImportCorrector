import Foundation
import ArgumentParser

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

typealias ImportTable = [String: [String: String]]

class ImportTableMaker: Logable {
    
    enum Error: LocalizedError {
        
        case noExist(path: String)
        case noneFolder(path: String)
        case failedToCreateEnumerator(path: String)
    }
    
    let publicHeaderFolders: [String]
    
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

struct CorrectFlow: Logable {
    
    let publicHeaderFolders: [String]
    let folderFilters: [PathFilter]
    
    let correctingFolders: [String]
    
    var testMode: Bool = false
    var log: Bool = false
    
    init(projectDir: String,
         headersDirs: [String],
         exlcudedDirs: [String],
         relativeExcludedDirs: [String]) {
        self.correctingFolders = [projectDir]
        self.publicHeaderFolders = !headersDirs.isEmpty ? headersDirs : [projectDir + "/Pods/Headers/Public"]
        var folderFilters = [PathFilter]()
        if !exlcudedDirs.isEmpty {
            folderFilters.append(ExcludedFolderFilter(excludedDirs: exlcudedDirs))
        }
        if !relativeExcludedDirs.isEmpty {
            folderFilters.append(RelativeExcludedFolderFilter(relativeExcludedDirs: relativeExcludedDirs))
        }
        self.folderFilters = folderFilters
    }
    
    init(specificDirs: [String],
         headerDirs: [String],
         exlcudedDirs: [String]) {
        self.correctingFolders = specificDirs
        self.publicHeaderFolders = headerDirs
        var folderFilters = [PathFilter]()
        if !exlcudedDirs.isEmpty {
            folderFilters.append(ExcludedFolderFilter(excludedDirs: exlcudedDirs))
        }
        self.folderFilters = folderFilters
    }
    
    func run() throws {
        print("Start")
        print("Running...")
        // table maker
        let tableMaker = ImportTableMaker(publicHeaderFolders: self.publicHeaderFolders)
        tableMaker.testMode = self.testMode
        tableMaker.log = self.log
        let importTable = try tableMaker.make()
        
        // corrector
        let fileFilters = [OCFilter()]
        var folderFilters = self.folderFilters
        folderFilters.append(PodsFilter())
        let lineFilters = [CommonLineFilter()]
        let corrector = ImportCorrector(folders: self.correctingFolders,
                                        importTable: importTable,
                                        fileFilters: fileFilters,
                                        folderFilters: folderFilters,
                                        lineFilters: lineFilters)
        corrector.testMode = self.testMode
        corrector.log = self.log
        try corrector.correct()
        print("Finished")
    }
}

protocol CorrectCommand {
    
    var commonOptions: CorrectImport.CommonOptions { get }
}

extension CorrectCommand {
    
    func run(flow: @autoclosure () -> CorrectFlow) throws {
        var flow = flow()
        flow.testMode = self.commonOptions.testMode
        flow.log = self.commonOptions.log
        try flow.run()
    }
}

struct CorrectImport: ParsableCommand {
    
    static var configuration: CommandConfiguration = .init(commandName: "correctimport",
                                                           abstract: "Correct import way",
                                                           version: "1.0.0",
                                                           subcommands: [ProjectDir.self, SpecificDir.self],
                                                           defaultSubcommand: ProjectDir.self,
                                                           helpNames: .shortAndLong)
}

extension CorrectImport {
    
    struct CommonOptions: ParsableArguments {
        
        @Option(name: .shortAndLong, parsing: .upToNextOption, help: "excludedDirs")
        var excludedDirs: [String] = []
        
        @Flag(name: .shortAndLong, help: "testMode")
        var testMode: Bool = false
        
        @Flag(name: .shortAndLong, help: "log")
        var log: Bool = false
    }
    
    struct ProjectDir: ParsableCommand, CorrectCommand {
        
        static var configuration: CommandConfiguration = .init(commandName: "project",
                                                               abstract: "Project directory",
                                                               helpNames: .shortAndLong)
        
        @Argument(help: "project dir")
        var path: String
        
        @OptionGroup
        var commonOptions: CommonOptions
        
        @Option(name: .shortAndLong, parsing: .upToNextOption, help: "headersDir")
        var headersDirs: [String] = []
        
        @Option(name: .shortAndLong, parsing: .upToNextOption, help: "relativeExcludedDirs")
        var relativeExcludedDirs: [String] = []
        
        func run() throws {
            try self.run(flow: .init(projectDir: self.path,
                                     headersDirs: self.headersDirs,
                                     exlcudedDirs: self.commonOptions.excludedDirs,
                                     relativeExcludedDirs: self.relativeExcludedDirs))
        }
    }
    
    struct SpecificDir: ParsableCommand, CorrectCommand {
        
        static var configuration: CommandConfiguration = .init(commandName: "dirs",
                                                               abstract: "Specific dirs",
                                                               helpNames: .shortAndLong)
        
        @Argument(help: "specific dirs")
        var dirs: [String]
        
        @Option(name: .shortAndLong, parsing: .upToNextOption, help: "headersDir")
        var headersDirs: [String]
        
        @OptionGroup
        var commonOptions: CommonOptions
        
        func run() throws {
            try self.run(flow: .init(specificDirs: self.dirs,
                                     headerDirs: self.headersDirs,
                                     exlcudedDirs: self.commonOptions.excludedDirs))
        }
    }
    
    struct Log: ParsableCommand {
        
        static var configuration: CommandConfiguration = .init(commandName: "log",
                                                               abstract: "log or no",
                                                               helpNames: .shortAndLong)
        
        
    }
}

CorrectImport.main()
