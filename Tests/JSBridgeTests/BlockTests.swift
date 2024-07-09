//
//  File.swift
//  
//
//  Created by hujinyou on 2024/7/8.
//

import XCTest
import JavaScriptCore

@objc protocol JSExportDelegate: JSExport {
    func sleep(_ seconds: NSNumber, _ callback: JSValue?)
    func showLog(_ message: Any?)
}

@objc class JSBridge: NSObject, JSExportDelegate {
    var logBlock: ((Any?) -> Void)?
    
    func sleep(_ seconds: NSNumber, _ callback: JSValue?) {
        let delay = DispatchTime.now() + .milliseconds(Int(truncating: seconds) * 1000)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            let resp = callback?.call(withArguments: ["Done"])
        }
    }
    
    func showLog(_ message: Any?) {
        print(message)
        logBlock?(message)
    }
}


final class BlockTests: XCTestCase {
    var context: JSContext!

    func testBlock() throws {
        let expectation = expectation(description: "block")
        
        context = JSContext()

        // 设置 JSBridge 对象
        let bridge = JSBridge()
        bridge.logBlock = { message in
            if message as? String == "Done" {
                expectation.fulfill()
            }
        }
        
        context.setObject(bridge, forKeyedSubscript: "JSBridge" as NSString)
        
        // 设置异常处理
        context.exceptionHandler = { context, exception in
            print("JS Error: \(String(describing: exception))")
        }

        // 加载并评估 JavaScript 代码
        let jsSource = """
        function testBlock(message) {
            JSBridge.sleep(0.5, function(res) {
                JSBridge.showLog(res);
            });
            JSBridge.showLog(message);
        }
        """
        
        context.evaluateScript(jsSource)
        
        // 调用 JavaScript 函数
        let testFunction = context.objectForKeyedSubscript("testBlock")
        testFunction?.call(withArguments: ["This is a test message"])
        
        
        
        wait(for: [expectation], timeout: 2)
    }
}
