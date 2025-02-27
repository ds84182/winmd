// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'com/imetadataimport2.dart';
import 'enums.dart';
import 'scope.dart';

/// Size used for Win32 string allocations.
///
/// A common pattern for Win32 string calls is to provide a buffer larger than
/// the expected return value, along with an out parameter to be filled in with
/// the actual size of the string returned. This constant is used to set a
/// consistent value that is expected to be large enough to accommodate the
/// return results.
const stringBufferSize = 256;

/// The base object for metadata objects.
///
/// All metadata objects (typedefs, parameters, fields, events, etc.) have a
/// 32-bit token value, which is the primary key for the object in the
/// underlying Windows metadata database. The high byte of the token describes
/// its type.
abstract class TokenObject {
  /// The [Scope] that contains this token.
  final Scope scope;

  /// A unique identifier for this token in the metadata file.
  final int token;

  const TokenObject(this.scope, this.token);

  IMetaDataImport2 get reader => scope.reader;

  @override
  int get hashCode => token;

  @override
  bool operator ==(Object other) =>
      other is TokenObject && other.token == token;

  /// Returns true if the token maps to an entry in the WinMD database.
  ///
  /// This should return true for most objects, but as noted in
  /// https://docs.microsoft.com/en-us/uwp/winrt-cref/winmd-files#type-system-encoding,
  /// some types are markers that should never be resolved. For example, WinRT
  /// uses the CLR `System.Guid` type as a marker, but it should not be resolved
  /// to the .NET type system.
  bool get isResolvedToken => reader.IsValidToken(token) == TRUE;

  /// Returns true if the token is marked as global.
  bool get isGlobal {
    if (!isResolvedToken) return false;

    return using((Arena arena) {
      final pIsGlobal = arena<Int32>();
      final hr = reader.IsGlobal(token, pIsGlobal);
      if (FAILED(hr)) throw WindowsException(hr);

      return pIsGlobal.value == 1;
    });
  }

  TokenType get tokenType => TokenType.fromToken(token);
}
