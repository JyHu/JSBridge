//
//  JSExportObject.swift
//  JSBridgeTests
//
//  Created by Jo on 2024/1/3.
//

import Foundation
import JavaScriptCore

/// 定义供 JavaScript 调用的协议
@objc private protocol JSExportDelegate: JSExport {
    /// JavaScript 调用的方法，用于将消息发送到本地
    func reply(_ message: Any?)
    
    /// 和asyncCall匹配使用的javascript方法，用于将结果从javascript中回传到native
    func asyncReply(_ message: Any?)
    
    /// 用于调试目的的 JavaScript 调用的方法
    func showLog(_ level: Int, _ message: Any?)
}

/// 本地与 JavaScript 交互的中间对象
public class JSExportObject {
    
    /// JS端输出日志的等级
    public enum LogLevel: Int {
        case debug = 0      /// 调试日志
        case info = 1       /// 普通日志
        case warning = 2    /// 警告信息
        case error = 3      /// 错误信息
        
        public init(rawValue: Int) {
            switch rawValue {
            case 3: self = .error
            case 2: self = .warning
            case 1: self = .info
            default: self = .debug
            }
        }
    }
    
    /// 枚举表示 JavaScript 消息订阅选项
    public enum Watch: Int {
        /// 仅用于通知，无需回复
        case notify = 0
        /// 仅接收一次消息，无需持续订阅
        case oncetime = 1
        /// 需要接收多次消息，需要持续订阅，需要由本地方主动取消订阅
        case monitor = 2
    }
    
    /// 结构体表示来自 JavaScript 的消息
    public struct Message {
        /// 消息名称，用于区分所需的操作
        public let name: String
        
        /// 消息 ID，在回复 JavaScript 消息时用于确定订阅是哪个；对于每个上下文，所有的 taskID 都是唯一的
        public let taskID: Int
        
        /// 当前消息事件的实际参数
        public let params: Any?
        
        /// 订阅模式
        public let watch: Watch
        
        /// 内部初始化方法
        fileprivate init?(message: Any?) {
            guard let message = message as? [String: Any] else { return nil }
            guard let name = message["name"] as? String,
                  let taskID = message["taskID"] as? Int,
                  let watchRawVal = message["watch"] as? Int,
                  let watch = Watch(rawValue: watchRawVal) else {
                return nil
            }
            
            self.name = name
            self.taskID = taskID
            self.params = message["params"]
            self.watch = watch
        }
    }
    
    /// JavaScript 中间对象，用于中转 JavaScript 消息，隐藏了一些方法
    private class Bridge: NSObject, JSExportDelegate {
        /// 由native发起的请求缓存对象
        struct Request {
            let name: String
            let watch: Watch
            let callback: ((Any?) -> Void)?
        }
        
        private var context: JSContext?
        
        /// 将收到的JS消息传递出去
        var callback: ((Message) -> Void)?
        
        /// 将收到的JS的日志信息传递出去
        var showLogBlock: ((LogLevel, Any?) -> Void)?
        
        /// 日志等级
        var logLevel: LogLevel = .warning {
            didSet {
                updateLogLevel()
            }
        }
        
        /// 缓存的native的所有请求
        var requests: [Int: Request] = [:]
        
        /// native发起请求的任务id，用于在每次发起请求的时候进行累加，确保所有的请求ID都是唯一的
        var lastestReqID: Int = 0
        
        // MARK: 资源加载
        
        /// 将 JavaScript 代码加载到 JSContext 中
        /// - Parameter javascript: JavaScript 代码
        func load(_ javascript: String) {
            context = nil
            context = JSContext()
            context?.evaluateScript(javascript)
            context?.setObject(self, forKeyedSubscript: "JSConnecter" as NSString)
        }
        
        /// 将日志等级同步到javascript中
        func updateLogLevel() {
            call("__onUpdateLogLevel__", arguments: logLevel.rawValue)
        }
        
        // MARK: 由JS发起请求，客户端异步处理
        
        /// 回调方法，将结果发送回 JavaScript
        /// - Parameters:
        ///   - taskID: 任务 ID
        ///   - message: 结果信息
        func callback(taskID: Int, message: Any) {
            let params: [String: Any] = [
                "taskID": taskID,
                "result": message
            ]
            
            call("__onSyncReply__", arguments: params)
        }
        
        /// 本地取消订阅方法，由本地方调用
        /// - Parameter taskID: 任务 ID
        func unwatch(taskID: Int) {
            call("__unwatch__", arguments: ["taskID": taskID])
        }
        
        /// JavaScript 调用本地发送消息的方法
        /// - Parameter message: 发送的消息
        func reply(_ message: Any?) {
            guard let message = Message(message: message) else { return }
            callback?(message)
        }
        
        // MARK: 由客户端发起请求，JS中异步处理
        
