//
//  File.swift
//  
//
//  Created by Jo on 2024/1/6.
//

@testable import JSBridge

class TestableBridge: JSExportObject {
    override init() {
        super.init()
    }
    
    var showLogCallback: ((JSExportObject.LogLevel, Any?) -> Void)?
    
    override func showLog(_ level: JSExportObject.LogLevel, _ message: Any?) {
        showLogCallback?(level, message)
    }
}
