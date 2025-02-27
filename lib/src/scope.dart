// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'assemblyref.dart';
import 'com/imetadataassemblyimport.dart';
import 'com/imetadataimport2.dart';
import 'enums.dart';
import 'metadatastore.dart';
import 'moduleref.dart';
import 'pekind.dart';
import 'token_object.dart';
import 'type_aliases.dart';
import 'typedef.dart';
import 'utils/exception.dart';

/// A metadata scope, which typically matches an on-disk file.
///
/// Rather than being created directly, you should obtain a scope from a
/// [MetadataStore], which caches scopes to avoid duplication.
class Scope {
  late final String guid;
  late final String name;
  final IMetaDataImport2 reader;
  final IMetaDataAssemblyImport assemblyImport;

  late final enums = _getEnums();
  late final moduleRefs = _getModuleRefs();
  late final assemblyRefs = _getAssemblyRefs();
  late final delegates = _getDelegates();
  late final userStrings = _getUserStrings();

  final _typedefsByName = <String, List<TypeDef>>{};
  final _typedefs = <int, TypeDef>{};

  Scope(this.reader, this.assemblyImport) {
    using((Arena arena) {
      final szName = arena<WCHAR>(stringBufferSize).cast<Utf16>();
      final pchName = arena<ULONG>();
      final pmvid = arena<GUID>();

      final hr = reader.GetScopeProps(szName, stringBufferSize, pchName, pmvid);
      if (SUCCEEDED(hr)) {
        name = szName.toDartString();
        guid = pmvid.ref.toString();
      } else {
        throw COMException(hr);
      }
    });

    _populateTypeDefs();
  }

  @override
  String toString() => name;

  /// Get an enumerated list of typedefs for this scope.
  Iterable<TypeDef> get typeDefs => _typedefs.values;

  /// Return the first typedef object matching the given name.
  ///
  /// Returns null if no typedefs match the name.
  TypeDef? findTypeDef(String name,
      {PreferredArchitecture preferredArchitecture =
          PreferredArchitecture.x64}) {
    final matchingTypeDefs = _typedefsByName[name];

    if (matchingTypeDefs == null) return null;
    if (matchingTypeDefs.length == 1) return matchingTypeDefs.first;

    // More than one typedef, so we find the one that matches the preferred
    // architecture.
    for (final typeDef in matchingTypeDefs) {
      final supportedArch = typeDef.supportedArchitectures;

      if (preferredArchitecture == PreferredArchitecture.x64 &&
          supportedArch.x64) return typeDef;
      if (preferredArchitecture == PreferredArchitecture.arm64 &&
          supportedArch.arm64) return typeDef;
      if (preferredArchitecture == PreferredArchitecture.x86 &&
          supportedArch.x86) return typeDef;
    }

    return null;
  }

  /// Return the typedef matching the given token.
  ///
  /// Returns null if no typedefs match the token. Note that this does not
  /// resolve `TypeRef`s or `TypeSpec`s.
  TypeDef? findTypeDefByToken(int token) => _typedefs[token];

  void _populateTypeDefs() {
    using((Arena arena) {
      final phEnum = arena<HCORENUM>();
      final rgTypeDefs = arena<mdTypeDef>();
      final pcTypeDefs = arena<ULONG>();

      var hr = reader.EnumTypeDefs(phEnum, rgTypeDefs, 1, pcTypeDefs);
      while (hr == S_OK) {
        final typeDefToken = rgTypeDefs.value;

        _typedefs[typeDefToken] = TypeDef.fromToken(this, typeDefToken);
        hr = reader.EnumTypeDefs(phEnum, rgTypeDefs, 1, pcTypeDefs);
      }
      reader.CloseEnum(phEnum.value);
    });

    for (final typeDef in typeDefs) {
      _typedefsByName.putIfAbsent(typeDef.name, () => []).add(typeDef);
    }
  }

  int get moduleToken => using((Arena arena) {
        final pmd = arena<mdModule>();

        final hr = reader.GetModuleFromScope(pmd);
        if (SUCCEEDED(hr)) {
          return pmd.value;
        } else {
          throw WinmdException('Unable to find module token.');
        }
      });

  /// Get an enumerated list of modules in this scope.
  Iterable<ModuleRef> _getModuleRefs() {
    final modules = <ModuleRef>[];
    using((Arena arena) {
      final phEnum = arena<HCORENUM>();
      final rgModuleRefs = arena<mdModuleRef>();
      final pcModuleRefs = arena<ULONG>();

      var hr = reader.EnumModuleRefs(phEnum, rgModuleRefs, 1, pcModuleRefs);
      while (hr == S_OK) {
        final moduleToken = rgModuleRefs.value;
        modules.add(ModuleRef.fromToken(this, moduleToken));
        hr = reader.EnumModuleRefs(phEnum, rgModuleRefs, 1, pcModuleRefs);
      }
      reader.CloseEnum(phEnum.value);
    });

    return modules;
  }

  /// Get an enumerated list of assembly references in this scope.
  Iterable<AssemblyRef> _getAssemblyRefs() {
    final assemblies = <AssemblyRef>[];
    using((Arena arena) {
      final phEnum = arena<HCORENUM>();
      final rAssemblyRefs = arena<mdModuleRef>();
      final pcTokens = arena<ULONG>();

      var hr =
          assemblyImport.EnumAssemblyRefs(phEnum, rAssemblyRefs, 1, pcTokens);
      while (hr == S_OK) {
        final assemblyToken = rAssemblyRefs.value;
        assemblies.add(AssemblyRef.fromToken(this, assemblyToken));
        hr =
            assemblyImport.EnumAssemblyRefs(phEnum, rAssemblyRefs, 1, pcTokens);
      }
      assemblyImport.CloseEnum(phEnum.value);
    });

    return assemblies;
  }

  /// Get an enumerated list of all hard-coded strings in this scope.
  Iterable<String> _getUserStrings() {
    final userStrings = <String>[];
    using((Arena arena) {
      final phEnum = arena<HCORENUM>();
      final rgStrings = arena<mdString>();
      final pcStrings = arena<ULONG>();
      final szString = arena<WCHAR>(stringBufferSize).cast<Utf16>();
      final pchString = arena<ULONG>();

      var hr = reader.EnumUserStrings(phEnum, rgStrings, 1, pcStrings);
      while (hr == S_OK) {
        final stringToken = rgStrings.value;
        hr = reader.GetUserString(
            stringToken, szString, stringBufferSize, pchString);
        if (hr == S_OK) {
          userStrings.add(szString.toDartString());
        }
        hr = reader.EnumUserStrings(phEnum, rgStrings, 1, pcStrings);
      }
      reader.CloseEnum(phEnum.value);
    });

    return userStrings;
  }

  /// Get an enumerated list of all enumerations in this scope.
  Iterable<TypeDef> _getEnums() => typeDefs.where((typeDef) => typeDef.isEnum);

  /// Get an enumerated list of all delegates in this scope.
  Iterable<TypeDef> _getDelegates() =>
      typeDefs.where((typeDef) => typeDef.isDelegate);

  PEKind get executableKind => PEKind(reader);

  String get version => using((Arena arena) {
        final pwzBuf = arena<WCHAR>(stringBufferSize).cast<Utf16>();
        final pccBufSize = arena<DWORD>();

        final hr =
            reader.GetVersionString(pwzBuf, stringBufferSize, pccBufSize);

        if (SUCCEEDED(hr)) {
          return pwzBuf.toDartString();
        } else {
          return '';
        }
      });
}
