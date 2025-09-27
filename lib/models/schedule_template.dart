import 'package:cloud_firestore/cloud_firestore.dart';

/// Auto-schedule template configuration for a group.
class ScheduleTemplate {
  /// Whether automatic schedule creation is enabled.
  final bool active;

  /// IANA timezone identifier, e.g. "UTC" or "America/Los_Angeles".
  final String timezone;

  /// Local start time in 24h format HH:mm (optional, currently informational).
  final String startTimeLocal;

  /// Optional duration in minutes.
  final int? durationMinutes;

  /// Optional recurrence rule (RFC 5545). Defaults to daily.
  final String rrule;

  /// Creates a [ScheduleTemplate].
  const ScheduleTemplate({
    required this.active,
    required this.timezone,
    required this.startTimeLocal,
    this.durationMinutes,
    this.rrule = 'FREQ=DAILY;INTERVAL=1',
  });

  /// Default template with daily recurrence at midnight UTC.
  factory ScheduleTemplate.defaultUtc() =>
      const ScheduleTemplate(active: false, timezone: 'UTC', startTimeLocal: '00:00');

  /// Reads a [ScheduleTemplate] from a Firestore document.
  factory ScheduleTemplate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ScheduleTemplate(
      active: (data['active'] as bool?) ?? false,
      timezone: (data['timezone'] as String?)?.trim().isNotEmpty == true
          ? (data['timezone'] as String)
          : 'UTC',
      startTimeLocal: (data['startTimeLocal'] as String?)?.trim().isNotEmpty == true
          ? (data['startTimeLocal'] as String)
          : '00:00',
      durationMinutes: (data['durationMinutes'] as num?)?.toInt(),
      rrule: (data['rrule'] as String?)?.trim().isNotEmpty == true
          ? (data['rrule'] as String)
          : 'FREQ=DAILY;INTERVAL=1',
    );
  }

  /// Serializes this template for Firestore.
  Map<String, dynamic> toFirestore() => {
        'active': active,
        'timezone': timezone,
        'startTimeLocal': startTimeLocal,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'rrule': rrule,
      };

  ScheduleTemplate copyWith({
    bool? active,
    String? timezone,
    String? startTimeLocal,
    int? durationMinutes,
    String? rrule,
  }) =>
      ScheduleTemplate(
        active: active ?? this.active,
        timezone: timezone ?? this.timezone,
        startTimeLocal: startTimeLocal ?? this.startTimeLocal,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        rrule: rrule ?? this.rrule,
      );
}

