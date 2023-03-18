// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// waitFor is controversial, but necessary in the absence of a better mechanism
// for non-Flutter packages to load binary assets.
//
// ignore_for_file: deprecated_member_use

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'com/enums.dart';
import 'com/imetadataassemblyimport.dart';
import 'com/imetadatadispenser.dart';
import 'com/imetadataimport2.dart';
import 'nuget/nuget.dart';
import 'scope.dart';
import 'type_aliases.dart';
import 'typedef.dart';
import 'utils/exception.dart';

/// Caches a reader for each file scope.
///
/// Use this to obtain a reference of a scope without creating unnecessary
/// copies or cycles.
class MetadataStore {
  Map<String, Scope> scopeCache = {};
  late final IMetaDataDispenser dispenser;

  MetadataStore() {
    // This must have the same object lifetime as MetadataStore itself.
    final dispenserObject = calloc<COMObject>();
    final clsidCorMetaDataDispenser =
        convertToCLSID(CorMetaDataDispenser.CLSID);
    final iidIMetaDataDispenser = convertToIID(IMetaDataDispenser.IID);

    try {
      final hr = MetaDataGetDispenser(clsidCorMetaDataDispenser,
          iidIMetaDataDispenser, dispenserObject.cast());

      if (FAILED(hr)) {
        throw WindowsException(hr);
      }

      dispenser = IMetaDataDispenser(dispenserObject);
    } finally {
      free(clsidCorMetaDataDispenser);
      free(iidIMetaDataDispenser);
    }
  }

  /// Return the scope that contains the Win32 metadata.
  ///
  /// The Windows Runtime metadata is included as part of Windows, but Win32
  /// metadata is not. We include a copy that is tested to work with this
  /// package, since it's likely that the two will be used together.
  ///
  /// By having this here, we remove the need for this large file to be
  /// distributed with the win32 package, since it's only used at development
  /// time for generating types. It also reduces the risk of breaking changes
  /// being out of sync with the winmd library, since the two can be more
  /// tightly bound together.
  Future<void> loadWin32Metadata() async {
    const win32pkg = 'Microsoft.Windows.SDK.Win32Metadata';
    final latestVersion =
        await NuGet.getLatestVersion(win32pkg, includePreviewVersions: true);
    final win32PackagePath = await NuGet.unpackPackage(win32pkg, latestVersion);

    final win32Metadata = File('$win32PackagePath\\Windows.Win32.winmd');
    scopeCache['Windows.Win32.winmd'] = loadScopeFromFile(win32Metadata);

    final win32InteropDll =
        File('$win32PackagePath\\Windows.Win32.Interop.dll');
    scopeCache['Windows.Win32.Interop.dll'] =
        loadScopeFromFile(win32InteropDll);
  }

  /// Takes a metadata file path and returns the matching scope.
  Scope loadScopeFromFile(File fileScope) {
    final filename = fileScope.uri.pathSegments.last;

    if (scopeCache.containsKey(filename)) {
      return scopeCache[filename]!;
    } else {
      final szFile = fileScope.path.toNativeUtf16();
      final pReader = calloc<COMObject>();
      final iidIMetaDataImport2 = convertToIID(IMetaDataImport2.IID);
      final pAssemblyImport = calloc<COMObject>();
      final iidIMetaDataAssemblyImport =
          convertToIID(IMetaDataAssemblyImport.IID);

      try {
        var hr = dispenser.OpenScope(
            szFile, CorOpenFlags.ofRead, iidIMetaDataImport2, pReader.cast());
        if (FAILED(hr)) throw WindowsException(hr);
        hr = dispenser.OpenScope(szFile, CorOpenFlags.ofRead,
            iidIMetaDataAssemblyImport, pAssemblyImport.cast());
        final scope = Scope(IMetaDataImport2(pReader),
            IMetaDataAssemblyImport(pAssemblyImport));
        scopeCache[filename] = scope;
        return scope;
      } finally {
        free(szFile);
        free(iidIMetaDataImport2);
        free(iidIMetaDataAssemblyImport);
      }
    }
  }

