// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';

ImageProvider<Object>? resolvePlayerArtworkImageProvider(Uri uri) {
  switch (uri.scheme) {
    case 'https':
      return NetworkImage(uri.toString());
    case 'file':
      return FileImage(File.fromUri(uri));
    default:
      return null;
  }
}
