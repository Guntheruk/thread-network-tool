import 'dart:io';

/// Disposable test CA and DNS-only localhost leaf. Never installed into OS trust.
class HaTlsFixture {
  HaTlsFixture(this.directory, this.serverContext, this.clientContext);
  final Directory directory;
  final SecurityContext serverContext;
  final SecurityContext clientContext;

  static Future<HaTlsFixture> create() async {
    final directory = await Directory.systemTemp.createTemp('tnt-ha-test-ca-');
    Future<void> openssl(List<String> args) async {
      final result =
          await Process.run('openssl', args, workingDirectory: directory.path);
      if (result.exitCode != 0) {
        throw StateError('Synthetic TLS fixture generation failed');
      }
    }

    try {
      await openssl([
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '1',
        '-keyout',
        'ca.key',
        '-out',
        'ca.pem',
        '-subj',
        '/CN=Synthetic HA Test CA',
        '-addext',
        'basicConstraints=critical,CA:TRUE',
        '-addext',
        'keyUsage=critical,keyCertSign,cRLSign'
      ]);
      await openssl([
        'req',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        'server.key',
        '-out',
        'server.csr',
        '-subj',
        '/CN=localhost'
      ]);
      await File('${directory.path}/server.ext').writeAsString(
          'subjectAltName=DNS:localhost\nbasicConstraints=critical,CA:FALSE\n'
          'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n');
      await openssl([
        'x509',
        '-req',
        '-in',
        'server.csr',
        '-CA',
        'ca.pem',
        '-CAkey',
        'ca.key',
        '-CAcreateserial',
        '-out',
        'server.pem',
        '-days',
        '1',
        '-extfile',
        'server.ext'
      ]);
      final serverContext = SecurityContext()
        ..useCertificateChain('${directory.path}/server.pem')
        ..usePrivateKey('${directory.path}/server.key');
      final clientContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('${directory.path}/ca.pem');
      return HaTlsFixture(directory, serverContext, clientContext);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> close() => directory.delete(recursive: true);
}
