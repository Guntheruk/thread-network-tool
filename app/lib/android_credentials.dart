import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AndroidCredentialStatus {
  available,
  unavailable,
  missingSdk,
  notConfigured,
  localNetworkDisconnected,
  permissionDenied,
  cancelled,
  busy,
  timedOut,
  failure,
}

/// Available from a readiness check means Play services can receive a request.
/// It does not mean a preferred credential exists.
class AndroidCredentialResult {
  const AndroidCredentialResult(this.status, {this.datasetHex});

  final AndroidCredentialStatus status;
  final String? datasetHex;

  @override
  String toString() => 'AndroidCredentialResult(${status.name})';
}

class AndroidCredentials {
  AndroidCredentials({
    MethodChannel? channel,
    bool? supportedPlatform,
    this.availabilityTimeout = const Duration(seconds: 10),
    this.fetchTimeout = const Duration(seconds: 50),
  })  : _channel = channel ??
            const MethodChannel('thread_network/android_credentials'),
        _supportedPlatform = supportedPlatform ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final bool _supportedPlatform;
  final Duration availabilityTimeout;
  final Duration fetchTimeout;
  static int _nextOperation = 0;
  String? _activeOperationId;
  Completer<AndroidCredentialResult>? _cancellation;

  /// Checks service readiness only. This does not request credentials.
  Future<AndroidCredentialResult> availability() => _invoke('availability');

  /// Requests Google's consent UI. Call only after an explicit user action.
  Future<AndroidCredentialResult> fetchPreferred() async {
    if (!_supportedPlatform) {
      return const AndroidCredentialResult(AndroidCredentialStatus.unavailable);
    }
    if (_activeOperationId != null) {
      return const AndroidCredentialResult(AndroidCredentialStatus.busy);
    }
    final operationId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_nextOperation}';
    final cancellation = Completer<AndroidCredentialResult>();
    _activeOperationId = operationId;
    _cancellation = cancellation;
    try {
      final result = await Future.any([
        _invoke('fetchPreferred', operationId: operationId),
        cancellation.future,
      ]);
      if (result.status == AndroidCredentialStatus.timedOut) {
        unawaited(_cancelNative(operationId));
      }
      return result;
    } finally {
      if (_activeOperationId == operationId) {
        _activeOperationId = null;
        _cancellation = null;
      }
    }
  }

  /// Ends this provider's current fetch and invalidates any late response.
  Future<void> cancelPending() async {
    final operationId = _activeOperationId;
    if (operationId == null) return;
    _activeOperationId = null;
    _cancellation?.complete(
      const AndroidCredentialResult(AndroidCredentialStatus.cancelled),
    );
    _cancellation = null;
    await _cancelNative(operationId);
  }

  Future<void> _cancelNative(String operationId) async {
    try {
      await _channel.invokeMethod<void>(
        'cancelPending',
        {'operationId': operationId},
      ).timeout(const Duration(seconds: 1));
    } catch (_) {
      // The local future is already cancelled; native errors are never surfaced.
    }
  }

  Future<AndroidCredentialResult> _invoke(
    String method, {
    String? operationId,
  }) async {
    if (!_supportedPlatform) {
      return const AndroidCredentialResult(AndroidCredentialStatus.unavailable);
    }
    try {
      final response = await _channel
          .invokeMapMethod<String, dynamic>(
            method,
            operationId == null ? null : {'operationId': operationId},
          )
          .timeout(
              method == 'availability' ? availabilityTimeout : fetchTimeout);
      if (operationId != null && _activeOperationId != operationId) {
        return const AndroidCredentialResult(AndroidCredentialStatus.cancelled);
      }
      final status = _status(response?['status']);
      if (method == 'fetchPreferred' &&
          status == AndroidCredentialStatus.available) {
        final bytes = response?['dataset'];
        if (bytes is Uint8List && bytes.isNotEmpty && bytes.length <= 254) {
          final hex = bytes
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join();
          return AndroidCredentialResult(status, datasetHex: hex);
        }
        return const AndroidCredentialResult(AndroidCredentialStatus.failure);
      }
      return AndroidCredentialResult(status);
    } on TimeoutException {
      return const AndroidCredentialResult(AndroidCredentialStatus.timedOut);
    } on MissingPluginException {
      return const AndroidCredentialResult(AndroidCredentialStatus.unavailable);
    } on PlatformException catch (error) {
      // Never relay message, details, or stack trace from the native SDK.
      return AndroidCredentialResult(_status(error.code));
    } catch (_) {
      return const AndroidCredentialResult(AndroidCredentialStatus.failure);
    }
  }

  AndroidCredentialStatus _status(Object? code) => switch (code) {
        'available' => AndroidCredentialStatus.available,
        'unavailable' => AndroidCredentialStatus.unavailable,
        'missingSdk' => AndroidCredentialStatus.missingSdk,
        'notConfigured' => AndroidCredentialStatus.notConfigured,
        'localNetworkDisconnected' =>
          AndroidCredentialStatus.localNetworkDisconnected,
        'permissionDenied' => AndroidCredentialStatus.permissionDenied,
        'cancelled' => AndroidCredentialStatus.cancelled,
        'busy' => AndroidCredentialStatus.busy,
        'timedOut' => AndroidCredentialStatus.timedOut,
        _ => AndroidCredentialStatus.failure,
      };
}
