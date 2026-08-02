package com.andre.video_ultra_player

internal data class TimelineEditSnapshot(
    val clips: List<TimelineClip>,
    val audioTrack: AudioTrackDescriptor?,
    val textOverlays: List<TextOverlayDescriptor>
)

internal class TimelineEditModel(
    private val limit: Int = 50
) {
    private val undoStack = ArrayDeque<TimelineEditSnapshot>()
    private val redoStack = ArrayDeque<TimelineEditSnapshot>()
    private val safeLimit = limit.coerceAtLeast(1)

    val canUndo: Boolean
        get() = undoStack.isNotEmpty()

    val canRedo: Boolean
        get() = redoStack.isNotEmpty()

    fun pushSnapshot(snapshot: TimelineEditSnapshot) {
        undoStack.addLast(snapshot)
        while (undoStack.size > safeLimit) {
            undoStack.removeFirst()
        }
        redoStack.clear()
    }

    fun undo(current: TimelineEditSnapshot): TimelineEditSnapshot? {
        val previous = undoStack.removeLastOrNull() ?: return null
        redoStack.addLast(current)
        while (redoStack.size > safeLimit) {
            redoStack.removeFirst()
        }
        return previous
    }

    fun redo(current: TimelineEditSnapshot): TimelineEditSnapshot? {
        val next = redoStack.removeLastOrNull() ?: return null
        undoStack.addLast(current)
        while (undoStack.size > safeLimit) {
            undoStack.removeFirst()
        }
        return next
    }
}
