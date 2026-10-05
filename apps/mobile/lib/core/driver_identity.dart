// Share validation between independent driver signup and identity updates.
// The server enforces the same rules; no client field can promote a rider.
import 'input_normalization.dart';

String normalizePhone(String value) {
  var phone = normalizeDigits(value);
  phone = phone.replaceAll(RegExp(r'[\s()\-]'), '');
  if (phone.startsWith('00')) phone = '+${phone.substring(2)}';
  if (RegExp(r'^05[0-9]{8}$').hasMatch(phone)) {
    phone = '+970${phone.substring(1)}';
  }
  if (RegExp(r'^5[0-9]{8}$').hasMatch(phone)) phone = '+970$phone';
  if (RegExp(r'^(970|972)[0-9]{9}$').hasMatch(phone)) phone = '+$phone';
  return phone;
}

bool validDriverName(String value) =>
    value.trim().length <= 120 &&
    value.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length >= 2;
bool validDriverPhone(String value) =>
    RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(normalizePhone(value));
String dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
