import 'models.dart';

enum ReadingPeriod { all, today, week }

DateTime? readingStart(ReadingPeriod period, DateTime now) {
  if (period == ReadingPeriod.all) return null;
  final beijing = now.toUtc().add(const Duration(hours: 8));
  final start = DateTime.utc(
    beijing.year,
    beijing.month,
    beijing.day,
  ).subtract(const Duration(hours: 8));
  return period == ReadingPeriod.today
      ? start
      : start.subtract(const Duration(days: 6));
}

bool inReadingPeriod(Article article, ReadingPeriod period, DateTime now) {
  final start = readingStart(period, now);
  return start == null ||
      (!article.publishedAt.isBefore(start) &&
          !article.publishedAt.isAfter(now));
}

class ReadingSelection {
  const ReadingSelection({this.category = '', this.period = ReadingPeriod.all});
  final String category;
  final ReadingPeriod period;
}
