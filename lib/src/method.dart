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
import 'methodimpls.dart';
import 'mixins/customattributes_mixin.dart';
import 'mixins/genericparams_mixin.dart';
import 'module.dart';
import 'parameter.dart';
import 'pinvokemap.dart';
import 'typedef.dart';
import 'typeidentifier.dart';
import 'utils.dart';
import 'win32.dart';

enum MemberAccess {
  privateScope,
  private,
  familyAndAssembly,
  assembly,
  family,
  familyOrAssembly,
  public
}

enum VtableLayout { reuseSlot, newSlot }

class Method extends TokenObject
    with CustomAttributesMixin, GenericParamsMixin {
  int _parentToken;
  String methodName;
  int _attributes;
  Uint8List signatureBlob;
  int relativeVirtualAddress;
  int implFlags;

  TypeDef get parent => TypeDef.fromToken(reader, _parentToken);

  /// Returns information about the method's visibility / accessibility to other
  /// types.
  MemberAccess get memberAccess =>
      MemberAccess.values[_attributes & CorMethodAttr.mdMemberAccessMask];

  /// Returns true if the member is defined as part of the type rather than as a
  /// member of an instance.
  bool get isStatic =>
      _attributes & CorMethodAttr.mdStatic == CorMethodAttr.mdStatic;

  /// Returns true if the method cannot be overridden.
  bool get isFinal =>
      _attributes & CorMethodAttr.mdFinal == CorMethodAttr.mdFinal;

  /// Returns true if the method can be overridden.
  bool get isVirtual =>
      _attributes & CorMethodAttr.mdVirtual == CorMethodAttr.mdVirtual;

  /// Returns true if the method hides by name and signature, rather than just
  /// by name.
  bool get isHideBySig =>
      _attributes & CorMethodAttr.mdHideBySig == CorMethodAttr.mdHideBySig;

  /// Returns information about the vtable layout of this method.
  ///
  /// If `ReuseSlot`, the slot used for this method in the virtual table be
  /// reused. This is the default. If `NewSlot`, the method always gets a new
  /// slot in the virtual table.
  VtableLayout get vTableLayout {
    switch (_attributes & CorMethodAttr.mdVtableLayoutMask) {
      case CorMethodAttr.mdReuseSlot:
        return VtableLayout.reuseSlot;
      case CorMethodAttr.mdNewSlot:
        return VtableLayout.newSlot;
      default:
        throw WinmdException('Attribute missing vtable layout information');
    }
  }

  /// Returns true if the method can be overridden by the same types to which it
  /// is visible.
  bool get isCheckAccessOnOverride =>
      _attributes & CorMethodAttr.mdCheckAccessOnOverride ==
      CorMethodAttr.mdCheckAccessOnOverride;

  /// Returns true if the method is not implemented.
  bool get isAbstract =>
      _attributes & CorMethodAttr.mdAbstract == CorMethodAttr.mdAbstract;

  /// Returns true if the method is special; its name describes how.
  bool get isSpecialName =>
      _attributes & CorMethodAttr.mdSpecialName == CorMethodAttr.mdSpecialName;

  /// Returns true if the method implementation is forwarded using PInvoke.
  bool get isPinvokeImpl =>
      _attributes & CorMethodAttr.mdPinvokeImpl == CorMethodAttr.mdPinvokeImpl;

  /// Returns true if the method is a managed method exported to unmanaged code.
  bool get isUnmanagedExport =>
      _attributes & CorMethodAttr.mdUnmanagedExport ==
      CorMethodAttr.mdUnmanagedExport;

  /// Returns true if the common language runtime should check the encoding of
  /// the method name.
  bool get isRTSpecialName =>
      _attributes & CorMethodAttr.mdSpecialName == CorMethodAttr.mdSpecialName;

  PinvokeMap get pinvokeMap => PinvokeMap.fromToken(reader, token);

  MethodImplementationFeatures get implFeatures =>
      MethodImplementationFeatures(implFlags);

  bool get isProperty => isGetProperty | isSetProperty;
  bool isGetProperty = false;
  bool isSetProperty = false;

  List<Parameter> parameters = <Parameter>[];
  late Parameter returnType;

  Module get module {
    final pdwMappingFlags = calloc<DWORD>();
    final szImportName = stralloc(MAX_STRING_SIZE);
    final pchImportName = calloc<ULONG>();
    final ptkImportDLL = calloc<mdModuleRef>();
    try {
      final hr = reader.GetPinvokeMap(token, pdwMappingFlags, szImportName,
          MAX_STRING_SIZE, pchImportName, ptkImportDLL);
      if (SUCCEEDED(hr)) {
        return Module.fromToken(reader, ptkImportDLL.value);
      } else {
        throw COMException(hr);
      }
    } finally {
      free(pdwMappingFlags);
      free(szImportName);
      free(pchImportName);
      free(ptkImportDLL);
    }
  }

  Method(
      IMetaDataImport2 reader,
      int token,
      this._parentToken,
      this.methodName,
      this._attributes,
      this.signatureBlob,
      this.relativeVirtualAddress,
      this.implFlags)
      : super(reader, token) {
    _parseMethodType();
    _parseParameterNames();
    _parseSignatureBlob();
    _parseParameterAttributes();
  }

  /// Creates a method object from its given token.
  factory Method.fromToken(IMetaDataImport2 reader, int token) {
    final ptkClass = calloc<mdTypeDef>();
    final szMethod = stralloc(MAX_STRING_SIZE);
    final pchMethod = calloc<ULONG>();
    final pdwAttr = calloc<DWORD>();
    final ppvSigBlob = calloc<PCCOR_SIGNATURE>();
    final pcbSigBlob = calloc<ULONG>();
    final pulCodeRVA = calloc<ULONG>();
    final pdwImplFlags = calloc<DWORD>();

    try {
      final hr = reader.GetMethodProps(
          token,
          ptkClass,
          szMethod,
          MAX_STRING_SIZE,
          pchMethod,
          pdwAttr,
          ppvSigBlob.cast(),
          pcbSigBlob,
          pulCodeRVA,
          pdwImplFlags);

      if (SUCCEEDED(hr)) {
        final signature = ppvSigBlob.value.asTypedList(pcbSigBlob.value);
        return Method(reader, token, ptkClass.value, szMethod.toDartString(),
            pdwAttr.value, signature, pulCodeRVA.value, pdwImplFlags.value);
      } else {
        throw WindowsException(hr);
      }
    } finally {
      free(ptkClass);
      free(szMethod);
      free(pchMethod);
      free(pdwAttr);
      free(ppvSigBlob);
      free(pcbSigBlob);
      free(pulCodeRVA);
      free(pdwImplFlags);
    }
  }

  bool get hasGenericParameters => signatureBlob[0] & 0x10 == 0x10;

  void _parseMethodType() {
    if (isSpecialName && methodName.startsWith('get_')) {
      // Property getter
      isGetProperty = true;
    } else if (isSpecialName && methodName.startsWith('put_')) {
      // Property setter
      isSetProperty = true;
    }
  }

  /// Returns flags relating to the method calling convention.
  String get callingConvention {
    final retVal = StringBuffer();
    final cc = signatureBlob[0];

    retVal.write('default ');
    if (cc & 0x05 == 0x05) retVal.write('vararg ');
    if (cc & 0x10 == 0x10) retVal.write('generic ');
    if (cc & 0x20 == 0x20) retVal.write('instance ');
    if (cc & 0x40 == 0x40) retVal.write('explicit ');

    return retVal.toString();
  }

  /// Parses the parameters and return type for this method from the
  /// [signatureBlob], which is of type `MethodDefSig` (or `PropertySig`, if the
  /// method is a property getter). This is documented in §II.23.2.1 and
  /// §II.23.2.5 respectively.
  void _parseSignatureBlob() {
    // Win32 properties are declared as such, but are represented as
    // MethodDefSig objects
    if (isGetProperty && signatureBlob[0] != 0x20) {
      _parsePropertySig();
    } else {
      _parseMethodDefSig();
    }
  }

  /// Parse a property from the signature blob. Properties have the following
  /// format: [type | paramCount | customMod | type | param]
  ///
  /// `PropertySig` is defined in §II.23.2.5.
  void _parsePropertySig() {
    if (isGetProperty) {
      // Type should begin at index 2
      final typeIdentifier =
          parseTypeFromSignature(signatureBlob.sublist(2), reader)
              .typeIdentifier;
      returnType = Parameter.fromTypeIdentifier(reader, token, typeIdentifier);
    } else if (isSetProperty) {
      // set properties don't have a return type
      returnType = Parameter.fromVoid(reader, token);
    }
  }

  /// Parses the parameters and return type for this method from the
  /// [signatureBlob], which is of type `MethodDefSig`. This is documented in
  /// §II.23.2.1.
  ///
  /// This is of format:
  ///   [callConv | genParamCount | paramCount | retType | param...]
  void _parseMethodDefSig() {
    var paramsIndex = 0;

    // Strip off the header and the paramCount. We know the number and names of
    // the parameters already; we're simply mapping them to types here.
    var blobPtr = hasGenericParameters == false ? 2 : 3;

    // Windows Runtime emits a zero-th parameter for the return type. So move
    // that to the returnType and parse a type from the signature.
    if (parameters.isNotEmpty && parameters.first.sequence == 0) {
      // Parse return type
      returnType = parameters.first;
      parameters = parameters.sublist(1);
      final returnTypeTuple =
          parseTypeFromSignature(signatureBlob.sublist(blobPtr), reader);
      returnType.typeIdentifier = returnTypeTuple.typeIdentifier;
      blobPtr += returnTypeTuple.offsetLength;
    } else {
      // In Win32 metadata, EnumParams does not return a zero-th parameter even
      // if there is a return type. So we create a new returnType for it.
      final returnTypeTuple =
          parseTypeFromSignature(signatureBlob.sublist(blobPtr), reader);
      returnType = Parameter.fromTypeIdentifier(
          reader, token, returnTypeTuple.typeIdentifier);
      blobPtr += returnTypeTuple.offsetLength;
    }

    // Parse through the params section of MethodDefSig, and map each recovered
    // type to the corresponding parameter.
    while (paramsIndex < parameters.length) {
      final runtimeType =
          parseTypeFromSignature(signatureBlob.sublist(blobPtr), reader);
      blobPtr += runtimeType.offsetLength;

      if (runtimeType.typeIdentifier.corType ==
          CorElementType.ELEMENT_TYPE_ARRAY) {
        blobPtr += _parseArray(signatureBlob.sublist(blobPtr), paramsIndex) + 2;
        paramsIndex++; //we've added two parameters here
      } else {
        parameters[paramsIndex].typeIdentifier = runtimeType.typeIdentifier;
      }
      paramsIndex++;
    }
  }

  void _parseParameterNames() {
    final phEnum = calloc<HCORENUM>();
    final rParams = calloc<mdParamDef>();
    final pcTokens = calloc<ULONG>();

    try {
      var hr = reader.EnumParams(phEnum, token, rParams, 1, pcTokens);
      while (hr == S_OK) {
        final token = rParams.value;

        parameters.add(Parameter.fromToken(reader, token));
        hr = reader.EnumParams(phEnum, token, rParams, 1, pcTokens);
      }
    } finally {
      reader.CloseEnum(phEnum.value);
      free(phEnum);
      free(rParams);
      free(pcTokens);
    }
  }

  void _parseParameterAttributes() {
    // At some point, we should look this up
    const nativeTypeInfoToken = 0x0A000004;

    for (final param in parameters) {
      for (final attr in param.customAttributes) {
        if (attr.attributeType == nativeTypeInfoToken) {
          if (attr.signatureBlob[2] == 0x14) // ASCII
          {
            param.typeIdentifier.name = 'LPSTR';
          } else if (attr.signatureBlob[2] == 0x15) // Unicode
          {
            param.typeIdentifier.name = 'LPWSTR';
          }
        }
      }
    }
  }

  // Various projections do smart things to mask this into a single array
  // value. We're not that clever yet, so we project it in its raw state, which
  // means a little work here to ensure that it comes out right.
  int _parseArray(Uint8List sublist, int paramsIndex) {
    final typeTuple = parseTypeFromSignature(sublist.sublist(2), reader);

    parameters[paramsIndex].name = '__valueSize';
    parameters[paramsIndex].typeIdentifier.corType =
        CorElementType.ELEMENT_TYPE_PTR;
    parameters[paramsIndex]
        .typeIdentifier
        .typeArgs
        .add(TypeIdentifier(CorElementType.ELEMENT_TYPE_U4));

    parameters.insert(paramsIndex + 1, Parameter.fromVoid(reader, token));
    parameters[paramsIndex + 1].name = 'value';
    parameters[paramsIndex + 1].typeIdentifier.corType =
        CorElementType.ELEMENT_TYPE_PTR;
    parameters[paramsIndex + 1]
        .typeIdentifier
        .typeArgs
        .add(typeTuple.typeIdentifier);

    return typeTuple.offsetLength;
  }

  @override
  String toString() => 'Method: $methodName';
}
