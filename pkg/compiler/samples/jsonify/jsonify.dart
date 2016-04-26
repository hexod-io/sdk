// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:sdk_library_metadata/libraries.dart' show libraries;

import '../../lib/src/filenames.dart';
import '../../lib/src/mirrors/analyze.dart' show analyze;
import '../../lib/src/mirrors/dart2js_mirrors.dart' show BackDoor;
import '../../lib/src/source_file_provider.dart';
import '../../lib/src/util/uri_extras.dart';

const DART2JS = '../../lib/src/dart2js.dart';
const DART2JS_MIRROR = '../../lib/src/mirrors/dart2js_mirror.dart';
const SDK_ROOT = '../../../../sdk/';

bool isPublicDart2jsLibrary(String name) {
  return !name.startsWith('_') && libraries[name].isDart2jsLibrary;
}

var handler;
RandomAccessFile output;
Uri outputUri;
Uri sdkRoot;
const bool outputJson =
    const bool.fromEnvironment('outputJson', defaultValue: false);

main(List<String> arguments) {
  handler = new FormattingDiagnosticHandler()..throwOnError = true;

  outputUri = handler.provider.cwd.resolve(nativeToUriPath(arguments.first));
  output = new File(arguments.first).openSync(mode: FileMode.WRITE);

  Uri myLocation = handler.provider.cwd.resolveUri(Platform.script);

  Uri packageRoot = handler.provider.cwd.resolve(Platform.packageRoot);

  Uri libraryRoot = myLocation.resolve(SDK_ROOT);

  sdkRoot = libraryRoot.resolve('../');

  // Get the names of public dart2js libraries.
  Iterable<String> names = libraries.keys.where(isPublicDart2jsLibrary);

  // Turn the names into uris by prepending dart: to them.
  List<Uri> uris = names.map((String name) => Uri.parse('dart:$name')).toList();

  analyze(uris, libraryRoot, packageRoot, handler.provider, handler)
      .then(jsonify);
}

jsonify(MirrorSystem mirrors) {
  var map = <String, String>{};
  List<Future> futures = <Future>[];

  Future mapUri(Uri uri) {
    String filename = relativize(sdkRoot, uri, false);
    return handler.provider.readStringFromUri(uri).then((contents) {
      map['sdk:/$filename'] = contents;
    });
  }

  mirrors.libraries.forEach((_, LibraryMirror library) {
    BackDoor.compilationUnitsOf(library).forEach((compilationUnit) {
      futures.add(mapUri(compilationUnit.uri));
    });
  });

  libraries.forEach((name, info) {
    var patch = info.dart2jsPatchPath;
    if (patch != null) {
      futures.add(mapUri(sdkRoot.resolve('sdk/lib/$patch')));
    }
  });

  for (String filename in [
    "dart_client.platform",
    "dart_server.platform",
    "dart_shared.platform"
  ]) {
    futures.add(mapUri(sdkRoot.resolve('sdk/lib/$filename')));
  }

  Future.wait(futures).then((_) {
    if (outputJson) {
      output.writeStringSync(JSON.encode(map));
    } else {
      output.writeStringSync('''
// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// DO NOT EDIT.
// This file is generated by jsonify.dart.

library dart.sdk_sources;

const Map<String, String> SDK_SOURCES = const <String, String>''');
      output.writeStringSync(JSON.encode(map).replaceAll(r'$', r'\$'));
      output.writeStringSync(';\n');
    }
    output.closeSync();
  });
}
