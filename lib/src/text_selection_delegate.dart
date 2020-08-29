import 'package:flutter/services.dart';

/// An interface for manipulating the selection, to be used by the implementor
/// of the toolbar widget.
abstract class ToolbarTextSelectionDelegate {
  /// Gets the current text input.
  TextEditingValue get textEditingValue;

  /// Sets the current text input (replaces the whole line).
  set textEditingValue(TextEditingValue value);

  /// Hides the text selection toolbar.
  void hideToolbar();

  /// Brings the provided [TextPosition] into the visible area of the text
  /// input.
  void bringIntoView(TextPosition position);
}
