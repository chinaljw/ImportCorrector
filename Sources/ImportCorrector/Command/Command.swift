//
//  File.swift
//  
//
//  Created by Alan on 2022/7/13.
//

import Foundation
import ArgumentParser

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
                                                           subcommands: [
                                                            ProjectDir.self,
                                                            SpecificDir.self,
                                                            PodDir.self,
                                                           ],
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
        
        @Option(name: .long, parsing: .upToNextOption, help: "excludeTables")
        var excludeTables: [String] = []
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
                                     relativeExcludedDirs: self.relativeExcludedDirs,
                                     excludeTables: self.commonOptions.excludeTables))
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
                                     exlcudedDirs: self.commonOptions.excludedDirs,
                                     excludeTables: self.commonOptions.excludeTables))
        }
    }
    
    struct PodDir: ParsableCommand, CorrectCommand {
        
        static var configuration: CommandConfiguration = .init(commandName: "podProject",
                                                               abstract: "Pod project directory",
                                                               helpNames: .shortAndLong)
        
        @Argument(help: "Pod project directory")
        var podDir: String
        
        @Option(name: .shortAndLong, help: "headersDir")
        var headersDir: String?
        
        @Option(name: .shortAndLong, help: "Pod name")
        var podName: String?
        
        @OptionGroup
        var commonOptions: CommonOptions
        
        func run() throws {
            try self.run(flow: .init(podDir: self.podDir,
                                     headerDir: self.headersDir,
                                     exlcudedDirs: self.commonOptions.excludedDirs,
                                     podName: self.podName,
                                     excludeTables: self.commonOptions.excludeTables))
        }
    }
}
