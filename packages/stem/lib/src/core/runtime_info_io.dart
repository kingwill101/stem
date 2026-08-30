import 'dart:io';

/// Returns the local VM hostname when the platform exposes one.
String? stemLocalHostname() => Platform.localHostname;
