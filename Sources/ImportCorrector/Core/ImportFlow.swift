//
//  File.swift
//  
//
//  Created by Alan on 2022/7/13.
//

import Foundation

struct CorrectFlow: Logable {
    
    let publicHeaderFolders: [String]
    let folderFilters: [PathFilter]
    
    let correctingFolders: [String]
    
    var excludeTables: [String] = []
    
    var testMode: Bool = false
    var log: Bool = false
    
    init(projectDir: String,
         headersDirs: [String],
         exlcudedDirs: [String],
         relativeExcludedDirs: [String],
         excludeTables: [String]) {
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
        self.excludeTables = excludeTables
    }
    
    init(specificDirs: [String],
         headerDirs: [String],
         exlcudedDirs: [String],
         excludeTables: [String]) {
        self.correctingFolders = specificDirs
        self.publicHeaderFolders = headerDirs
        var folderFilters = [PathFilter]()
        if !exlcudedDirs.isEmpty {
            folderFilters.append(ExcludedFolderFilter(excludedDirs: exlcudedDirs))
        }
        self.folderFilters = folderFilters
        self.excludeTables = excludeTables
    }
    
    init(podDir: String,
         headerDir: String?,
         exlcudedDirs: [String],
         podName: String?,
         excludeTables: [String]) {
        self.correctingFolders = [podDir]
        self.publicHeaderFolders = [headerDir ?? podDir + "/Example/Pods/Headers/Public/"]
        
        var folderFilters = [PathFilter]()
        if !exlcudedDirs.isEmpty {
            folderFilters.append(ExcludedFolderFilter(excludedDirs: exlcudedDirs))
        }
        self.folderFilters = folderFilters
        
        if let excludeTable = podName {
            self.excludeTables.append(excludeTable)
        } else if let last = podDir.split(separator: "/").last {
            self.excludeTables.append(String(last))
        }
        self.excludeTables.append(contentsOf: excludeTables)
    }
    
    func run() throws {
        print("Start")
        print("Running...")
        // table maker
        let tableMaker = ImportTableMaker(publicHeaderFolders: self.publicHeaderFolders)
        tableMaker.excludeTables = excludeTables
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
