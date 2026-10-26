import 'home_assistant_credentials.dart';

HomeAssistantCredentials createHomeAssistantCredentials(Duration timeout) =>
    _UnsupportedHomeAssistantCredentials();

class _UnsupportedHomeAssistantCredentials implements HomeAssistantCredentials {
  @override
  bool get supported => false;
  @override
  Future<List<HomeAssistantNetwork>> connectAndList(String url, String token,
          {bool allowUnencrypted = false}) async =>
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.unsupported);
  @override
  Future<String> fetchDataset(HomeAssistantNetwork selected) async =>
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.unsupported);
  @override
  void cancel() {}
}
