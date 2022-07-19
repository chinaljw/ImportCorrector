//
//  File.swift
//  
//
//  Created by Alan on 2022/7/15.
//

import Foundation

@discardableResult
func safeShell(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh") //<--updated
    task.standardInput = nil

    try task.run() //<--updated
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    
    return output
}

class PodDefine: CustomStringConvertible {
    
    let defineName: String
    var pods: [String] = []
    
    init(defineName: String) {
        self.defineName = defineName
    }
    
    var description: String {
        return "\n{ \n" + self.defineName + ", \n" + self.pods.description + " \n}"
    }
    
    var definLines: [String] {
        var lines = [String]()
        lines.append("def \(self.defineName)")
        self.pods.forEach { line in
            lines.append(line)
        }
        lines.append("end")
        lines.append("")
        return lines
    }
}

struct PodfileCorrector: Logable {
    
    typealias DefineTable = [String: PodDefine]
    typealias TargetPodsTable = [String: Set<String>]
    
    let dependancePods: [String]
    let podfile: String
    let mainTargetName: String
    let output: String
    let buildOutput: String
    
    var testMode: Bool = false
    var log: Bool = false
    
    func correct() throws {
        do {
            print("Podfile Correcting Started")
            print("Running...")
            let (defineTable, moduleTable) = try self.makePodFileInfo()
            let podDefineContent = podDefineContent(of: defineTable)
            
            self.log("defineTable: \(defineTable)")
            self.log("moduleTable: \(moduleTable)")
            
            let targetPodTable = try self.targetPodTable(of: self.buildOutput, with: moduleTable)
            self.log("targetPodsTable: \(targetPodTable)")
            let subjectPodContent = self.subprojectPodContent(of: targetPodTable)
            
            // write output
            let result = podDefineContent.appending(subjectPodContent)
            try result.write(toFile: output, atomically: true, encoding: .utf8)

            print("Check the output file(\(self.output) to determin whether or not to correct. \nInput 'y/Y' to execute correcting. Input others to exit.")
            
            // open output file
            try safeShell("open \(self.output)")
            
            // read line
            if let result = readLine() {
                print("input: \(result)")
                if result.lowercased() == "y" {
                    print("Correcting...")
                    try self.correct(withDefineTable: defineTable, targetPodsTable: targetPodTable)
                    print("Finished with correcting.")
                } else {
                    print("Finished without correcting.")
                }
            } else {
                print("Read nothing")
            }
        } catch {
            print(error)
        }
    }
}

extension PodfileCorrector {
    
    func match(of line: String, reg: String) throws -> String? {
        let reg = try NSRegularExpression(pattern: reg)
        let range = reg.rangeOfFirstMatch(in: line, range: .init(location: 0, length: line.count))
        guard let range = Range(range, in: line) else {
            return nil
        }
        return .init(line[range])
    }

    func pod(of line: String) throws -> String? {
        guard var matched = try match(of: line, reg: "pod '.*?'") else {
            return nil
        }
        matched.removeLast()
        matched.removeFirst(5)
        return matched
    }

    func moduleName(of line: String, with dependancePods: [String]) -> String {
        let modules = line.split(separator: "/").map({ String($0) })
        self.log("modules: " + modules.description)
        let moduleName: String
        if modules.count == 1 {
            moduleName = modules[0]
        } else {
            let first = modules[0]
            if dependancePods.contains(first) {
                moduleName = modules[1]
            } else {
                moduleName = first
            }
        }
        self.log("moduleName \(moduleName)")
        return moduleName
    }

    func defineName(of pod: String) -> String {
        let modules = pod.split(separator: "/").map({ String($0) })
        return (modules.first ?? pod).lowercased() + "_pods"
    }


    func lines(of file: String) throws -> [String] {
        let content = try String(contentsOfFile: file)
        return content.components(separatedBy: .newlines)
    }

    func isProjectStartLine(_ line: String, projectName: String) -> Bool {
        return line.hasPrefix("target '\(projectName)'")
    }

    func isEndLine(_ line: String) -> Bool {
        return line.hasPrefix("end")
    }

    func isDefineStartLine(_ line: String) -> Bool {
        return line.hasPrefix("def ")
    }

    func define(of line: String) throws -> String? {
        guard var matched = try match(of: line, reg: "def .*") else {
            return nil
        }
        matched.removeFirst(4)
        return matched
    }

