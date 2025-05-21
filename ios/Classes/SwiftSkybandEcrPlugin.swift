import Flutter
import UIKit
import SkyBandECRSDK

public class SwiftSkybandEcrPlugin: NSObject, FlutterPlugin, SocketConnectionDelegate {
    private var coreServices: SKBCoreServices?
    private var eventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "skyband_ecr_plugin", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "skyband_ecr_events", binaryMessenger: registrar.messenger())
        let instance = SwiftSkybandEcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(result: result)
        case "connectDevice":
            connectDevice(call: call, result: result)
        case "disconnectDevice":
            disconnectDevice(result: result)
        case "getDeviceStatus":
            getDeviceStatus(result: result)
        case "initiatePayment":
            initiatePayment(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func initialize(result: @escaping FlutterResult) {
        coreServices = SKBCoreServices.shareInstance()
        coreServices?.delegate = self
        result(nil)
    }
    
    private func connectDevice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let ipAddress = args["ipAddress"] as? String,
              let port = args["port"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "Invalid arguments for connectDevice",
                              details: nil))
            return
        }
        
        let portNumber = UInt(port)
        coreServices?.connectSocket(ipAddress, portNumber: portNumber)
        result(true)
    }
    
    private func disconnectDevice(result: @escaping FlutterResult) {
        coreServices?.disConnectSocket()
        result(nil)
    }
    
    private func getDeviceStatus(result: @escaping FlutterResult) {
        let status = coreServices?.connected ?? false
        result(status)
    }
    
    private func initiatePayment(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let dateFormat = args["dateFormat"] as? String,
              let amount = args["amount"] as? Double,
              let printReceipt = args["printReceipt"] as? Bool,
              let ecrRefNum = args["ecrRefNum"] as? String,
              let transactionType = args["transactionType"] as? Int,
              let signature = args["signature"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "Invalid arguments for initiatePayment",
                              details: nil))
            return
        }
        
        let request = "\(dateFormat);\(amount);\(printReceipt);\(ecrRefNum)!"
        coreServices?.doTCPIPTransaction(
            coreServices?.ipAdress,
            portNumber: coreServices?.portNumber ?? 0,
            requestData: request,
            transactionType: Int32(transactionType),
            signature: signature ? "true" : "false"
        )
        
        // Store the result callback to be called when the payment is complete
        self.paymentResult = result
    }
    
    // MARK: - SocketConnectionDelegate
    
    private var paymentResult: FlutterResult?
    
    public func socketConnectionStream(_ connection: SKBCoreServices!, didReceiveData responseData: NSMutableDictionary!) {
        if let result = paymentResult {
            result(responseData as? [String: Any])
            paymentResult = nil
        }
        
        // Also update the event sink if needed
        eventSink?(["response": responseData])
    }
    
    public func socketConnectionStreamDidFail(toConnect connection: SKBCoreServices!) {
        eventSink?(["status": "disconnected"])
    }
    
    public func socketConnectionStreamDidConnect(_ connection: SKBCoreServices!) {
        eventSink?(["status": "connected"])
    }
    
    public func socketConnectionStreamDidDisconnect(_ connection: SKBCoreServices!, willReconnectAutomatically: Bool) {
        eventSink?(["status": "disconnected", "willReconnect": willReconnectAutomatically])
    }
}

// MARK: - FlutterStreamHandler

extension SwiftSkybandEcrPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
} 