        /// 发起异步调用，由客户端发起到 JS 中进行异步处理
        /// - Parameters:
        ///   - function: 客户端调用的 JS 中的方法名
        ///   - watch: 订阅方式，默认为 .notify
        ///   - arguments: 方法参数
        ///   - callback: 接收回调的闭包
        func asyncCall(_ function: String, watch: JSExportObject.Watch = .notify, arguments: Any? = nil, callback: ((Any?) -> Void)? = nil) -> Int {
            
            defer {
                lastestReqID += 1
            }
            
            if watch != .notify {
                requests[lastestReqID] = Request(name: function, watch: watch, callback: callback)
            }
            
            var params: [String: Any] = [
                "taskID": lastestReqID,
                "func": function,
                "watch": watch.rawValue
            ]
            
            if let arguments {
                params["params"] = arguments
            }
            
            call("__onAsyncCall__", arguments: params)
            
            return lastestReqID
        }
        
        /// 收到 JS 中异步处理的回调
        /// - Parameter message: 回调结果
        func asyncReply(_ message: Any?) {
            guard let message = message as? [String: Any] else { return }
            guard let taskID = message["taskID"] as? Int else { return }
            guard let request = requests[taskID] else { return }
            
            if request.watch == .oncetime {
                requests.removeValue(forKey: taskID)
            }
            
            request.callback?(message["result"])
        }
        
        // MARK: 辅助操作方法
        
        /// JavaScript 调试方法
        /// - Parameter message: 调试信息
        func showLog(_ level: Int, _ message: Any?) {
            self.showLogBlock?(LogLevel(rawValue: level), message)
        }
        
        /// 调用指定 JavaScript 函数
        /// - Parameters:
        ///   - function: JavaScript 函数名
        ///   - arguments: 函数参数
        func call(_ function: String, arguments: Any?) {
            guard let jsfunc = context?.objectForKeyedSubscript(function), !jsfunc.isUndefined else { return }
            
            if let arguments {
                jsfunc.call(withArguments: [arguments])
            } else {
                jsfunc.call(withArguments: [])
            }
        }
    }
    
    /// Bridge 类的实例
    private var bridge = Bridge()
    
    /// 框架内基础的javascript
    private var javascript: String = ""
    
    /// 日志等级
    var logLevel: LogLevel {
        get { bridge.logLevel }
        set { bridge.logLevel = newValue }
    }
    
    /// 初始化方法，设置回调
    public init() {
        self.javascript = __loadJS__()
        
        self.bridge.callback = { [weak self] message in
            self?.distribute(message: message)
        }
        
        self.bridge.showLogBlock = { [weak self] level, message in
            self?.showLog(level, message)
        }
    }
    
    /// 分发消息，根据消息类型进行处理，所有子类都可以重写这个方法来管理自己的消息事件
    /// - Parameter message: JS 发送的消息
    public func distribute(message: Message) {
        if message.name == "showLog" {
            print("JSBridge \(message.name): \(String(describing: message.params))")
        }
        // Handle other message types if needed
    }
    
    /// 打印日志
    /// - Parameter message: 日志信息
    public func showLog(_ level: LogLevel, _ message: Any?) {
        guard let message else { return }
        print("JSBridge Debug Log: \(message)")
    }
}

// MARK: - Public Extensions

public extension JSExportObject {
    
    // MARK: JS资源加载方法
    
    /// 将 JavaScript 代码加载到 JSContext 中
    /// - Parameter javascript: JavaScript 代码
    func load(_ javascript: String) {
        bridge.load(javascript)
    }
    
    /// 拼接自定义的 JS 到协议内 JS
    /// - Parameter javascript: 自定义的 JavaScript 代码
    func append(_ javascript: String) {
        load(
        """
        \(self.javascript)
        
        \(javascript)
        """
        )
    }
    
    /// 调用指定 JavaScript 函数
    /// - Parameters:
    ///   - function: JavaScript 函数名
    ///   - arguments: 函数参数
    func call(_ function: String, arguments: Any?) {
        bridge.call(function, arguments: arguments)
    }
    
    /// 将结果发送回 JavaScript
    /// - Parameters:
    ///   - taskID: 任务 ID
    ///   - message: 结果信息
    func callback(taskID: Int, message: Any) {
        bridge.callback(taskID: taskID, message: message)
    }
    
    /// 本地取消订阅方法，由本地方调用
    /// - Parameter taskID: 任务 ID
    func unwatch(taskID: Int) {
        bridge.unwatch(taskID: taskID)
    }
    
    /// 由客户端发起请求到 JS 中进行异步处理
    /// - Parameters:
    ///   - function: 客户端调用的 JS 中的方法名
    ///   - watch: 订阅方式，默认为 .notify
    ///   - arguments: 方法参数
    ///   - callback: 接收回调的闭包
    @discardableResult func asyncCall(_ function: String, watch: JSExportObject.Watch = .notify, arguments: Any? = nil, callback: ((Any?) -> Void)? = nil) -> Int {
        return bridge.asyncCall(function, watch: watch, arguments: arguments, callback: callback)
    }
    
    /// 移除一个 request 的请求
    /// - Parameter taskID: 请求的 ID
    func remove(taskID: Int) {
        bridge.requests.removeValue(forKey: taskID)
    }
}

// MARK: - Private Methods

private func __loadJS__() -> String {
    #if COCOAPODS
    let bundle = Bundle.main
    #else
    let bundle = Bundle.module
    #endif
    
    guard let path = bundle.path(forResource: "bridge", ofType: "js"),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        return ""
    }
    
    return String(data: data, encoding: .utf8) ?? ""
}
