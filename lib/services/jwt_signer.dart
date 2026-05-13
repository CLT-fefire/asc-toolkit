import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// App Store Connect API용 ES256 JWT 생성.
/// p8 키는 `-----BEGIN PRIVATE KEY-----` PKCS#8 PEM 형식.
class JwtSigner {
  String sign({
    required String issuerId,
    required String keyId,
    required String p8Pem,
    Duration ttl = const Duration(minutes: 18),
  }) {
    final now = DateTime.now();
    final exp = now.add(ttl);

    final jwt = JWT(
      {
        'iss': issuerId,
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
        'aud': 'appstoreconnect-v1',
      },
      header: {
        'alg': 'ES256',
        'kid': keyId,
        'typ': 'JWT',
      },
    );

    return jwt.sign(
      ECPrivateKey(p8Pem),
      algorithm: JWTAlgorithm.ES256,
    );
  }
}
