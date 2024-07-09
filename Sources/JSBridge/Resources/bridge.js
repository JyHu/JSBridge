// JSBridge 是一个模块，旨在简化 JavaScript 与客户端（OC、Swift）之间的通信。
// 它允许 JavaScript 调用客户端并在返回数据时接收数据。

// JSConnecter 是在 JSContext 中注册的对象，它使 JavaScript 能够调用 OC 或 Swift 方法。

// 定义一个模块，封装相关功能。
const JSBridge = (function () {
    // 日志等级
    //   debug = 0      /// 调试日志
    //   info = 1       /// 普通日志
    //   warning = 2    /// 警告信息
    //   error = 3      /// 错误信息
    var logLevel = 2;
    
    // 用于跟踪最后一个任务 ID 的私有变量。
    let lastTaskID = 0;
        
    // 与事件关联的所有回调对象的缓存。
    const callbackMap = {};

    // 模块暴露的公共方法。
    return {
        // 由 JS 调用与客户端交互的方法。
        // name: 协议名称
        // params: 参数
        // watch: 是否监听事件
        //   0: 仅用于通知，不会缓存回调信息
        //   1: 仅需要接收一次消息，接收后立即移除对应缓存
        //   2: 需要接收多次消息，需要主动取消订阅
        // callback: 回调方法
        call: function (name, params, watch, callback) {
            if (watch !== 0) {
                // 将回调信息存储在 callbackMap 对象中。
                callbackMap[lastTaskID] = { name, watch, callback };
            }
            
            // 这行代码使用了 ES6 对象字面量简写语法，等效于：
            //    Fella.call({
            //      name: name,
            //      params: params,
            //      taskID: lastTaskID
            //    });
            const arguments = { name, watch, taskID: lastTaskID };

            if (params !== null) {
                arguments['params'] = params;
            }

            // 将消息发送到客户端。
            JSConnecter.call(arguments);

            // 自增消息 ID。
            lastTaskID++;
        },
        // 由客户端调用通知 JS 的方法。
        // message: 消息
        //   - taskID: 任务 ID，在缓存中查找对应的回调缓存信息
        //   - result: 客户端处理的结果信息
        onReceive: function (message) {
            const { taskID, result } = message;
            if (taskID !== undefined && typeof taskID === "number" && taskID >= 0) {
                const callback = callbackMap[taskID];
                                
                if (callback !== undefined) {
                    // 移除一次性监听的回调信息。
                    if (callback.watch === 1) {
                        delete callbackMap[taskID];
                    }

                    // 调用回调方法。
                    callback.callback(result);
                }
            }
        },

        // 由客户端主动取消订阅的协议信息。
        // message: 消息
        //   - id: 任务 ID
        unwatch: function (message) {
            const { taskID } = message;

            if (taskID !== undefined) {
                // 删除订阅信息。
                delete callbackMap[taskID];
            }
        },
        
        // JS内部根据消息等级输出日志信息
        // lv: 消息等级
        // log: 输出的日志内容
        log: function (lv, log) {
            if (lv >= this.logLevel) {
                JSConnecter.showLog(lv, log);
            }
        }
    };
})();

// 更新日志输出等级
// level: 日志等级
function __onUpdateLogLevel__(level) {
    JSBridge.logLevel = level;
}

// 外部（JSContext）接收到消息时调用的回调方法。
// 消息格式必须为：
//   {
//       "taskID": xxx,
//       "result": xxx
//   }
function __onSyncReply__(message) {
    JSBridge.onReceive(message);
}

// 外部（JSContext）主动取消订阅时调用的回调方法。
// 消息格式必须为：
//   {
//       "taskID": xxx
//   }
function __unwatch__(message) {
    JSBridge.unwatch(message);
}

// 外部（JSContext）发起请求，由JS中异步处理，在处理完成后异步回调给外部
// 消息格式必须是：
//  {
//      "taskID": xxx,
//      "func": xxxx,
//      "watch": 0 | 1 | 2
//      "params": xxx
//  }
//
// 然后接收事件的方法必须有除了func以外的三个参数，如：
//   function exampleFunc(taskID, watch, params) {
//      // async operation
//      JSConnecter.asyncReply({"taskID": taskID, "result": "result"});
//   }
// 在一定异步处理后，通过asyncReply将结果回调到外部
function __onAsyncCall__(message) {
    const { taskID, func, watch, params } = message;
    
    if (func === undefined || taskID === undefined) {
        return;
    }
    
    // 使用对象的属性名动态调用函数
    if (typeof this[func] === 'function') {
        this[func](taskID, watch, params);
    } else {
        JSConnecter.showLog(0, "no func");
    }
}