    func podDefineContent(of defineTable: DefineTable) -> String {
        self.content(withLabel: "DEFINE_LIST") {
            var lines = [String]()
            lines.append("")
            lines.append(self.mainTargetName + " - START")
            defineTable.keys.forEach { key in
                lines.append(key)
            }
            lines.append(self.mainTargetName + " - END")
            
            lines.append("")
            defineTable.values.forEach { podDefine in
                lines.append(contentsOf: podDefine.definLines)
            }
            return lines
        }
    }
    
    func content(of lines: [String]) -> String {
        return lines.joined(separator: "\n")
    }
    
    func content(withLabel label: String, lines: () -> [String]) -> String {
        var result = [String]()
        result.append(self.seperator(withLabel: label, isStart: true))
        result.append(contentsOf: lines())
        result.append(self.seperator(withLabel: label, isStart: false))
        result.append("")
        result.append("")
        result.append("")
        return self.content(of: result)
    }
    
    func write(content: String, toFile file: String) throws {
        try content.write(toFile: file, atomically: true, encoding: .utf8)
    }
    
    func seperator(withLabel label: String, isStart: Bool) -> String {
        return "\(label)_\(isStart ? "START" : "End") ==============="
    }
    
    func makePodFileInfo() throws -> (DefineTable, [String: String]) {
        var podsTable = DefineTable()
        var moduleTable = [String: String]()
        let dependancePods = self.dependancePods
        
        let podfile = self.podfile
        let mainTargetName = self.mainTargetName
        
        let lines = try lines(of: podfile)
        
        var currentProject: String?
        var currentDefine: String?
        
        var keywordStack = [String]()
        let otherKeywords: Set<String> = ["if"]
        
        for index in 0..<lines.count {
            let line = lines[index]
            
            if isEndLine(line) && !keywordStack.isEmpty {
                keywordStack.removeLast()
                if keywordStack.isEmpty {
                    if currentProject != nil {
                        currentProject = nil
                    }
                    if currentDefine != nil {
                        currentDefine = nil
                    }
                }
                continue
            }
            else if isProjectStartLine(line, projectName: mainTargetName) {
                currentProject = mainTargetName
                keywordStack.append(mainTargetName)
                continue
            }
            else if isDefineStartLine(line),
                    let defineName = try define(of: line) {
                currentDefine = defineName
                continue
            } else if line.contains(where: { char in
                return otherKeywords.contains(char.description)
            }) {
                keywordStack.append(line)
                continue
            }
            
            // project mode
            if currentProject != nil {
                if let pod = try pod(of: line) {
                    let moduleName = moduleName(of: pod, with: dependancePods)
                    let defineName = defineName(of: pod)
                    self.log("defineName: \(defineName)")
                    
                    moduleTable[moduleName] = defineName
                    
                    var podDefine = podsTable[defineName]
                    if podDefine == nil {
                        podDefine = .init(defineName: defineName)
                        podsTable[defineName] = podDefine
                    }
                    podDefine?.pods.append(line)
                }
            }
            // define mode
            else if let currentDefine = currentDefine {
                if let pod = try pod(of: line) {
                    let moduleName = moduleName(of: pod, with: dependancePods)
                    self.log("currentDefine: \(currentDefine)")
                    moduleTable[moduleName] = currentDefine
                }
            }
        }
        return (podsTable, moduleTable)
    }

    // MARK: - sub project
    func isTargetStartLine(_ line: String) -> Bool {
        return line.hasPrefix("Build target ")
    }

    func targetName(ofLine line: String) -> String? {
        let components = line.components(separatedBy: " ")
        guard components.count > 2 else {
            return nil
        }
        return components[2]
    }

