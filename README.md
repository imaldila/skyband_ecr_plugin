# SkyBand ECR Plugin

A Flutter plugin for integrating SkyBand ECR devices.

## Features

- Initialize Skyband ECR SDK
- Connect to payment terminal
- Disconnect from payment terminal
- Get terminal connection status
- Initiate payment transactions
- Handle payment responses
- Monitor terminal connection status

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  skyband_ecr_plugin:
    git:
      url: https://github.com/imaldila/skyband_ecr_plugin.git
      ref: main
```

## iOS Setup

The plugin includes the SkyBandECRSDK (version 3.5.0) as a framework dependency. No additional setup is required.

## Requirements

- iOS 12.0 or later
- Flutter 1.20.0 or later
- SkyBandECRSDK 3.5.0

## Usage

```dart
import 'package:skyband_ecr_plugin/skyband_ecr_plugin.dart';

// Initialize the plugin
final ecrPlugin = SkybandEcrPlugin();
await ecrPlugin.initialize();

// Connect to device
bool connected = await ecrPlugin.connectDevice('192.168.1.100', 9100);

// Listen to device status updates
ecrPlugin.deviceStatusStream.listen((status) {
  print('Device status: $status');
});

// Initiate payment
final result = await ecrPlugin.initiatePayment(
  dateFormat: 'YYYYMMDD',
  amount: 100.00,
  printReceipt: true,
  ecrRefNum: 'REF123',
  transactionType: 1,
  signature: true,
);

// Disconnect device
await ecrPlugin.disconnectDevice();
```

## Error Handling

The plugin throws exceptions with descriptive messages when operations fail. Always wrap plugin calls in try-catch blocks to handle potential errors:

```dart
try {
  await ecrPlugin.connectDevice('192.168.1.100', 9100);
} catch (e) {
  print('Failed to connect: $e');
}
```

## Platform Support

Currently, this plugin only supports iOS platform.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