  /// Takes a typename (e.g. `Windows.Globalization.Calendar`) and returns the
  /// metadata file that contains the type.
  File winmdFileContainingType(String typeName) {
    if (typeName.isEmpty) throw WinmdException('Type cannot be empty.');

    File path;

    final hstrTypeName = convertToHString(typeName);
    final hstrMetaDataFilePath = calloc<HSTRING>();
    final spMetaDataImport = calloc<Pointer>();
    final typeDef = calloc<mdTypeDef>();

    try {
      // RoGetMetaDataFile can only be used for Windows Runtime classes (i.e. not
      // third-party types) in an app that is not a Windows Store app.
      final hr = RoGetMetaDataFile(hstrTypeName, nullptr, hstrMetaDataFilePath,
          spMetaDataImport, typeDef);
      if (SUCCEEDED(hr)) {
        path = File(convertFromHString(hstrMetaDataFilePath.value));
      } else {
        final errorCode = hr.toHexString(32);
        if (errorCode == RO_E_METADATA_INVALID_TYPE_FORMAT.toHexString(32)) {
          throw WindowsException(hr,
              message: "'$typeName' is not a valid Windows Runtime type.");
        } else if (errorCode ==
            RO_E_METADATA_NAME_IS_NAMESPACE.toHexString(32)) {
          throw WindowsException(hr,
              message: "'$typeName' is a namespace, not a type.");
        } else if (errorCode == RO_E_METADATA_NAME_NOT_FOUND.toHexString(32)) {
          throw WindowsException(hr,
              message: "Could not find type '$typeName'.");
        }
        throw WindowsException(hr);
      }
    } finally {
      WindowsDeleteString(hstrTypeName);
      WindowsDeleteString(hstrMetaDataFilePath.value);

      free(hstrMetaDataFilePath);
    }

    return path;
  }

  /// Takes a typename (e.g. `Windows.Globalization.Calendar`) and returns the
  /// metadata scope that contains the type.
  Scope getScopeForType(String typeName) {
    if (typeName.isEmpty) throw WinmdException('Type cannot be empty.');

    if (typeName.startsWith('Windows.Win32')) {
      // It's a Win32 type.

      // The following will throw an exception if the Win32 scope isn't in the
      // cache, since we don't know where to find the Win32 metadata if it's not
      // already loaded. This won't be a problem, so long as the original Win32
      // metadata scope was loaded with getScopeForFile.
      final cacheEntry =
          scopeCache.keys.firstWhere((entry) => entry == 'Windows.Win32.winmd');

      return scopeCache[cacheEntry]!;
    } else {
      // Assume it's a Windows Runtime type
      final hstrTypeName = convertToHString(typeName);

      final hstrMetaDataFilePath = calloc<HSTRING>();
      final spMetaDataImport = calloc<Pointer>();
      final typeDef = calloc<mdTypeDef>();

      try {
        // For apps that are not Windows Store apps, RoGetMetaDataFile can only
        // be used for classes that are part of the Windows Runtime itself (i.e.
        // not third-party types).
        final hr = RoGetMetaDataFile(hstrTypeName, nullptr,
            hstrMetaDataFilePath, spMetaDataImport, typeDef);
        if (SUCCEEDED(hr)) {
          final filePath = convertFromHString(hstrMetaDataFilePath.value);
          return loadScopeFromFile(File(filePath));
        } else {
          final errorCode = hr.toHexString(32);
          if (errorCode == RO_E_METADATA_INVALID_TYPE_FORMAT.toHexString(32)) {
            throw WindowsException(hr,
                message: "'$typeName' is not a valid Windows Runtime type.");
          } else if (errorCode ==
              RO_E_METADATA_NAME_IS_NAMESPACE.toHexString(32)) {
            throw WindowsException(hr,
                message: "'$typeName' is a namespace, not a type.");
          } else if (errorCode ==
              RO_E_METADATA_NAME_NOT_FOUND.toHexString(32)) {
            throw WindowsException(hr,
                message: "Could not find type '$typeName'.");
          }
          throw WindowsException(hr);
        }
      } finally {
        WindowsDeleteString(hstrTypeName);
        WindowsDeleteString(hstrMetaDataFilePath.value);

        free(hstrMetaDataFilePath);
      }
    }
  }

  /// Find a matching typedef, if one exists, for a Windows Runtime type.
  TypeDef? getMetadataForType(String typeName) {
    if (typeName.isEmpty) throw WinmdException('Type cannot be empty.');

    final scope = getScopeForType(typeName);
    return scope.findTypeDef(typeName);
  }

  /// Dispose of all objects.
  ///
  /// The readers and dispensers should be automatically torn down with the end
  /// of the process, but it's polite to do this in an orderly manner,
  /// particularly if the calling app outlives the cache lifetime.
  void close() {}

  /// Print information about the cache for debugging purposes.
  String get cacheInfo => '[${MetadataStore.scopeCache.keys.join(', ')}]';
}