    func mayBeTargetEndLine(_ line: String) -> Bool {
        return line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func isNotFoundLine(_ line: String) -> Bool {
        return line.hasSuffix("file not found")
    }

    func notFoundModule(ofLine line: String) -> String? {
        let elements = line.split(separator: " ").map({ String($0) })
        guard elements.count > 3 else {
            return nil
        }
        let file = elements[elements.count - 4]
        let modules = file.split(separator: "/").map({ String($0) })
        guard modules.count > 1 else {
            return nil
        }
        var result = modules[0]
        result.removeFirst()
        return result
    }

    func subprojectPodContent(of targetPodTable: TargetPodsTable) -> String {
        self.content(withLabel: "SUBJECT_PODS") {
            var lines = [String]()
            targetPodTable.forEach { key, pods in
                lines.append(key + " {")
                pods.forEach { line in
                    lines.append(line)
                }
                lines.append("}")
                lines.append("")
            }
            return lines
        }
    }
    
    func targetPodTable(of buildOutput: String, with moduleTable: [String: String]) throws -> TargetPodsTable {
        let lines = try lines(of: buildOutput)
        
        var currentTarget: String?
        var emptyLineCount = 0
        
        var targetPodTable = TargetPodsTable()
        
        for index in 0..<lines.count {
            let line = lines[index]
            
            if mayBeTargetEndLine(line) {
                if emptyLineCount == 0 {
                    emptyLineCount += 1
                } else if emptyLineCount == 1 {
                    emptyLineCount = 0
                    currentTarget = nil
                }
                continue
            } else {
                emptyLineCount = 0
                if isTargetStartLine(line),
                   let targetName = targetName(ofLine: line)
                {
                    self.log(targetName)
                    currentTarget = targetName
                    targetPodTable[targetName] = .init()
                    continue
                }
                
                if let currentTarget = currentTarget {
                    if isNotFoundLine(line),
                       let notFoundModule = notFoundModule(ofLine: line)
                    {
                        if let podDefine = moduleTable[notFoundModule] {
                            var pods = targetPodTable[currentTarget]
                            pods?.insert(podDefine)
                            targetPodTable[currentTarget] = pods
                        }
                    }
                }
            }
        }
        return targetPodTable
    }
}

extension PodfileCorrector {
    
    func correct(withDefineTable defineTable: DefineTable, targetPodsTable: TargetPodsTable) throws {
        let oldLines = try self.lines(of: self.podfile)
        var lines = [String]()
        var keywordStack = [String]()
        var isInMainTarget = false
        var currentSubProjectTarget: String?
        try oldLines.forEach { line in
            if isInMainTarget,
               try self.pod(of: line) != nil
            || line.trimmingCharacters(in: .whitespaces).isEmpty {
                // remove main target pods
                return
            }
            
            if isEndLine(line),
               !keywordStack.isEmpty
            {
                keywordStack.removeLast()
                if keywordStack.isEmpty {
                    if isInMainTarget {
                        // end main target
                        isInMainTarget = false
                        defineTable.keys.forEach { defineName in
                            lines.append("    " + defineName)
                        }
                    }
                    else if let subProjectTarget = currentSubProjectTarget {
                        // end current subProjectTarget
                        let podsOfTarget = targetPodsTable[subProjectTarget]?.map({ "\t" + $0 })
                        if let podsOfTarget = podsOfTarget {
                            lines.append(contentsOf: podsOfTarget)
                        }
                        currentSubProjectTarget = nil
                        self.log("end target \(subProjectTarget), podsOfTarget: \(podsOfTarget?.description ?? "nil")")
                    }
                }
            }
            else if self.isProjectStartLine(line, projectName: self.mainTargetName) {
                // start main target
                keywordStack.append(self.mainTargetName)
                isInMainTarget = true
            }
            else if let targetName = try self.subProjectTargetName(ofLine: line) {
                self.log("matched targetName: \(targetName)")
                // start subProject
                keywordStack.append(targetName)
                currentSubProjectTarget = targetName
            }
            
            // append normal line
            lines.append(line)
            
            if self.isPlatform(line: line) {
               // insert pods define
               lines.append("")
               lines.append(contentsOf: self.defineLins(of: defineTable))
           }
        }
        try self.write(content: self.content(of: lines), toFile: self.podfile)
    }
    
    func subProjectTargetName(ofLine line: String) throws -> String? {
        guard let matched = try self.match(of: line, reg: "target '.*?' do project ") else {
            return nil
        }
        var result = matched.split(separator: " ").map({ String($0) })[1]
        result.removeFirst()
        result.removeLast()
        return result
    }
    
    func isPlatform(line: String) -> Bool {
        return line.hasPrefix("platform :ios")
    }
    
    func defineLins(of defineTable: DefineTable) -> [String] {
        var lines = [String]()
        lines.append(contentsOf: defineTable.values.flatMap({ $0.definLines }))
        return lines
    }
}
