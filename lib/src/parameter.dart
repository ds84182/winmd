// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'base.dart';
import 'com/IMetaDataImport2.dart';
import 'constants.dart';
import 'method.dart';
import 'mixins/customattributes_mixin.dart';
import 'typeidentifier.dart';
import 'win32.dart';

/// A parameter or return type.
class Parameter extends TokenObject with CustomAttributesMixin {
  final int _methodToken;
  final int sequence;
  final int _attributes;
  TypeIdentifier typeIdentifier;
  String name;
  final Uint8List signatureBlob;

  Method get parent => Method.fromToken(reader, _methodToken);

  /// Returns true if the parameter is passed into the method call.
  bool get isInParam => _attributes & CorParamAttr.pdIn == CorParamAttr.pdIn;

  /// Returns true if the parameter is passed from the method return.
  bool get isOutParam => _attributes & CorParamAttr.pdOut == CorParamAttr.pdOut;

  /// Returns true if the parameter is optional.
  bool get isOptional =>
      _attributes & CorParamAttr.pdOptional == CorParamAttr.pdOptional;

  /// Returns true if the parameter has a default value.
  bool get hasDefault =>
      _attributes & CorParamAttr.pdHasDefault == CorParamAttr.pdHasDefault;

  /// Returns true if the parameter has marshaling information.
  bool get hasFieldMarshal =>
      _attributes & CorParamAttr.pdHasFieldMarshal ==
      CorParamAttr.pdHasFieldMarshal;

  Parameter(
      IMetaDataImport2 reader,
      int token,
      this._methodToken,
      this.sequence,
      this._attributes,
      this.typeIdentifier,
      this.name,
      this.signatureBlob)
      : super(reader, token);

  /// Creates a parameter object from its given token.
  factory Parameter.fromToken(IMetaDataImport2 reader, int token) {
    final ptkMethodDef = calloc<mdMethodDef>();
    final pulSequence = calloc<ULONG>();
    final szName = stralloc(MAX_STRING_SIZE);
    final pchName = calloc<ULONG>();
    final pdwAttr = calloc<DWORD>();
    final pdwCPlusTypeFlag = calloc<DWORD>();
    final ppValue = calloc<UVCP_CONSTANT>();
    final pcchValue = calloc<ULONG>();

    try {
      final hr = reader.GetParamProps(
          token,
          ptkMethodDef,
          pulSequence,
          szName,
          MAX_STRING_SIZE,
          pchName,
          pdwAttr,
          pdwCPlusTypeFlag,
          ppValue.cast(),
          pcchValue);
      if (SUCCEEDED(hr)) {
        return Parameter(
            reader,
            token,
            ptkMethodDef.value,
            pulSequence.value,
            pdwAttr.value,
            TypeIdentifier.fromValue(pdwCPlusTypeFlag.value),
            szName.toDartString(),
            ppValue.value.asTypedList(pcchValue.value));
      } else {
        throw WindowsException(hr);
      }
    } finally {
      free(ptkMethodDef);
      free(pulSequence);
      free(szName);
      free(pchName);
      free(pdwAttr);
      free(pdwCPlusTypeFlag);
      free(ppValue);
      free(pcchValue);
    }
  }

  factory Parameter.fromTypeIdentifier(IMetaDataImport2 reader, int methodToken,
          TypeIdentifier runtimeType) =>
      Parameter(reader, 0, methodToken, 0, 0, runtimeType, '', Uint8List(0));

  factory Parameter.fromVoid(IMetaDataImport2 reader, int methodToken) =>
      Parameter(reader, 0, methodToken, 0, 0,
          TypeIdentifier(CorElementType.ELEMENT_TYPE_VOID), '', Uint8List(0));
  @override
  String toString() => 'Parameter: $name';
}
