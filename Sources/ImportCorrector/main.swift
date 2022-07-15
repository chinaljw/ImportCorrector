import Foundation

//CorrectImport.main()

class PodDefine {
    
    let defineName: String
    var pods: [String] = []
    
    init(defineName: String) {
        self.defineName = defineName
    }
}

do {
    var podsTable = [String: PodDefine]()
    let reg = try NSRegularExpression(pattern: "pod '.*?'")
    let line = "pod 'XMPaySDK',     :git => 'git@gitlab.ximalaya.com:iphone/XMPaySDK.git',      :commit => '77da2e8503b678a598c584a9ecd7c0ccd5d1a788'"
    let range = reg.rangeOfFirstMatch(in: line, range: .init(location: 0, length: line.count))
    if let range = Range(range, in: line) {
        var matched = String(line[range])
        matched.removeLast()
        matched.removeFirst(5)
        print(matched)
        let podName = matched.lowercased() + "_pods"
        var pods = podsTable[podName]
        if pods == nil {
            podsTable[matched] = .init(defineName: podName)
        }
        
        
        print(podName)
    }
} catch {
    print(error)
}
