import 'package:flutter/foundation.dart';

/// A single word of a caption cue with its own presentation window, used by
/// the karaoke highlight mode.
///
/// [start] and [end] are relative to the timeline; the word is highlighted
/// during `[start, end)` when the parent style has `karaoke = true`.
@immutable
class TimelineCaptionWord {
  /// Creates a [TimelineCaptionWord].
  ///
  /// Throws [ArgumentError] when [end] is not greater than [start].
  TimelineCaptionWord({
    required this.text,
    required this.start,
    required this.end,
  }) {
    if (end <= start) {
      throw ArgumentError.value(
        end,
        'end',
        'Must be greater than start.',
      );
    }
  }

  /// The word text (without surrounding whitespace).
  final String text;

  /// Start of the word highlight window on the timeline.
  final Duration start;

  /// End of the word highlight window. The word is active in `[start, end)`.
  final Duration end;

  /// Serialises this [TimelineCaptionWord] to a JSON-compatible map for the
  /// method channel. Durations are expressed in milliseconds.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'text': text,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineCaptionWord &&
          text == other.text &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(text, start, end);
}

/// One caption cue: [text] visible on the video during `[start, end)`.
///
/// [words] carries the per-word windows needed by the karaoke style; it is
/// serialised as an empty list (never `null`) so the native side never
/// receives a null `words` value.
@immutable
class TimelineCaptionCue {
  /// Creates a [TimelineCaptionCue].
  ///
  /// Throws [ArgumentError] when [end] is not greater than [start].
  TimelineCaptionCue({
    required this.text,
    required this.start,
    required this.end,
    this.words = const <TimelineCaptionWord>[],
  }) {
    if (end <= start) {
      throw ArgumentError.value(
        end,
        'end',
        'Must be greater than start.',
      );
    }
  }

  /// Text content of the cue (may contain multiple lines via `\n`).
  final String text;

  /// Start of the visibility window on the timeline.
  final Duration start;

  /// End of the visibility window. The cue is visible in `[start, end)`.
  final Duration end;

  /// Per-word windows used by the karaoke style. Empty when the style is not
  /// karaoke or the ASR provider did not return word timestamps.
  final List<TimelineCaptionWord> words;

  /// Serialises this [TimelineCaptionCue] to a JSON-compatible map for the
  /// method channel. Durations are expressed in milliseconds.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'text': text,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'words': words.map((word) => word.toMap()).toList(growable: false),
  };

  /// Returns a copy with the given fields replaced.
  TimelineCaptionCue copyWith({
    String? text,
    Duration? start,
    Duration? end,
    List<TimelineCaptionWord>? words,
  }) => TimelineCaptionCue(
    text: text ?? this.text,
    start: start ?? this.start,
    end: end ?? this.end,
    words: words ?? this.words,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineCaptionCue &&
          text == other.text &&
          start == other.start &&
          end == other.end &&
          listEquals(words, other.words);

  @override
  int get hashCode => Object.hash(text, start, end, Object.hashAll(words));
}

/// Visual style applied to every caption cue on the timeline.
///
/// [fontSize] is a fraction of the video height, [positionY] is the center of
/// the caption block in normalized frame coordinates (`0.0` is the top edge,
/// `1.0` the bottom edge). [strokeWidth] is a fraction of the video height
/// (`0.0` disables the outline). [backgroundOpacity] is the opacity of the
/// black box behind the text in `[0.0, 1.0]` (`0.0` draws no background).
/// Colors are ARGB ints.
@immutable
class TimelineCaptionStyle {
  /// Creates a [TimelineCaptionStyle].
  const TimelineCaptionStyle({
    this.color = 0xFFFFFFFF,
    this.fontSize = 0.055,
    this.positionY = 0.85,
    this.uppercase = false,
    this.karaoke = false,
    this.strokeWidth = 0.0,
    this.backgroundOpacity = 0.0,
    this.highlightColor = 0xFFFFD700,
  }) : assert(fontSize > 0.0 && fontSize <= 1.0),
       assert(positionY >= 0.0 && positionY <= 1.0),
       assert(strokeWidth >= 0.0),
       assert(backgroundOpacity >= 0.0 && backgroundOpacity <= 1.0);

  /// ARGB color of the caption text. Default is opaque white (`0xFFFFFFFF`).
  final int color;

  /// Font size as a fraction of the video height, in `(0.0, 1.0]`.
  final double fontSize;

  /// Center of the caption block in normalized frame coordinates, in
  /// `[0.0, 1.0]` (`0.0` is the top edge, `1.0` the bottom edge).
  final double positionY;

  /// Whether the caption text is rendered uppercase.
  final bool uppercase;

  /// Whether the active word is highlighted as the video plays (karaoke mode).
  final bool karaoke;

  /// Stroke (outline) width as a fraction of the video height. `0.0` disables
  /// the outline.
  final double strokeWidth;

  /// Opacity of the black background box behind the text in `[0.0, 1.0]`.
  /// `0.0` draws no background.
  final double backgroundOpacity;

  /// ARGB color of the active-word highlight in karaoke mode.
  final int highlightColor;

  /// Serialises this [TimelineCaptionStyle] to a JSON-compatible map for the
  /// method channel.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'color': color,
    'fontSize': fontSize,
    'positionY': positionY,
    'uppercase': uppercase,
    'karaoke': karaoke,
    'strokeWidth': strokeWidth,
    'backgroundOpacity': backgroundOpacity,
    'highlightColor': highlightColor,
  };

  /// Returns a copy with the given fields replaced.
  TimelineCaptionStyle copyWith({
    int? color,
    double? fontSize,
    double? positionY,
    bool? uppercase,
    bool? karaoke,
    double? strokeWidth,
    double? backgroundOpacity,
    int? highlightColor,
  }) => TimelineCaptionStyle(
    color: color ?? this.color,
    fontSize: fontSize ?? this.fontSize,
    positionY: positionY ?? this.positionY,
    uppercase: uppercase ?? this.uppercase,
    karaoke: karaoke ?? this.karaoke,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    highlightColor: highlightColor ?? this.highlightColor,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineCaptionStyle &&
          color == other.color &&
          fontSize == other.fontSize &&
          positionY == other.positionY &&
          uppercase == other.uppercase &&
          karaoke == other.karaoke &&
          strokeWidth == other.strokeWidth &&
          backgroundOpacity == other.backgroundOpacity &&
          highlightColor == other.highlightColor;

  @override
  int get hashCode => Object.hash(
    color,
    fontSize,
    positionY,
    uppercase,
    karaoke,
    strokeWidth,
    backgroundOpacity,
    highlightColor,
  );
}
