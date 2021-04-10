@TestOn('windows')

import 'package:test/test.dart';
import 'package:winmd/winmd.dart';

/// Exhaustively test an enum representation.
void main() {
  // .class public auto ansi sealed Windows.Win32.WindowsAndMessaging.HANDEDNESS
  // 	extends [netstandard]System.Enum
  // {
  // 	// Fields
  // 	.field public specialname rtspecialname int32 value__
  // 	.field public static literal valuetype [Windows.Win32.winmd]Windows.Win32.WindowsAndMessaging.HANDEDNESS HANDEDNESS_LEFT = int32(0)
  // 	.field public static literal valuetype [Windows.Win32.winmd]Windows.Win32.WindowsAndMessaging.HANDEDNESS HANDEDNESS_RIGHT = int32(1)

  // } // end of class Windows.Win32.WindowsAndMessaging.HANDEDNESS
  test('Windows.Win32.WindowsAndMessaging.HANDEDNESS', () {
    final scope = MetadataStore.getWin32Scope();
    final hand =
        scope.findTypeDef('Windows.Win32.WindowsAndMessaging.HANDEDNESS')!;

    expect(hand.typeVisibility, equals(TypeVisibility.public));
    expect(hand.typeLayout, equals(TypeLayout.auto));
    expect(hand.stringFormat, equals(StringFormat.ansi));
    expect(hand.isSealed, isTrue);
    expect(
        hand.typeName, equals('Windows.Win32.WindowsAndMessaging.HANDEDNESS'));
    expect(hand.parent?.typeName, equals('System.Enum'));

    expect(hand.fields.length, equals(3));

    expect(hand.fields[0].fieldAccess, equals(FieldAccess.public));
    expect(hand.fields[0].isSpecialName, isTrue);
    expect(hand.fields[0].isRTSpecialName, isTrue);
    expect(hand.fields[0].typeIdentifier.corType,
        equals(CorElementType.ELEMENT_TYPE_I4));
    expect(hand.fields[0].name, equals('value__'));

    expect(hand.fields[1].fieldAccess, equals(FieldAccess.public));
    expect(hand.fields[1].isStatic, isTrue);
    expect(hand.fields[1].isLiteral, isTrue);
    expect(hand.fields[1].typeIdentifier.corType,
        equals(CorElementType.ELEMENT_TYPE_VALUETYPE));
    expect(hand.fields[1].typeIdentifier.name,
        equals('Windows.Win32.WindowsAndMessaging.HANDEDNESS'));
    expect(hand.fields[1].name, equals('HANDEDNESS_LEFT'));
    expect(hand.fields[1].fieldType, equals(CorElementType.ELEMENT_TYPE_I4));
    expect(hand.fields[1].value, equals(0));

    expect(hand.fields[2].fieldAccess, equals(FieldAccess.public));
    expect(hand.fields[2].isStatic, isTrue);
    expect(hand.fields[2].isLiteral, isTrue);
    expect(hand.fields[2].typeIdentifier.corType,
        equals(CorElementType.ELEMENT_TYPE_VALUETYPE));
    expect(hand.fields[2].typeIdentifier.name,
        equals('Windows.Win32.WindowsAndMessaging.HANDEDNESS'));
    expect(hand.fields[2].name, equals('HANDEDNESS_RIGHT'));
    expect(hand.fields[2].fieldType, equals(CorElementType.ELEMENT_TYPE_I4));
    expect(hand.fields[2].value, equals(1));
  });
}
