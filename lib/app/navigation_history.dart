/// Browser-style forward history.
///
/// Going back records how to redo that step; any other navigation clears what was recorded,
/// just like a browser drops its forward pages when you open a new one.
class NavigationHistory {
  final _forward = <Future<void> Function()>[];
  bool _replaying = false;

  bool get canGoForward => _forward.isNotEmpty;

  /// Records a step that was just undone by going back; [redo] repeats it.
  void recordBack(Future<void> Function() redo) => _forward.add(redo);

  /// Called on navigation that isn't back/forward. Ignored while a forward step is being replayed.
  void clearForward() {
    if (!_replaying) _forward.clear();
  }

  /// Repeats the most recently undone step.
  Future<void> goForward() async {
    if (_forward.isEmpty) return;
    final redo = _forward.removeLast();
    // Only the synchronous start of the step counts as replaying; it is where navigation is recorded.
    _replaying = true;
    final Future<void> done;
    try {
      done = redo();
    } finally {
      _replaying = false;
    }
    await done;
  }
}
