/// Owns the media files imported by the editor.
///
/// Files picked from the system (gallery via `ImagePicker`) live in
/// picker-owned caches that the OS may purge at any moment. Importing them
/// into a controlled session directory keeps the timeline stable for the whole
/// editing session (and for export).
abstract class EditorMediaSessionService {
  /// Copies [sourcePath] into the current session and returns the owned path.
  Future<String> importFile(String sourcePath);

  /// Deletes [ownedPath] if it belongs to the controlled session directory.
  Future<void> releaseFile(String ownedPath);

  /// Deletes the whole current session, releasing every imported file.
  Future<void> clearSession();
}
