/// Astronomical calculation engine for solar events.
///
/// This library implements a simplified version of the NOAA Solar Position
/// Algorithm (SPA) to compute sunrise, sunset, and solar noon times for
/// any geographic location on Earth.
///
/// ## Algorithm Overview
///
/// The calculator uses the Julian day and Earth's orbital parameters to
/// estimate the Sun's position. It accounts for:
/// - Earth's eccentricity and axial tilt.
/// - Atmospheric refraction (via a standard zenith of 90.833°).
/// - Equation of Time (discrepancy between solar and clock time).
///
/// ## Precision
///
/// While suitable for task scheduling, this implementation is an approximation.
/// Accuracy is typically within ±1-2 minutes for mid-latitudes but decreases
/// near the poles or during extreme solar atmospheric conditions.
library;

import 'dart:math';

import 'package:stem/src/scheduler/schedule_spec.dart';
import 'package:timezone/timezone.dart' as tz;

/// Computes solar events (sunrise, sunset, solar noon) using NOAA SPA
/// approximations.
class SolarCalculator {
  /// Creates a solar calculator instance.
  const SolarCalculator();

  /// Standard zenith angle for sunrise/sunset (90° 50'), accounting for
  /// the solar disk radius and typical atmospheric refraction.
  static const double _zenith = 90.8333; // degrees

  /// Computes the next solar event for the given [spec].
  ///
  /// ## Algorithm
  ///
  /// 1. Starts from the date of [fromUtc].
  /// 2. Iterates forward day-by-day (up to 400 days) calculating the
  ///    specific `spec.event` time for each day.
  /// 3. Returns the first event time that is `>= fromUtc`.
  /// 4. If [location] is provided, the result is correctly mapped to that
  ///    timezone while remaining a UTC [DateTime].
  ///
  /// ## Throws
  ///
  /// - [StateError] if no such event can be computed within a year (e.g.,
  ///   polar day/night).
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
        case 'sunset':
          candidate = sunset;
        case 'noon':
          candidate = solarNoon;
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

  /// Internal implementation of the solar position math.
  ///
  /// ## Implementation Details
  ///
  /// This method performs the heavy lifting of the orbital mechanics math.
  /// It follows the standard astronomical procedure:
  /// 1. Calculate the day of the year and approximate solar time.
  /// 2. Compute the Sun's mean anomaly and true longitude.
  /// 3. Determine the Sun's right ascension and declination.
  /// 4. Calculate the local hour angle for the specified [event].
  /// 5. Convert local mean time to UTC.
  ///
  /// ## Parameters
  ///
  /// - [date]: The target calendar date (midnight UTC).
  /// - [latitude]: Observer latitude in degrees.
  /// - [longitude]: Observer longitude in degrees.
  /// - [event]: The specific celestial event to solve for.
  ///
  /// ## Returns
  ///
  /// A UTC [DateTime] for the event, or `null` if the event does not occur
  /// on that date (common in arctic regions).
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
      // Event doesn't occur (Polar Day or Polar Night)
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

  /// Returns the 1-based day of the year.
  int _dayOfYear(DateTime date) {
    final start = DateTime.utc(date.year);
    return date.difference(start).inDays + 1;
  }

  /// Converts degrees to radians.
  double _degToRad(double deg) => deg * (pi / 180.0);

  /// Converts radians to degrees.
  double _radToDeg(double rad) => rad * (180.0 / pi);

  /// Keeps an angle within the [0, 360) range.
  double _normalizeAngle(double angle) {
    var result = angle % 360;
    if (result < 0) result += 360;
    return result;
  }
}

/// Supported solar events for scheduling.
enum SolarEvent {
  /// The moment when the top of the Sun appears on the horizon.
  sunrise,

  /// The moment when the top of the Sun disappears below the horizon.
  sunset,

  /// The moment when the Sun is at its highest point in the sky.
  noon,
}
