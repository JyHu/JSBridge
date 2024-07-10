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
    /// JavaScript 调用 `call: function (name, params, watch, callback)` 时会在
    /// bridge内部调用的方法，用于将消息发送到swift
    /// message为数据字典，包含如下字段：
    ///     name: 协议名称
    ///     params: 参数
    ///     watch: 是否监听事件
    ///       0: 仅用于通知，不会缓存回调信息
    ///       1: 仅需要接收一次消息，接收后立即移除对应缓存
    ///       2: 需要接收多次消息，需要主动取消订阅
    func call(_ message: Any?)
    
    /// 和asyncCall匹配使用的javascript方法，用于将结果从javascript中回传到native
    /// 比如swift侧调用了asyncCall，那么在JS中会调用到对应的方法中，在该方法内执行一定时间
    /// 获得结果后，可以通过asyncReply将结果传回swift，swift侧会查找requests缓存，并从中
    /// 找到对应的请求，然后根据请求内缓存的block来回传数据
    ///
    /// message必须为字典类型，且必须包含taskID字段，该字段是在调用asyncCall时传入的，用来
    /// 查找唯一对应的请求，然后结果用"result"作为key返回
    func asyncReply(_ message: Any?)
    
    /// 用于调试目的的 JavaScript 调用的方法
    func showLog(_ level: Int, _ message: Any?)
    
    /// 延时执行某个方法
    func asyncAfter(_ seconds: NSNumber, _ callback: JSValue?)
    
    /// 移除一个JS侧的订阅
    func remove(_ taskID: NSNumber?)
}

/// 本地与 JavaScript 交互的中间对象
open class JSExportObject {
    
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
        
        /// 移除任务
        var removeTask: ((Int) -> Void)?
        
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
        
        /// JS中发起请求的所有消息
        /// key: taskID
        /// value: Message
        var messages: [Int: Message] = [:]
        
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
        
        /// JavaScript 调用本地发送消息的方法
        /// - Parameter message: 发送的消息
        func call(_ message: Any?) {
            if let message = Message(message: message) {
                if message.watch != .notify {
                    messages[message.taskID] = message
                }
                
                callback?(message)
            }
        }
        
        /// native方回调方法，将call(_:)请求结果发送回 JavaScript
        /// - Parameters:
        ///   - taskID: 任务 ID
        ///   - message: 结果信息
        func callback(taskID: Int, message: Any) {
            let params: [String: Any] = [
                "taskID": taskID,
                "result": message
            ]
            
            if messages[taskID]?.watch == .oncetime {
                messages.removeValue(forKey: taskID)
            }
            
            call("__onReply__", arguments: params)
        }
        
        func callback(taskName: String, message: Any) {
            for (taskID, cachedMessage) in messages {
                if cachedMessage.name == taskName {
                    let params: [String: Any] = [
                        "taskID": cachedMessage.taskID,
                        "result": message
                    ]
                    
                    call("__onReply__", arguments: params)
                    
                    if cachedMessage.watch == .oncetime {
                        messages.removeValue(forKey: taskID)
                    }
                }
            }
        }
        
        func remove(_ taskID: NSNumber?) {
            guard let taskID = taskID?.intValue else { return }
            messages.removeValue(forKey: taskID)
            removeTask?(taskID)
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
            
            // 查找请求
            guard let request = requests[taskID] else { return }
            
            // 调用回调
            request.callback?(message["result"])
            
            // 如果是一次性订阅，则移除请求
            if request.watch == .oncetime {
                requests.removeValue(forKey: taskID)
            }
        }
        
        
        /// native侧发起请求，在不需要的时候移除请求
        /// 移除请求的时候需要移除本地request的缓存，同时告知JS侧取消订阅；
        /// 一般这种操作适用于Swift侧发起一次请求，但是需要JS侧长时间、多次返回数据的情况。
        func unwatchNativeRequestWith(taskID: Int) {
            requests.removeValue(forKey: taskID)
            call("__removeNativeTask__", arguments: ["taskID": taskID])
        }
        
        // MARK: 辅助操作方法
        
        // MARK: 日志输出
        
        /// JS 调用本地日志输出的方法
        /// - Parameters:
        ///   - level: 日志等级
        ///   - message: 日志内容
        func showLog(_ level: Int, _ message: Any?) {
            self.showLogBlock?(LogLevel(rawValue: level), message)
        }
        
        // MARK: 延时调用
        
        /// 延时调用某个方法
        /// - Parameters:
        ///   - seconds: 延时秒数
        ///   - callback: 延时结束后的回调方法
        func asyncAfter(_ seconds: NSNumber, _ callback: JSValue?) {
            guard let callback = callback else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds.doubleValue) {
                callback.call(withArguments: nil)
            }
        }
        
        // MARK: 内部调用 JavaScript
        
        /// 调用 JavaScript 方法
        /// - Parameters:
        ///   - function: 方法名
        ///   - arguments: 参数列表
        func call(_ function: String, arguments: Any? = nil) {
            let args = arguments != nil ? [arguments!] : []
            context?.objectForKeyedSubscript(function)?.call(withArguments: args)
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
    
    /// 回传log内容的block
    public var showLogAction: ((LogLevel, Any?) -> Void)?
    
    /// 回传消息内容的block
    public var distributeCallback: ((Message) -> Void)?
    
    /// H5移除一个请求，告知native方移除对应的请求
    public var removeTaskAction: ((Int) -> Void)?
    
    /// 获取当前js这边发过来的所有活跃状态的消息
    public var messages: [Int: Message] {
        self.bridge.messages
    }
    
    /// 初始化方法，设置回调
    public init() {
        self.javascript = __loadJS__()
        
        self.bridge.callback = { [weak self] message in
            self?.distribute(message: message)
            self?.distributeCallback?(message)
        }
        
        self.bridge.showLogBlock = { [weak self] level, message in
            self?.showLog(level, message)
            self?.showLogAction?(level, message)
        }
        
        self.bridge.removeTask = { [weak self] taskID in
            self?.removeTaskAction?(taskID)
            self?.removeTask(taskID)
        }
    }
    
    /// 分发消息，根据消息类型进行处理，所有子类都可以重写这个方法来管理自己的消息事件
    /// - Parameter message: JS 发送的消息
    open func distribute(message: Message) {
        if message.name == "showLog" {
            print("JSBridge \(message.name): \(String(describing: message.params))")
        }
        // Handle other message types if needed
    }
    
    /// 打印日志
    /// - Parameter message: 日志信息
    open func showLog(_ level: LogLevel, _ message: Any?) {
        guard let message else { return }
        print("JSBridge Debug Log: \(message)")
    }
    
    /// H5移除了一个任务，由子类继承重写
    open func removeTask(_ taskID: Int) {
        bridge.messages.removeValue(forKey: taskID)
    }
}

// MARK: - Public Extensions

public extension JSExportObject {
    
    // MARK: JS资源加载方法
    
    /// 将 JavaScript 代码加载到 JSContext 中
    /// - Parameter javascript: JavaScript 代码
    func load(_ javascript: String) {
        bridge.requests.removeAll()
        
        bridge.load(javascript)
    }
    
    /// 拼接自定义的 JS 到协议内 JS
    /// - Parameter javascript: 自定义的 JavaScript 代码
    func append(_ javascript: String) {
        bridge.requests.removeAll()
        
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
        bridge.unwatchNativeRequestWith(taskID: taskID)
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
