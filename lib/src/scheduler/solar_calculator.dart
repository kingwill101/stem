import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

import 'schedule_spec.dart';

/// Computes solar events (sunrise, sunset, solar noon) using NOAA SPA approximations.
class SolarCalculator {
  const SolarCalculator();

  static const double _zenith = 90.8333; // degrees

  DateTime nextEvent(
    SolarScheduleSpec spec,
    DateTime fromUtc,
    tz.Location? location,
  ) {
    var date = DateTime.utc(fromUtc.year, fromUtc.month, fromUtc.day);
    for (var i = 0; i < 400; i++) {
      final sunrise = _calculate(
        date,
        spec.latitude,
        spec.longitude,
        SolarEvent.sunrise,
      );
      final sunset = _calculate(
        date,
        spec.latitude,
        spec.longitude,
        SolarEvent.sunset,
      );
      final solarNoon = _calculate(
        date,
        spec.latitude,
        spec.longitude,
        SolarEvent.noon,
      );
      DateTime? candidate;
      switch (spec.event) {
        case 'sunrise':
          candidate = sunrise;
          break;
        case 'sunset':
          candidate = sunset;
          break;
        case 'noon':
          candidate = solarNoon;
          break;
      }
      if (candidate != null && !candidate.isBefore(fromUtc)) {
        return location != null
            ? tz.TZDateTime.from(candidate, location).toUtc()
            : candidate;
      }
      date = date.add(const Duration(days: 1));
    }
    throw StateError('Unable to compute solar event for ${spec.event}');
  }

  DateTime? _calculate(
    DateTime date,
    double latitude,
    double longitude,
    SolarEvent event,
  ) {
    final lngHour = longitude / 15.0;
    final dayOfYear = _dayOfYear(date);
    final approx = event == SolarEvent.sunrise
        ? dayOfYear + ((6 - lngHour) / 24)
        : dayOfYear + ((18 - lngHour) / 24);

    final meanAnomaly = (0.9856 * approx) - 3.289;
    var trueLongitude =
        meanAnomaly +
        (1.916 * sin(_degToRad(meanAnomaly))) +
        (0.020 * sin(_degToRad(2 * meanAnomaly))) +
        282.634;
    trueLongitude = _normalizeAngle(trueLongitude);

    var rightAscension = _radToDeg(
      atan(0.91764 * tan(_degToRad(trueLongitude))),
    );
    rightAscension = _normalizeAngle(rightAscension);
    final quadrant = (trueLongitude / 90).floor() * 90;
    final raQuadrant = (rightAscension / 90).floor() * 90;
    rightAscension += quadrant - raQuadrant;
    rightAscension /= 15.0;

    final sinDec = 0.39782 * sin(_degToRad(trueLongitude));
    final cosDec = cos(asin(sinDec));

    final cosH =
        (cos(_degToRad(_zenith)) - (sinDec * sin(_degToRad(latitude)))) /
        (cosDec * cos(_degToRad(latitude)));

    if (cosH.abs() > 1) {
      return null;
    }

    double hourAngle;
    if (event == SolarEvent.sunrise) {
      hourAngle = 360 - _radToDeg(acos(cosH));
    } else if (event == SolarEvent.sunset) {
      hourAngle = _radToDeg(acos(cosH));
    } else {
      hourAngle = 180;
    }
    hourAngle /= 15.0;

    final localMeanTime =
        hourAngle + rightAscension - (0.06571 * approx) - 6.622;
    var utcTime = localMeanTime - lngHour;
    utcTime = (utcTime + 24) % 24;

    final hours = utcTime.floor();
    final minutes = ((utcTime - hours) * 60).floor();
    final seconds = ((((utcTime - hours) * 60) - minutes) * 60).round();
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      hours,
      minutes,
      seconds,
    );
  }

  int _dayOfYear(DateTime date) {
    final start = DateTime.utc(date.year, 1, 1);
    return date.difference(start).inDays + 1;
  }

  double _degToRad(double deg) => deg * (pi / 180.0);

  double _radToDeg(double rad) => rad * (180.0 / pi);

  double _normalizeAngle(double angle) {
    var result = angle % 360;
    if (result < 0) result += 360;
    return result;
  }
}

enum SolarEvent { sunrise, sunset, noon }
