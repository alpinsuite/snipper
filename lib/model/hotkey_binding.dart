/// A key that can carry the global capture binding.
///
/// A closed set rather than anything the keyboard can produce. A system-wide
/// binding takes the key away from every other application on the machine, so
/// the ones offered here are the ones nothing else wants: the function row, the
/// print-screen key, and letters and digits, none of which is usable without a
/// modifier anyway.
enum HotkeyKey {
  printScreen('PrintScreen', 0x2C),
  f1('F1', 0x70),
  f2('F2', 0x71),
  f3('F3', 0x72),
  f4('F4', 0x73),
  f5('F5', 0x74),
  f6('F6', 0x75),
  f7('F7', 0x76),
  f8('F8', 0x77),
  f9('F9', 0x78),
  f10('F10', 0x79),
  f11('F11', 0x7A),
  f12('F12', 0x7B),
  a('A', 0x41),
  b('B', 0x42),
  c('C', 0x43),
  d('D', 0x44),
  e('E', 0x45),
  f('F', 0x46),
  g('G', 0x47),
  h('H', 0x48),
  i('I', 0x49),
  j('J', 0x4A),
  k('K', 0x4B),
  l('L', 0x4C),
  m('M', 0x4D),
  n('N', 0x4E),
  o('O', 0x4F),
  p('P', 0x50),
  q('Q', 0x51),
  r('R', 0x52),
  s('S', 0x53),
  t('T', 0x54),
  u('U', 0x55),
  v('V', 0x56),
  w('W', 0x57),
  x('X', 0x58),
  y('Y', 0x59),
  z('Z', 0x5A),
  digit0('0', 0x30),
  digit1('1', 0x31),
  digit2('2', 0x32),
  digit3('3', 0x33),
  digit4('4', 0x34),
  digit5('5', 0x35),
  digit6('6', 0x36),
  digit7('7', 0x37),
  digit8('8', 0x38),
  digit9('9', 0x39);

  const HotkeyKey(this.token, this.virtualKey);

  /// How the key is written, both in the interface and in the preferences
  /// file. One spelling, so what is shown is what is stored.
  final String token;

  /// The Win32 virtual-key code. Meaningless on Linux, where no in-process
  /// binding is attempted at all.
  final int virtualKey;

  static HotkeyKey? forToken(String token) {
    final wanted = token.toUpperCase();
    for (final key in HotkeyKey.values) {
      if (key.token.toUpperCase() == wanted) return key;
    }
    return null;
  }
}

/// A system-wide key combination.
///
/// Parsed from and written back to a single string, because that is what goes
/// into the preferences file and what a person reads in the settings dialog.
/// Round-tripping through one format means the two cannot disagree.
class HotkeyBinding {
  const HotkeyBinding({
    required this.key,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.win = false,
  });

  /// The default.
  ///
  /// Deliberately not Win+Shift+S: the Windows Snipping Tool owns that, and
  /// registering over it would either fail or take the key away from a tool
  /// somebody may still be using. A bare PrintScreen is also avoided — plenty
  /// of software already watches for it.
  static const HotkeyBinding defaultBinding = HotkeyBinding(
    key: HotkeyKey.printScreen,
    control: true,
    shift: true,
  );

  final HotkeyKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool win;

  /// At least one modifier, always.
  ///
  /// An unmodified system-wide binding takes a plain key away from every text
  /// field on the machine, which is not a thing a screenshot tool gets to do.
  bool get isUsable => control || shift || alt || win;

  /// Win32 `MOD_*` flags. The literals are from `winuser.h`; they are written
  /// out rather than imported so this stays a plain value type that a Linux
  /// build and a headless test can both hold.
  int get modifiers {
    var flags = 0;
    if (alt) flags |= 0x0001; // MOD_ALT
    if (control) flags |= 0x0002; // MOD_CONTROL
    if (shift) flags |= 0x0004; // MOD_SHIFT
    if (win) flags |= 0x0008; // MOD_WIN
    return flags;
  }

  int get virtualKey => key.virtualKey;

  /// The one spelling, used for both display and storage.
  ///
  /// Modifiers in the order every Windows application writes them, so it reads
  /// the way the same binding reads in any other program's settings.
  String get label => <String>[
    if (control) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    if (win) 'Win',
    key.token,
  ].join('+');

  /// The inverse of [label]. Null for anything unrecognised, so a preferences
  /// file written by a future version falls back to the default rather than
  /// stopping the application from starting.
  static HotkeyBinding? parse(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split('+').map((part) => part.trim()).toList();
    if (parts.isEmpty) return null;

    var control = false;
    var shift = false;
    var alt = false;
    var win = false;
    HotkeyKey? key;

    for (final part in parts) {
      switch (part.toLowerCase()) {
        case 'ctrl':
        case 'control':
          control = true;
        case 'shift':
          shift = true;
        case 'alt':
          alt = true;
        case 'win':
        case 'super':
        case 'meta':
          win = true;
        default:
          // Two keys in one binding is not a binding.
          if (key != null) return null;
          key = HotkeyKey.forToken(part);
          if (key == null) return null;
      }
    }

    if (key == null) return null;
    return HotkeyBinding(
      key: key,
      control: control,
      shift: shift,
      alt: alt,
      win: win,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HotkeyBinding &&
      other.key == key &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt &&
      other.win == win;

  @override
  int get hashCode => Object.hash(key, control, shift, alt, win);

  @override
  String toString() => 'HotkeyBinding($label)';
}
