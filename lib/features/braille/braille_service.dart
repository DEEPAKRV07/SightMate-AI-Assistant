// lib/features/braille/braille_service.dart
// Complete Braille Grade 1 dot-to-character mapping
// Standard 6-dot Braille cell (dots 1-6, two-column left-to-right layout):
//
//   1 4
//   2 5
//   3 6
//
// Note: In full Grade 1 Braille, letters and numbers share the same dot patterns.
// A Number Indicator cell (dots 3-4-5-6) prefixes numeric sequences.
// This implementation uses letters by default; numbers require the number
// indicator prefix cell (handled in braille_page.dart if needed).

class BrailleService {
  static const Map<String, String> _brailleMap = {
    // ── Letters (a-z) ──────────────────────────────────────────────────────
    '1'       : 'a',
    '12'      : 'b',
    '14'      : 'c',
    '145'     : 'd',
    '15'      : 'e',
    '124'     : 'f',
    '1245'    : 'g',
    '125'     : 'h',
    '24'      : 'i',
    '245'     : 'j',
    '13'      : 'k',
    '123'     : 'l',
    '134'     : 'm',
    '1345'    : 'n',
    '135'     : 'o',
    '1234'    : 'p',
    '12345'   : 'q',
    '1235'    : 'r',
    '234'     : 's',
    '2345'    : 't',
    '136'     : 'u',
    '1236'    : 'v',
    '2456'    : 'w',
    '1346'    : 'x',
    '13456'   : 'y',
    '1356'    : 'z',

    // ── Punctuation ─────────────────────────────────────────────────────────
    '2'       : ',',
    '23'      : ';',
    '25'      : ':',
    '256'     : '.',
    '236'     : '!',
    '235'     : '?',
    '36'      : '-',
    '356'     : '"',
    '3'       : '\'',
    '346'     : '(',
    '3456'    : ')',

    // ── Control characters ───────────────────────────────────────────────────
    ''        : ' ',  // No dots pressed → space
  };

  /// Convert a set of active dot numbers (1-6) to a Braille character.
  static String convertDots(Set<int> dots) {
    final key = (dots.toList()..sort()).join();
    return _brailleMap[key] ?? '';
  }

  /// Human-readable label for a dot combination.
  static String dotsLabel(Set<int> dots) {
    if (dots.isEmpty) return 'space';
    final sorted = (dots.toList()..sort());
    return 'dots ${sorted.join(',')}';
  }

  /// Returns all dot patterns and their characters (for reference/debug).
  static Map<String, String> get allMappings => Map.unmodifiable(_brailleMap);
}
