// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import 'dart:io';

/// Returns the local VM hostname when the platform exposes one.
String? stemLocalHostname() => Platform.localHostname;
