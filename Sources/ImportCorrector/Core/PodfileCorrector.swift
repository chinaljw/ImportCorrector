//
//  File.swift
//  
//
//  Created by Alan on 2022/7/15.
//

import Foundation

class PodDefine: CustomStringConvertible {
    
    let defineName: String
    var pods: [String] = []
    
    init(defineName: String) {
        self.defineName = defineName
    }
    
    var description: String {
        return "\n{ \n" + self.defineName + ", \n" + self.pods.description + " \n}"
    }
}

struct PodfileCorrector: Logable {
    
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
            let (podsTable, moduleTable) = try self.makePodFileInfo()
            let podDefineContent = podDefineContent(of: podsTable)
            
            self.log("podsTable \(podsTable)")
            self.log("moduleTable \(moduleTable)")
            
            let subjectPodContent = try subprojectPodContent(of: buildOutput, with: moduleTable)
            
            let result = podDefineContent.appending(subjectPodContent)
            //    let result = subjectPodContent
            try result.write(toFile: output, atomically: true, encoding: .utf8)
            print("Podfile Correcting Finished")
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

    func podDefineContent(of defineTable: [String: PodDefine]) -> String {
        var lines = [String]()
        lines.append("DEFINE_TABLE_START ===============")
        lines.append("")
        defineTable.values.forEach { podDefine in
            lines.append("def \(podDefine.defineName)")
            podDefine.pods.forEach { line in
                lines.append(line)
            }
            lines.append("end")
            lines.append("")
        }
        lines.append("DEFINE_TABLE_END ===============")
        lines.append("")
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\n")
    }
    
    func makePodFileInfo() throws -> ([String: PodDefine], [String: String]) {
        var podsTable = [String: PodDefine]()
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

    func subprojectPodContent(of targetPodTable: [String: Set<String>]) -> String {
        var lines = [String]()
        lines.append("SUBJECT_PODS_START ===============")
        lines.append("")
        targetPodTable.forEach { key, pods in
            lines.append(key + " {")
            pods.forEach { line in
                lines.append("\t" + line)
            }
            lines.append("}")
            lines.append("")
        }
        lines.append("SUBJECT_PODS_END ===============")
        lines.append("")
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    func subprojectPodContent(of buildOutput: String, with moduleTable: [String: String]) throws -> String {
        let lines = try lines(of: buildOutput)
        
        var currentTarget: String?
        var emptyLineCount = 0
        
        var targetPodTable = [String: Set<String>]()
        
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
        return subprojectPodContent(of: targetPodTable)
    }
}
