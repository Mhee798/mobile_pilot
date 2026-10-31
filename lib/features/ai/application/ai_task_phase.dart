/// Lifecycle observed by the app. A response does not establish task success.
enum AiTaskPhase {
  idle,
  thinking,
  usingTool,
  waitingForUser,
  stopping,
  responded,
  stopped,
  failed,
}
