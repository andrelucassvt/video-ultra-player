import 'package:flutter/foundation.dart';

/// Whether the native edit-history stacks can currently undo or redo.
@immutable
class EditHistoryState {
  /// Creates an edit-history state.
  const EditHistoryState({
    required this.canUndo,
    required this.canRedo,
  });

  /// Whether an undo snapshot is available.
  final bool canUndo;

  /// Whether a redo snapshot is available.
  final bool canRedo;

  /// Deserialises an [EditHistoryState] from a native event map.
  factory EditHistoryState.fromMap(Map<dynamic, dynamic> map) {
    return EditHistoryState(
      canUndo: map['canUndo'] == true,
      canRedo: map['canRedo'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EditHistoryState &&
        other.canUndo == canUndo &&
        other.canRedo == canRedo;
  }

  @override
  int get hashCode => Object.hash(canUndo, canRedo);
}
