import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppleCredentialStatus {
  available,
  unavailable,
  noCredentials,
  permissionDenied,
  accessNotConfigured,
  timedOut,
  cancelled,
  inProgress,
  failure,
}

/// A dataset is present only after a successful, user-initiated fetch.
class AppleCredentialResult {
  const AppleCredentialResult(this.status, {this.datasetHex});

  final AppleCredentialStatus status;
  final String? datasetHex;
}

class AppleCredentials {
  static int _nextRequestId = 0;

  AppleCredentials({
    MethodChannel? channel,
    bool? supportedPlatform,
    this.availabilityTimeout = const Duration(seconds: 10),
    this.fetchTimeout = const Duration(seconds: 60),
  })  : _channel =
            channel ?? const MethodChannel('thread_network/apple_credentials'),
        _supportedPlatform = supportedPlatform ??
            (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.macOS ||
                    defaultTargetPlatform == TargetPlatform.iOS));

  final MethodChannel _channel;
  final bool _supportedPlatform;
  final Duration availabilityTimeout;
  final Duration fetchTimeout;
  int? _activeFetchId;
  Completer<void>? _activeCancellation;

  /// Checks whether Apple's preferred network exists. Never requests secrets.
  Future<AppleCredentialResult> availability() => _invoke('availability');

  /// May show the system consent prompt. Call only from an explicit UI action.
  Future<AppleCredentialResult> fetchPreferred() async {
    if (!_supportedPlatform) {
      return const AppleCredentialResult(AppleCredentialStatus.unavailable);
    }
    if (_activeFetchId != null) {
      return const AppleCredentialResult(AppleCredentialStatus.inProgress);
    }
    final requestId = ++_nextRequestId;
    final cancellation = Completer<void>();
    _activeFetchId = requestId;
    _activeCancellation = cancellation;
    try {
      final response = await Future.any<Map<String, dynamic>?>([
        _channel.invokeMapMethod<String, dynamic>(
            'fetchPreferred', {'requestId': requestId}),
        cancellation.future.then((_) => null),
      ]).timeout(fetchTimeout);
      if (_activeFetchId != requestId) {
        return const AppleCredentialResult(AppleCredentialStatus.cancelled);
      }
      return _decode(response, fetch: true);
    } on TimeoutException {
      await _cancelFetch(requestId);
      return const AppleCredentialResult(AppleCredentialStatus.timedOut);
    } on MissingPluginException {
      return const AppleCredentialResult(AppleCredentialStatus.unavailable);
    } on PlatformException catch (error) {
      return AppleCredentialResult(_platformErrorStatus(error.code));
    } catch (_) {
      return const AppleCredentialResult(AppleCredentialStatus.failure);
    } finally {
      if (_activeFetchId == requestId) {
        _activeFetchId = null;
        _activeCancellation = null;
      }
    }
  }

  /// Invalidates the current request in the native bridge before discarding it.
  Future<void> cancelFetch() async {
    final requestId = _activeFetchId;
    if (requestId == null) return;
    await _cancelFetch(requestId);
  }

  Future<void> _cancelFetch(int requestId) async {
    if (_activeFetchId == requestId) {
      _activeFetchId = null;
      _activeCancellation?.complete();
      _activeCancellation = null;
    }
    try {
      await _channel.invokeMethod<void>(
        'cancelFetch',
        {'requestId': requestId},
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      // A missing bridge or a late reply never exposes platform details.
    }
  }

  Future<AppleCredentialResult> _invoke(String method) async {
    if (!_supportedPlatform) {
      return const AppleCredentialResult(AppleCredentialStatus.unavailable);
    }
    try {
      final response = await _channel
          .invokeMapMethod<String, dynamic>(method)
          .timeout(
              method == 'availability' ? availabilityTimeout : fetchTimeout);
      return _decode(response, fetch: false);
    } on TimeoutException {
      return const AppleCredentialResult(AppleCredentialStatus.timedOut);
    } on MissingPluginException {
      return const AppleCredentialResult(AppleCredentialStatus.unavailable);
    } on PlatformException catch (error) {
      return AppleCredentialResult(_platformErrorStatus(error.code));
    } catch (_) {
      return const AppleCredentialResult(AppleCredentialStatus.failure);
    }
  }

  AppleCredentialResult _decode(Map<String, dynamic>? response,
      {required bool fetch}) {
    final status = switch (response?['status']) {
      'available' => AppleCredentialStatus.available,
      'unavailable' => AppleCredentialStatus.unavailable,
      'noCredentials' => AppleCredentialStatus.noCredentials,
      'permissionDenied' => AppleCredentialStatus.permissionDenied,
      'accessNotConfigured' => AppleCredentialStatus.accessNotConfigured,
      'timedOut' => AppleCredentialStatus.timedOut,
      'cancelled' => AppleCredentialStatus.cancelled,
      'inProgress' => AppleCredentialStatus.inProgress,
      _ => AppleCredentialStatus.failure,
    };
    if (fetch && status == AppleCredentialStatus.available) {
      final bytes = response?['dataset'];
      if (bytes is Uint8List && bytes.isNotEmpty && bytes.length <= 254) {
        final hex =
            bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        return AppleCredentialResult(status, datasetHex: hex);
      }
      return const AppleCredentialResult(AppleCredentialStatus.failure);
    }
    return AppleCredentialResult(status);
  }

  AppleCredentialStatus _platformErrorStatus(String code) {
    // Never expose the platform message or details: they may contain secrets.
    return switch (code) {
      'permissionDenied' => AppleCredentialStatus.permissionDenied,
      'accessNotConfigured' => AppleCredentialStatus.accessNotConfigured,
      'noCredentials' => AppleCredentialStatus.noCredentials,
      'unavailable' => AppleCredentialStatus.unavailable,
      'timedOut' => AppleCredentialStatus.timedOut,
      'cancelled' => AppleCredentialStatus.cancelled,
      'inProgress' => AppleCredentialStatus.inProgress,
      _ => AppleCredentialStatus.failure,
    };
  }
}
