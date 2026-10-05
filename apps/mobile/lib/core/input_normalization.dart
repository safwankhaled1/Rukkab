/// Accept Arabic and Persian digits from keyboards without changing names.
/// Remove invisible direction markers only when parsing numeric identifiers.
String normalizeDigits(String value) => value
    .replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
      final code = match[0]!.codeUnitAt(0);
      final start = code >= 0x06f0 ? 0x06f0 : 0x0660;
      return (code - start).toString();
    })
    .replaceAll(RegExp('[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '');

String normalizeNumber(String value) =>
    normalizeDigits(value.trim()).replaceAll('٫', '.').replaceAll('٬', '');
