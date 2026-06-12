import Foundation

struct TimelineEditSnapshot {
  let clips: [TimelineClipDescriptor]
  let audioTrack: AudioTrackDescriptor?
}

final class TimelineEditModel {
  private let limit: Int
  private var undoStack: [TimelineEditSnapshot] = []
  private var redoStack: [TimelineEditSnapshot] = []

  init(limit: Int = 50) {
    self.limit = max(limit, 1)
  }

  var canUndo: Bool {
    return !undoStack.isEmpty
  }

  var canRedo: Bool {
    return !redoStack.isEmpty
  }

  func pushSnapshot(_ snapshot: TimelineEditSnapshot) {
    undoStack.append(snapshot)
    if undoStack.count > limit {
      undoStack.removeFirst(undoStack.count - limit)
    }
    redoStack.removeAll()
  }

  func undo(current: TimelineEditSnapshot) -> TimelineEditSnapshot? {
    guard let previous = undoStack.popLast() else {
      return nil
    }
    redoStack.append(current)
    if redoStack.count > limit {
      redoStack.removeFirst(redoStack.count - limit)
    }
    return previous
  }

  func redo(current: TimelineEditSnapshot) -> TimelineEditSnapshot? {
    guard let next = redoStack.popLast() else {
      return nil
    }
    undoStack.append(current)
    if undoStack.count > limit {
      undoStack.removeFirst(undoStack.count - limit)
    }
    return next
  }
}
