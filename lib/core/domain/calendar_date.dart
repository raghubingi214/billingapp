/// Strict calendar dates, independent of device time zone and clock changes.
class CalendarDate {
  static DateTime? parse(String? value) {
    if (value == null ||
        value.length != 10 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static String? error(String? value) =>
      parse(value) == null ? 'Enter a valid date (YYYY-MM-DD)' : null;

  static String? rangeError(String from, String to, {int? maximumDays}) {
    final start = parse(from), end = parse(to);
    if (start == null || end == null) return null;
    if (start.isAfter(end)) return 'From date must be on or before To date';
    if (maximumDays != null && end.difference(start).inDays > maximumDays) {
      return 'Date range must span no more than $maximumDays days';
    }
    return null;
  }
}
