import Flutter
import UIKit

#if SIMULATOR
// Simulator stub for SKBCoreServices
class SKBCoreServices: NSObject {
    static func shared() -> SKBCoreServices {
        return SKBCoreServices()
    }
    
    func initEcrTerminal() -> Bool {
        print("SIMULATOR: SKBCoreServices initEcrTerminal called")
        return true
    }
    
    func performTransaction(_ transaction: [AnyHashable: Any], completion: @escaping ([AnyHashable: Any]) -> Void) {
        print("SIMULATOR: SKBCoreServices performTransaction called")
        let response: [String: Any] = [
            "status": "success",
            "message": "Simulator mock response",
            "responseCode": "00",
            "amount": "1000",
            "transactionId": "SIM12345",
            "cardType": "VISA",
            "maskedPan": "************1234"
        ]
        completion(response as [AnyHashable : Any])
    }
    
    // Stub implementations for additional methods
    var connected: Bool = false
    var ipAdress: String = "127.0.0.1"
    var portNumber: UInt = 0
    
    func connectSocket(_ ipAddress: String, portNumber: UInt) {
        print("SIMULATOR: connectSocket called with IP: \(ipAddress) and port: \(portNumber)")
        self.ipAdress = ipAddress
        self.portNumber = portNumber
        self.connected = true
    }
    
    func disConnectSocket() {
        print("SIMULATOR: disConnectSocket called")
        self.connected = false
    }
    
    func doTCPIPTransaction(_ ipAddress: String?, portNumber: UInt, requestData: String, transactionType: Int32, signature: String) {
        print("SIMULATOR: doTCPIPTransaction called")
        print("  - IP: \(ipAddress ?? "nil"), Port: \(portNumber)")
        print("  - Request: \(requestData)")
        print("  - Transaction Type: \(transactionType)")
        print("  - Signature: \(signature)")
    }
}

// Stub protocol for simulator
protocol SocketConnectionDelegate: AnyObject {
    func socketConnectionStream(_ connection: SKBCoreServices!, didReceiveData responseData: NSMutableDictionary!)
    func socketConnectionStreamDidFail(toConnect connection: SKBCoreServices!)
    func socketConnectionStreamDidConnect(_ connection: SKBCoreServices!)
    func socketConnectionStreamDidDisconnect(_ connection: SKBCoreServices!, willReconnectAutomatically: Bool)
}
#else
import SkyBandECRSDK
#endif

public class SwiftSkybandEcrPlugin: NSObject, FlutterPlugin {
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
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "initEcr":
            initializeEcr(result: result)
            
        case "performTransaction":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments invalid", details: nil))
                return
            }
            performTransaction(args: args, result: result)
            
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
    
    private func initializeEcr(result: @escaping FlutterResult) {
        coreServices = SKBCoreServices.shared()
        let initialized = coreServices?.initEcrTerminal() ?? false
        result(initialized)
    }
    
    private func performTransaction(args: [String: Any], result: @escaping FlutterResult) {
        guard let amount = args["amount"] as? String,
              let terminalId = args["terminalId"] as? String,
              let transactionType = args["transactionType"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required parameters", details: nil))
            return
        }
        
        let transactionParams: [String: Any] = [
            "amount": amount,
            "terminalId": terminalId,
            "transactionType": transactionType
        ]
        
        coreServices?.performTransaction(transactionParams as [AnyHashable : Any]) { response in
            result(response)
        }
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
        result(true)
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
        let signatureStr = signature ? "true" : "false"
        
        coreServices?.doTCPIPTransaction(
            coreServices?.ipAdress,
            portNumber: coreServices?.portNumber ?? 0,
            requestData: request,
            transactionType: Int32(transactionType),
            signature: signatureStr
        )
        
        #if SIMULATOR
        // In simulator mode, immediately return a success response
        let response: [String: Any] = [
            "status": "success",
            "message": "Payment processed in simulator",
            "amount": String(amount),
            "referenceNumber": ecrRefNum,
            "transactionId": "SIM\(Int.random(in: 10000...99999))"
        ]
        result(response)
        #else
        // Store the result callback to be called when the payment is complete
        self.paymentResult = result
        #endif
    }
    
    #if SIMULATOR
    // Mock implementation for simulator
    private var paymentResult: FlutterResult?
    #else
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
    #endif
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
