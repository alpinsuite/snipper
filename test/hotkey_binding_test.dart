import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/model/hotkey_binding.dart';

void main() {
  group('the label is the storage format', () {
    test('round-trips', () {
      for (final binding in <HotkeyBinding>[
        HotkeyBinding.defaultBinding,
        const HotkeyBinding(key: HotkeyKey.printScreen),
        const HotkeyBinding(key: HotkeyKey.s, control: true, shift: true),
        const HotkeyBinding(key: HotkeyKey.f5, alt: true),
        const HotkeyBinding(key: HotkeyKey.digit4, win: true, control: true),
        const HotkeyBinding(
          key: HotkeyKey.a,
          control: true,
          shift: true,
          alt: true,
          win: true,
        ),
      ]) {
        // What the settings dialog shows and what goes into the preferences
        // file are the same string, so this is the only thing keeping them
        // from disagreeing.
        expect(
          HotkeyBinding.parse(binding.label),
          binding,
          reason: binding.label,
        );
      }
    });

    test('modifiers are written in the order Windows writes them', () {
      const binding = HotkeyBinding(
        key: HotkeyKey.printScreen,
        shift: true,
        control: true,
        win: true,
        alt: true,
      );
      expect(binding.label, 'Ctrl+Alt+Shift+Win+PrintScreen');
    });

    test('the default is Ctrl+Shift+PrintScreen', () {
      // Not Win+Shift+S: the Windows Snipping Tool owns that one.
      expect(HotkeyBinding.defaultBinding.label, 'Ctrl+Shift+PrintScreen');
    });
  });

  group('parsing', () {
    test('accepts the spellings people actually type', () {
      expect(
        HotkeyBinding.parse('control+shift+PrintScreen'),
        HotkeyBinding.defaultBinding,
      );
      expect(
        HotkeyBinding.parse('CTRL + SHIFT + printscreen'),
        HotkeyBinding.defaultBinding,
      );
      expect(
        HotkeyBinding.parse('Super+F1'),
        const HotkeyBinding(key: HotkeyKey.f1, win: true),
      );
    });

    test('refuses what it cannot represent', () {
      // A preferences file from a future version, or edited by hand. Falling
      // back to the default beats refusing to start.
      expect(HotkeyBinding.parse(null), isNull);
      expect(HotkeyBinding.parse(''), isNull);
      expect(HotkeyBinding.parse('Ctrl'), isNull);
      expect(HotkeyBinding.parse('Ctrl+Shift'), isNull);
      expect(HotkeyBinding.parse('Ctrl+Tab'), isNull);
      expect(HotkeyBinding.parse('Ctrl+A+B'), isNull);
    });
  });

  group('what gets sent to Windows', () {
    test('the modifier flags are the MOD_ constants', () {
      expect(
        const HotkeyBinding(key: HotkeyKey.a, alt: true).modifiers,
        0x0001,
      );
      expect(
        const HotkeyBinding(key: HotkeyKey.a, control: true).modifiers,
        0x0002,
      );
      expect(
        const HotkeyBinding(key: HotkeyKey.a, shift: true).modifiers,
        0x0004,
      );
      expect(
        const HotkeyBinding(key: HotkeyKey.a, win: true).modifiers,
        0x0008,
      );
      expect(HotkeyBinding.defaultBinding.modifiers, 0x0002 | 0x0004);
    });

    test('the virtual keys are the VK_ codes', () {
      expect(HotkeyKey.printScreen.virtualKey, 0x2C); // VK_SNAPSHOT
      expect(HotkeyKey.a.virtualKey, 0x41);
      expect(HotkeyKey.z.virtualKey, 0x5A);
      expect(HotkeyKey.digit0.virtualKey, 0x30);
      expect(HotkeyKey.f1.virtualKey, 0x70);
      expect(HotkeyKey.f12.virtualKey, 0x7B);
    });

    test('every key has a distinct code and token', () {
      final codes = HotkeyKey.values.map((key) => key.virtualKey).toSet();
      final tokens = HotkeyKey.values.map((key) => key.token).toSet();
      expect(codes, hasLength(HotkeyKey.values.length));
      expect(tokens, hasLength(HotkeyKey.values.length));
    });
  });

  test('a binding with no modifier is not usable', () {
    // A system-wide binding on a bare letter takes it away from every text
    // field on the machine.
    expect(const HotkeyBinding(key: HotkeyKey.a).isUsable, isFalse);
    expect(
      const HotkeyBinding(key: HotkeyKey.a, control: true).isUsable,
      isTrue,
    );
  });
}
