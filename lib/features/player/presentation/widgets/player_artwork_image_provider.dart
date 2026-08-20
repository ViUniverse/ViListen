// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

ImageProvider<Object>? resolvePlayerArtworkImageProvider(Uri uri) {
  if (uri.scheme == 'https') {
    return NetworkImage(uri.toString());
  }
  return null;
}
