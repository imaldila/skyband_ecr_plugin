import Flutter
import UIKit

#if SIMULATOR
// Simulator stub for SKBCoreServices that matches the real SDK method names
class SKBCoreServices: NSObject {
    static func shareInstance() -> SKBCoreServices {
        return SKBCoreServices()
    }
    
    // Delegate property
    weak var delegate: SocketConnectionDelegate?
    
    // Properties from the real SDK
    var connected: Bool = false
    var ipAdress: String = "127.0.0.1"
    var portNumber: UInt = 0
    var shouldReconnectAutomatically: Bool = false
    var reconnectTimeInterval: TimeInterval = 5.0
    var timeoutTimeInterval: TimeInterval = 30.0
    
    // Stub of real SDK method for backward compatibility
    func initEcrTerminal() -> Bool {
        print("SIMULATOR: initEcrTerminal called (stub method)")
        return true
    }
    
    // Stub of real SDK method for backward compatibility
    func performTransaction(_ transaction: [AnyHashable: Any], completion: @escaping ([AnyHashable: Any]) -> Void) {
        print("SIMULATOR: performTransaction called (stub method)")
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
    
    // Real SDK methods
    func connectSocket(_ ipAddress: String, portNumber: UInt) {
        print("SIMULATOR: connectSocket called with IP: \(ipAddress) and port: \(portNumber)")
        self.ipAdress = ipAddress
        self.portNumber = portNumber
        self.connected = true
        
        // Notify delegate
        delegate?.socketConnectionStreamDidConnect?(self)
    }
    
    func disConnectSocket() {
        print("SIMULATOR: disConnectSocket called")
        self.connected = false
        
        // Notify delegate
        delegate?.socketConnectionStreamDidDisconnect?(self, willReconnectAutomatically: shouldReconnectAutomatically)
    }
    
    func doTCPIPTransaction(_ ipAddress: String?, portNumber: UInt, requestData: String, transactionType: Int32, signature: String) {
        print("SIMULATOR: doTCPIPTransaction called")
        print("  - IP: \(ipAddress ?? "nil"), Port: \(portNumber)")
        print("  - Request: \(requestData)")
        print("  - Transaction Type: \(transactionType)")
        print("  - Signature: \(signature)")
        
        // Create a simulated response
        let responseData = NSMutableDictionary()
        responseData["status"] = "success"
        responseData["message"] = "Transaction processed in simulator"
        responseData["amount"] = requestData.components(separatedBy: ";").dropFirst().first
        responseData["transactionId"] = "SIM\(Int.random(in: 10000...99999))"
        
        // Wait a bit to simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.delegate?.socketConnectionStream?(self, didReceiveData: responseData)
        }
    }
}

// Simulator stub for SocketConnectionDelegate that matches the real protocol
@objc protocol SocketConnectionDelegate: AnyObject {
    @objc optional func socketConnectionStream(_ connection: SKBCoreServices, didReceiveData responseData: NSMutableDictionary)
    @objc optional func socketConnectionStreamDidConnect(_ connection: SKBCoreServices)
    @objc optional func socketConnectionStreamDidDisconnect(_ connection: SKBCoreServices, willReconnectAutomatically: Bool)
    @objc optional func socketConnectionStream(_ connection: SKBCoreServices, didSendString string: String)
    @objc optional func socketConnectionStreamDidFailToConnect(_ connection: SKBCoreServices)
}
#else
// Try both import formats to ensure compatibility
@import SkyBandECRSDK;
#endif

public class SwiftSkybandEcrPlugin: NSObject, FlutterPlugin, SocketConnectionDelegate {
    private var coreServices: SKBCoreServices?
    private var eventSink: FlutterEventSink?
    private var paymentResult: FlutterResult?
    
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
        #if SIMULATOR
        coreServices = SKBCoreServices.shareInstance()
        coreServices?.delegate = self
        let initialized = coreServices?.initEcrTerminal() ?? false
        #else
        // The actual SDK uses `shareInstance` (not `shared`)
        coreServices = SKBCoreServices.shareInstance()
        coreServices?.delegate = self
        let initialized = true
        #endif
        result(initialized)
    }
    
    private func performTransaction(args: [String: Any], result: @escaping FlutterResult) {
        guard let amount = args["amount"] as? String,
              let terminalId = args["terminalId"] as? String,
              let transactionType = args["transactionType"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required parameters", details: nil))
            return
        }
        
        #if SIMULATOR
        let transactionParams: [String: Any] = [
            "amount": amount,
            "terminalId": terminalId,
            "transactionType": transactionType
        ]
        
        coreServices?.performTransaction(transactionParams as [AnyHashable : Any]) { response in
            result(response)
        }
        #else
        // For real device, we use doTCPIPTransaction from the SDK
        let dateFormat = "YYYYMMDD"
        let amountDouble = Double(amount) ?? 0.0
        let ecrRefNum = "REF" + String(Int.random(in: 10000...99999))
        
        let request = "\(dateFormat);\(amountDouble);true;\(ecrRefNum)!"
        let transactionTypeInt = Int(transactionType) ?? 1
        
        coreServices?.doTCPIPTransaction(
            coreServices?.ipAdress,
            portNumber: coreServices?.portNumber ?? 0,
            requestData: request,
            transactionType: Int32(transactionTypeInt),
            signature: "false"
        )
        
        // Store the result callback to be called when the payment is complete
        self.paymentResult = result
        #endif
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
        #if SIMULATOR
        coreServices?.connectSocket(ipAddress, portNumber: portNumber)
        #else
        // The real SDK might have a different method name
        coreServices?.connectSocket(ipAddress, portNumber: portNumber)
        #endif
        result(true)
    }
    
    private func disconnectDevice(result: @escaping FlutterResult) {
        #if SIMULATOR
        coreServices?.disConnectSocket()
        #else
        coreServices?.disConnectSocket()
        #endif
        result(true)
    }
    
    private func getDeviceStatus(result: @escaping FlutterResult) {
        #if SIMULATOR
        let status = coreServices?.connected ?? false
        #else
        let status = coreServices?.connected ?? false
        #endif
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

// Implementation of SocketConnectionDelegate for both simulator and real builds
extension SwiftSkybandEcrPlugin {
    // For simulator builds, we need these to be marked with @objc and be optional
    // For real device builds, these match the actual SDK methods
    
    @objc public func socketConnectionStream(_ connection: SKBCoreServices, didReceiveData responseData: NSMutableDictionary) {
        if let result = paymentResult {
            result(responseData as? [String: Any])
            paymentResult = nil
        }
        
        // Also update the event sink if needed
        eventSink?(["response": responseData])
    }
    
    @objc public func socketConnectionStreamDidFailToConnect(_ connection: SKBCoreServices) {
        eventSink?(["status": "disconnected"])
    }
    
    @objc public func socketConnectionStreamDidConnect(_ connection: SKBCoreServices) {
        eventSink?(["status": "connected"])
    }
    
    @objc public func socketConnectionStreamDidDisconnect(_ connection: SKBCoreServices, willReconnectAutomatically: Bool) {
        eventSink?(["status": "disconnected", "willReconnect": willReconnectAutomatically])
    }
    
    @objc public func socketConnectionStream(_ connection: SKBCoreServices, didSendString string: String) {
        // Optional method implementation
        print("Did send string: \(string)")
    }
} 
