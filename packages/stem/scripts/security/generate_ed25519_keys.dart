import 'dart:convert';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final publicKey = (await keyPair.extractPublicKey()).bytes;

  final privateB64 = base64.encode(privateKey);
  final publicB64 = base64.encode(publicKey);

  print('STEM_SIGNING_ALGORITHM=ed25519');
  print('STEM_SIGNING_PUBLIC_KEYS=primary:$publicB64');
  print('STEM_SIGNING_PRIVATE_KEYS=primary:$privateB64');
  print('STEM_SIGNING_ACTIVE_KEY=primary');
}
