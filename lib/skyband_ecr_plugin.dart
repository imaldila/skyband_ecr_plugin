import 'dart:async';

import 'package:flutter/services.dart';

class SkybandEcrPlugin {
  static const MethodChannel _channel = MethodChannel('skyband_ecr_plugin');
  static const EventChannel _eventChannel = EventChannel('skyband_ecr_events');

  // Singleton instance
  static final SkybandEcrPlugin _instance = SkybandEcrPlugin._internal();
  factory SkybandEcrPlugin() => _instance;
  SkybandEcrPlugin._internal();

  // Stream controller for device status updates
  final _deviceStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get deviceStatusStream =>
      _deviceStatusController.stream;

  // Initialize the plugin
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initEcr');
      _eventChannel.receiveBroadcastStream().listen((event) {
        _deviceStatusController.add(Map<String, dynamic>.from(event));
      });
    } catch (e) {
      throw Exception('Failed to initialize Skyband ECR: $e');
    }
  }

  // Connect to device
  Future<bool> connectDevice(String ipAddress, int port) async {
    try {
      final bool result = await _channel.invokeMethod('connectDevice', {
        'ipAddress': ipAddress,
        'port': port,
      });
      return result;
    } catch (e) {
      throw Exception('Failed to connect device: $e');
    }
  }

  // Disconnect device
  Future<void> disconnectDevice() async {
    try {
      await _channel.invokeMethod('disconnectDevice');
    } catch (e) {
      throw Exception('Failed to disconnect device: $e');
    }
  }

  // Get device status
  Future<bool> getDeviceStatus() async {
    try {
      final bool status = await _channel.invokeMethod('getDeviceStatus');
      return status;
    } catch (e) {
      throw Exception('Failed to get device status: $e');
    }
  }

  // Initiate payment
  Future<Map<String, dynamic>> initiatePayment({
    required String dateFormat,
    required double amount,
    required bool printReceipt,
    required String ecrRefNum,
    required int transactionType,
    required bool signature,
  }) async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('initiatePayment', {
        'dateFormat': dateFormat,
        'amount': amount,
        'printReceipt': printReceipt,
        'ecrRefNum': ecrRefNum,
        'transactionType': transactionType,
        'signature': signature,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      throw Exception('Failed to initiate payment: $e');
    }
  }

  // Dispose
  void dispose() {
    _deviceStatusController.close();
  }

  // Get platform version
  Future<String?> getPlatformVersion() async {
    try {
      final String? version =
          await _channel.invokeMethod<String>('getPlatformVersion');
      return version;
    } catch (e) {
      throw Exception('Failed to get platform version: $e');
    }
  }

  // Perform direct transaction
  Future<Map<String, dynamic>> performTransaction({
    required String amount,
    required String terminalId,
    required String transactionType,
  }) async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('performTransaction', {
        'amount': amount,
        'terminalId': terminalId,
        'transactionType': transactionType,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      throw Exception('Failed to perform transaction: $e');
    }
  }
}
