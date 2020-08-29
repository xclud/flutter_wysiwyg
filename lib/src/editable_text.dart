// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';

import 'render_editable_with_toolbar.dart';
import 'selectable_text_with_toolbar.dart';
import 'text_selection_delegate.dart';
import 'toolbar_container.dart';
import 'toolbar_items.dart';

/// The text position that a give selection handle manipulates. Dragging the
/// [start] handle always moves the [start]/[baseOffset] of the selection.
enum _TextSelectionHandlePosition { start, end }

/// An interface for building the selection UI, to be provided by the
/// implementor of the toolbar widget.
abstract class TextSelectionWithToolbarControls {
  /// Builds a selection handle of the given type.
  ///
  /// The top left corner of this widget is positioned at the bottom of the
  /// selection position.
  Widget buildHandle(BuildContext context, TextSelectionHandleType type,
      double textLineHeight);

  /// Get the anchor point of the handle relative to itself. The anchor point is
  /// the point that is aligned with a specific point in the text. A handle
  /// often visually "points to" that location.
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight);

  /// Builds a toolbar near a text selection.
  ///
  /// Typically displays buttons for copying and pasting text.
  ///
  /// [globalEditableRegion] is the TextField size of the global coordinate system
  /// in logical pixels.
  ///
  /// [textLineHeight] is the `preferredLineHeight` of the [RenderEditableWithToolbar] we
  /// are building a toolbar for.
  ///
  /// The [position] is a general calculation midpoint parameter of the toolbar.
  /// If you want more detailed position information, can use [endpoints]
  /// to calculate it.
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset position,
    List<TextSelectionPoint> endpoints,
    ToolbarBuilder toolbarBuilder,
    ToolbarTextSelectionDelegate delegate,
  );

  /// Returns the size of the selection handle.
  Size getHandleSize(double textLineHeight);
}

/// An object that manages a pair of text selection handles.
///
/// The selection handles are displayed in the [Overlay] that most closely
/// encloses the given [BuildContext].
class TextSelectionWithToolbarOverlay {
  /// Creates an object that manages overlay entries for selection handles.
  ///
  /// The [context] must not be null and must have an [Overlay] as an ancestor.
  TextSelectionWithToolbarOverlay({
    @required TextEditingValue value,
    @required this.context,
    this.debugRequiredFor,
    @required this.toolbarLayerLink,
    @required this.startHandleLayerLink,
    @required this.endHandleLayerLink,
    @required this.renderObject,
    this.selectionControls,
    bool handlesVisible = false,
    this.selectionDelegate,
    @required this.toolbarBuilder,
    this.dragStartBehavior = DragStartBehavior.start,
    this.onSelectionHandleTapped,
  })  : assert(value != null),
        assert(context != null),
        assert(handlesVisible != null),
        _handlesVisible = handlesVisible,
        _value = value {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    assert(
        overlay != null,
        'No Overlay widget exists above $context.\n'
        'Usually the Navigator created by WidgetsApp provides the overlay. Perhaps your '
        'app content was created above the Navigator with the WidgetsApp builder parameter.');
    _toolbarController =
        AnimationController(duration: fadeDuration, vsync: overlay);
  }

  /// The context in which the selection handles should appear.
  ///
  /// This context must have an [Overlay] as an ancestor because this object
  /// will display the text selection handles in that [Overlay].
  final BuildContext context;

  /// Debugging information for explaining why the [Overlay] is required.
  final Widget debugRequiredFor;

  /// The object supplied to the [CompositedTransformTarget] that wraps the text
  /// field.
  final LayerLink toolbarLayerLink;

  /// The objects supplied to the [CompositedTransformTarget] that wraps the
  /// location of start selection handle.
  final LayerLink startHandleLayerLink;

  /// The objects supplied to the [CompositedTransformTarget] that wraps the
  /// location of end selection handle.
  final LayerLink endHandleLayerLink;

  // moves? Not sure what cases I need to handle, or how to handle them.
  /// The editable line in which the selected text is being displayed.
  final RenderEditableWithToolbar renderObject;

  /// Builds text selection handles and toolbar.
  final TextSelectionWithToolbarControls selectionControls;

  /// The delegate for manipulating the current selection in the owning
  /// text field.
  final ToolbarBuilder toolbarBuilder;

  /// The delegate for manipulating the current selection in the owning
  /// text field.
  final ToolbarTextSelectionDelegate selectionDelegate;

  /// Determines the way that drag start behavior is handled.
  ///
  /// If set to [DragStartBehavior.start], handle drag behavior will
  /// begin upon the detection of a drag gesture. If set to
  /// [DragStartBehavior.down] it will begin when a down event is first detected.
  ///
  /// In general, setting this to [DragStartBehavior.start] will make drag
  /// animation smoother and setting it to [DragStartBehavior.down] will make
  /// drag behavior feel slightly more reactive.
  ///
  /// By default, the drag start behavior is [DragStartBehavior.start].
  ///
  /// See also:
  ///
  ///  * [DragGestureRecognizer.dragStartBehavior], which gives an example for the different behaviors.
  final DragStartBehavior dragStartBehavior;

  /// {@template flutter.widgets.textSelection.onSelectionHandleTapped}
  /// A callback that's invoked when a selection handle is tapped.
  ///
  /// Both regular taps and long presses invoke this callback, but a drag
  /// gesture won't.
  /// {@endtemplate}
  final VoidCallback onSelectionHandleTapped;

  /// Controls the fade-in and fade-out animations for the toolbar and handles.
  static const Duration fadeDuration = Duration(milliseconds: 150);

  AnimationController _toolbarController;
  Animation<double> get _toolbarOpacity => _toolbarController.view;

  /// Retrieve current value.
  @visibleForTesting
  TextEditingValue get value => _value;

  TextEditingValue _value;

  /// A pair of handles. If this is non-null, there are always 2, though the
  /// second is hidden when the selection is collapsed.
  List<OverlayEntry> _handles;

  /// A copy/paste toolbar.
  OverlayEntry _toolbar;

  TextSelection get _selection => _value.selection;

  /// Whether selection handles are visible.
  ///
  /// Set to false if you want to hide the handles. Use this property to show or
  /// hide the handle without rebuilding them.
  ///
  /// If this method is called while the [SchedulerBinding.schedulerPhase] is
  /// [SchedulerPhase.persistentCallbacks], i.e. during the build, layout, or
  /// paint phases (see [WidgetsBinding.drawFrame]), then the update is delayed
  /// until the post-frame callbacks phase. Otherwise the update is done
  /// synchronously. This means that it is safe to call during builds, but also
  /// that if you do call this during a build, the UI will not update until the
  /// next frame (i.e. many milliseconds later).
  ///
  /// Defaults to false.
  bool get handlesVisible => _handlesVisible;
  bool _handlesVisible = false;
  set handlesVisible(bool visible) {
    assert(visible != null);
    if (_handlesVisible == visible) return;
    _handlesVisible = visible;
    // If we are in build state, it will be too late to update visibility.
    // We will need to schedule the build in next frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(_markNeedsBuild);
    } else {
      _markNeedsBuild();
    }
  }

  /// Builds the handles by inserting them into the [context]'s overlay.
  void showHandles() {
    assert(_handles == null);
    _handles = <OverlayEntry>[
      OverlayEntry(
          builder: (BuildContext context) =>
              _buildHandle(context, _TextSelectionHandlePosition.start)),
      OverlayEntry(
          builder: (BuildContext context) =>
              _buildHandle(context, _TextSelectionHandlePosition.end)),
    ];

    Overlay.of(context, rootOverlay: true, debugRequiredFor: debugRequiredFor)
        .insertAll(_handles);
  }

  /// Destroys the handles by removing them from overlay.
  void hideHandles() {
    if (_handles != null) {
      _handles[0].remove();
      _handles[1].remove();
      _handles = null;
    }
  }

  /// Shows the toolbar by inserting it into the [context]'s overlay.
  void showToolbar() {
    assert(_toolbar == null);
    _toolbar = OverlayEntry(builder: _buildToolbar);
    Overlay.of(context, rootOverlay: true, debugRequiredFor: debugRequiredFor)
        .insert(_toolbar);
    _toolbarController.forward(from: 0.0);
  }

  /// Updates the overlay after the selection has changed.
  ///
  /// If this method is called while the [SchedulerBinding.schedulerPhase] is
  /// [SchedulerPhase.persistentCallbacks], i.e. during the build, layout, or
  /// paint phases (see [WidgetsBinding.drawFrame]), then the update is delayed
  /// until the post-frame callbacks phase. Otherwise the update is done
  /// synchronously. This means that it is safe to call during builds, but also
  /// that if you do call this during a build, the UI will not update until the
  /// next frame (i.e. many milliseconds later).
  void update(TextEditingValue newValue) {
    if (_value == newValue) return;
    _value = newValue;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(_markNeedsBuild);
    } else {
      _markNeedsBuild();
    }
  }

  /// Causes the overlay to update its rendering.
  ///
  /// This is intended to be called when the [renderObject] may have changed its
  /// text metrics (e.g. because the text was scrolled).
  void updateForScroll() {
    _markNeedsBuild();
  }

  void _markNeedsBuild([Duration duration]) {
    if (_handles != null) {
      _handles[0].markNeedsBuild();
      _handles[1].markNeedsBuild();
    }
    _toolbar?.markNeedsBuild();
  }

  /// Whether the handles are currently visible.
  bool get handlesAreVisible => _handles != null && handlesVisible;

  /// Whether the toolbar is currently visible.
  bool get toolbarIsVisible => _toolbar != null;

  /// Hides the entire overlay including the toolbar and the handles.
  void hide() {
    if (_handles != null) {
      _handles[0].remove();
      _handles[1].remove();
      _handles = null;
    }
    if (_toolbar != null) {
      hideToolbar();
    }
  }

  /// Hides the toolbar part of the overlay.
  ///
  /// To hide the whole overlay, see [hide].
  void hideToolbar() {
    assert(_toolbar != null);
    _toolbarController.stop();
    _toolbar.remove();
    _toolbar = null;
  }

  /// Final cleanup.
  void dispose() {
    hide();
    _toolbarController.dispose();
  }

  Widget _buildHandle(
      BuildContext context, _TextSelectionHandlePosition position) {
    if ((_selection.isCollapsed &&
            position == _TextSelectionHandlePosition.end) ||
        selectionControls == null) {
      return Container();
    } // hide the second handle when collapsed
    return Visibility(
        visible: handlesVisible,
        child: _TextSelectionHandleOverlay(
          onSelectionHandleChanged: (TextSelection newSelection) {
            _handleSelectionHandleChanged(newSelection, position);
          },
          onSelectionHandleTapped: onSelectionHandleTapped,
          startHandleLayerLink: startHandleLayerLink,
          endHandleLayerLink: endHandleLayerLink,
          renderObject: renderObject,
          selection: _selection,
          selectionControls: selectionControls,
          position: position,
          dragStartBehavior: dragStartBehavior,
        ));
  }

  Widget _buildToolbar(BuildContext context) {
    if (selectionControls == null) return Container();

    // Find the horizontal midpoint, just above the selected text.
    final List<TextSelectionPoint> endpoints =
        renderObject.getEndpointsForSelection(_selection);

    final Rect editingRegion = Rect.fromPoints(
      renderObject.localToGlobal(Offset.zero),
      renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero)),
    );

    final bool isMultiline =
        endpoints.last.point.dy - endpoints.first.point.dy >
            renderObject.preferredLineHeight / 2;

    // If the selected text spans more than 1 line, horizontally center the toolbar.
    // Derived from both iOS and Android.
    final double midX = isMultiline
        ? editingRegion.width / 2
        : (endpoints.first.point.dx + endpoints.last.point.dx) / 2;

    final Offset midpoint = Offset(
      midX,
      // The y-coordinate won't be made use of most likely.
      endpoints[0].point.dy - renderObject.preferredLineHeight,
    );

    return FadeTransition(
      opacity: _toolbarOpacity,
      child: CompositedTransformFollower(
        link: toolbarLayerLink,
        showWhenUnlinked: false,
        offset: -editingRegion.topLeft,
        child: selectionControls.buildToolbar(
          context,
          editingRegion,
          renderObject.preferredLineHeight,
          midpoint,
          endpoints,
          toolbarBuilder,
          selectionDelegate,
        ),
      ),
    );
  }

  void _handleSelectionHandleChanged(
      TextSelection newSelection, _TextSelectionHandlePosition position) {
    TextPosition textPosition;
    switch (position) {
      case _TextSelectionHandlePosition.start:
        textPosition = newSelection.base;
        break;
      case _TextSelectionHandlePosition.end:
        textPosition = newSelection.extent;
        break;
    }
    selectionDelegate.textEditingValue =
        _value.copyWith(selection: newSelection, composing: TextRange.empty);
    selectionDelegate.bringIntoView(textPosition);
  }
}

/// This widget represents a single draggable text selection handle.
class _TextSelectionHandleOverlay extends StatefulWidget {
  const _TextSelectionHandleOverlay({
    Key key,
    @required this.selection,
    @required this.position,
    @required this.startHandleLayerLink,
    @required this.endHandleLayerLink,
    @required this.renderObject,
    @required this.onSelectionHandleChanged,
    @required this.onSelectionHandleTapped,
    @required this.selectionControls,
    this.dragStartBehavior = DragStartBehavior.start,
  }) : super(key: key);

  final TextSelection selection;
  final _TextSelectionHandlePosition position;
  final LayerLink startHandleLayerLink;
  final LayerLink endHandleLayerLink;
  final RenderEditableWithToolbar renderObject;
  final ValueChanged<TextSelection> onSelectionHandleChanged;
  final VoidCallback onSelectionHandleTapped;
  final TextSelectionWithToolbarControls selectionControls;
  final DragStartBehavior dragStartBehavior;

  @override
  _TextSelectionHandleOverlayState createState() =>
      _TextSelectionHandleOverlayState();

  ValueListenable<bool> get _visibility {
    switch (position) {
      case _TextSelectionHandlePosition.start:
        return renderObject.selectionStartInViewport;
      case _TextSelectionHandlePosition.end:
        return renderObject.selectionEndInViewport;
    }
    return null;
  }
}

class _TextSelectionHandleOverlayState
    extends State<_TextSelectionHandleOverlay>
    with SingleTickerProviderStateMixin {
  Offset _dragPosition;

  AnimationController _controller;
  Animation<double> get _opacity => _controller.view;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
        duration: TextSelectionWithToolbarOverlay.fadeDuration, vsync: this);

    _handleVisibilityChanged();
    widget._visibility.addListener(_handleVisibilityChanged);
  }

  void _handleVisibilityChanged() {
    if (widget._visibility.value) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(_TextSelectionHandleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget._visibility.removeListener(_handleVisibilityChanged);
    _handleVisibilityChanged();
    widget._visibility.addListener(_handleVisibilityChanged);
  }

  @override
  void dispose() {
    widget._visibility.removeListener(_handleVisibilityChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    final Size handleSize = widget.selectionControls.getHandleSize(
      widget.renderObject.preferredLineHeight,
    );
    _dragPosition = details.globalPosition + Offset(0.0, -handleSize.height);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragPosition += details.delta;
    final TextPosition position =
        widget.renderObject.getPositionForPoint(_dragPosition);

    if (widget.selection.isCollapsed) {
      widget.onSelectionHandleChanged(TextSelection.fromPosition(position));
      return;
    }

    TextSelection newSelection;
    switch (widget.position) {
      case _TextSelectionHandlePosition.start:
        newSelection = TextSelection(
          baseOffset: position.offset,
          extentOffset: widget.selection.extentOffset,
        );
        break;
      case _TextSelectionHandlePosition.end:
        newSelection = TextSelection(
          baseOffset: widget.selection.baseOffset,
          extentOffset: position.offset,
        );
        break;
    }

    if (newSelection.baseOffset >= newSelection.extentOffset) {
      return;
    } // don't allow order swapping.

    widget.onSelectionHandleChanged(newSelection);
  }

  void _handleTap() {
    if (widget.onSelectionHandleTapped != null) {
      widget.onSelectionHandleTapped();
    }
  }

  @override
  Widget build(BuildContext context) {
    LayerLink layerLink;
    TextSelectionHandleType type;

    switch (widget.position) {
      case _TextSelectionHandlePosition.start:
        layerLink = widget.startHandleLayerLink;
        type = _chooseType(
          widget.renderObject.textDirection,
          TextSelectionHandleType.left,
          TextSelectionHandleType.right,
        );
        break;
      case _TextSelectionHandlePosition.end:
        // For collapsed selections, we shouldn't be building the [end] handle.
        assert(!widget.selection.isCollapsed);
        layerLink = widget.endHandleLayerLink;
        type = _chooseType(
          widget.renderObject.textDirection,
          TextSelectionHandleType.right,
          TextSelectionHandleType.left,
        );
        break;
    }

    final Offset handleAnchor = widget.selectionControls.getHandleAnchor(
      type,
      widget.renderObject.preferredLineHeight,
    );
    final Size handleSize = widget.selectionControls.getHandleSize(
      widget.renderObject.preferredLineHeight,
    );

    final Rect handleRect = Rect.fromLTWH(
      -handleAnchor.dx,
      -handleAnchor.dy,
      handleSize.width,
      handleSize.height,
    );

    // Make sure the GestureDetector is big enough to be easily interactive.
    final Rect interactiveRect = handleRect.expandToInclude(
      Rect.fromCircle(
          center: handleRect.center, radius: kMinInteractiveDimension / 2),
    );
    final RelativeRect padding = RelativeRect.fromLTRB(
      math.max((interactiveRect.width - handleRect.width) / 2, 0),
      math.max((interactiveRect.height - handleRect.height) / 2, 0),
      math.max((interactiveRect.width - handleRect.width) / 2, 0),
      math.max((interactiveRect.height - handleRect.height) / 2, 0),
    );

    return CompositedTransformFollower(
      link: layerLink,
      offset: interactiveRect.topLeft,
      showWhenUnlinked: false,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          alignment: Alignment.topLeft,
          width: interactiveRect.width,
          height: interactiveRect.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            dragStartBehavior: widget.dragStartBehavior,
            onPanStart: _handleDragStart,
            onPanUpdate: _handleDragUpdate,
            onTap: _handleTap,
            child: Padding(
              padding: EdgeInsets.only(
                left: padding.left,
                top: padding.top,
                right: padding.right,
                bottom: padding.bottom,
              ),
              child: widget.selectionControls.buildHandle(
                context,
                type,
                widget.renderObject.preferredLineHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextSelectionHandleType _chooseType(
    TextDirection textDirection,
    TextSelectionHandleType ltrType,
    TextSelectionHandleType rtlType,
  ) {
    if (widget.selection.isCollapsed) return TextSelectionHandleType.collapsed;

    assert(textDirection != null);
    switch (textDirection) {
      case TextDirection.ltr:
        return ltrType;
      case TextDirection.rtl:
        return rtlType;
    }
    return null;
  }
}

//=============================

const double _kHandleSize = 22.0;

// Minimal padding from all edges of the selection toolbar to all edges of the
// viewport.
const double _kToolbarScreenPadding = 8.0;
const double _kToolbarHeight = 44.0;
// Padding when positioning toolbar below selection.
const double _kToolbarContentDistanceBelow = _kHandleSize - 2.0;
const double _kToolbarContentDistance = 8.0;

/// Manages a copy/paste text selection toolbar.
class _TextSelectionToolbar extends StatefulWidget {
  const _TextSelectionToolbar({
    Key key,
    this.delegate,
    @required this.toolbarBuilder,
    this.isAbove,
  }) : super(key: key);

  final ToolbarTextSelectionDelegate delegate;
  final ToolbarBuilder toolbarBuilder;

  // When true, the toolbar fits above its anchor and will be positioned there.
  final bool isAbove;

  @override
  _TextSelectionToolbarState createState() => _TextSelectionToolbarState();
}

class _TextSelectionToolbarState extends State<_TextSelectionToolbar>
    with TickerProviderStateMixin {
  // Whether or not the overflow menu is open. When it is closed, the menu
  // items that don't overflow are shown. When it is open, only the overflowing
  // menu items are shown.
  bool _overflowOpen = false;

  // The key for _TextSelectionToolbarContainer.
  UniqueKey _containerKey = UniqueKey();

  // Close the menu and reset layout calculations, as in when the menu has
  // changed and saved values are no longer relevant. This should be called in
  // setState or another context where a rebuild is happening.
  void _reset() {
    // Change _TextSelectionToolbarContainer's key when the menu changes in
    // order to cause it to rebuild. This lets it recalculate its
    // saved width for the new set of children, and it prevents AnimatedSize
    // from animating the size change.
    _containerKey = UniqueKey();
    // If the menu items change, make sure the overflow menu is closed. This
    // prevents an empty overflow menu.
    _overflowOpen = false;
  }

  @override
  void didUpdateWidget(_TextSelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the children are changing, the current page should be reset.
    if ((widget.delegate == null) != (oldWidget.delegate == null)) {
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations localizations =
        MaterialLocalizations.of(context);
    final items = widget?.toolbarBuilder?.call(widget.delegate) ?? <Widget>[];

    // If there is no option available, build an empty widget.
    if (items.isEmpty) {
      return const SizedBox(width: 0.0, height: 0.0);
    }

    return TextSelectionToolbarContainer(
      key: _containerKey,
      overflowOpen: _overflowOpen,
      child: AnimatedSize(
        vsync: this,
        // This duration was eyeballed on a Pixel 2 emulator running Android
        // API 28.
        duration: const Duration(milliseconds: 140),
        child: Material(
          // This value was eyeballed to match the native text selection menu on
          // a Pixel 2 running Android 10.
          borderRadius: const BorderRadius.all(Radius.circular(7.0)),
          clipBehavior: Clip.antiAlias,
          elevation: 1.0,
          type: MaterialType.card,
          child: TextSelectionToolbarItems(
            isAbove: widget.isAbove,
            overflowOpen: _overflowOpen,
            children: <Widget>[
              // The navButton that shows and hides the overflow menu is the
              // first child.
              Material(
                type: MaterialType.card,
                child: IconButton(
                  // https://github.com/flutter/flutter/issues/51209
                  icon:
                      Icon(_overflowOpen ? Icons.arrow_back : Icons.more_vert),
                  onPressed: () {
                    setState(() {
                      _overflowOpen = !_overflowOpen;
                    });
                  },
                  tooltip: _overflowOpen
                      ? localizations.backButtonTooltip
                      : localizations.moreButtonTooltip,
                ),
              ),
              ...items
            ],
          ),
        ),
      ),
    );
  }
}

/// Centers the toolbar around the given anchor, ensuring that it remains on
/// screen.
class _TextSelectionToolbarLayout extends SingleChildLayoutDelegate {
  _TextSelectionToolbarLayout(this.anchor, this.upperBounds, this.fitsAbove);

  /// Anchor position of the toolbar in global coordinates.
  final Offset anchor;

  /// The upper-most valid y value for the anchor.
  final double upperBounds;

  /// Whether the closed toolbar fits above the anchor position.
  ///
  /// If the closed toolbar doesn't fit, then the menu is rendered below the
  /// anchor position. It should never happen that the toolbar extends below the
  /// padded bottom of the screen.
  ///
  /// If the closed toolbar does fit but it doesn't fit when the overflow menu
  /// is open, then the toolbar is still rendered above the anchor position. It
  /// then grows downward, overlapping the selection.
  final bool fitsAbove;

  // Return the value that centers width as closely as possible to position
  // while fitting inside of min and max.
  static double _centerOn(
      double position, double width, double min, double max) {
    // If it overflows on the left, put it as far left as possible.
    if (position - width / 2.0 < min) {
      return min;
    }

    // If it overflows on the right, put it as far right as possible.
    if (position + width / 2.0 > max) {
      return max - width;
    }

    // Otherwise it fits while perfectly centered.
    return position - width / 2.0;
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset(
      _centerOn(
        anchor.dx,
        childSize.width,
        _kToolbarScreenPadding,
        size.width - _kToolbarScreenPadding,
      ),
      fitsAbove
          ? math.max(upperBounds, anchor.dy - childSize.height)
          : anchor.dy,
    );
  }

  @override
  bool shouldRelayout(_TextSelectionToolbarLayout oldDelegate) {
    return anchor != oldDelegate.anchor;
  }
}

/// Draws a single text selection handle which points up and to the left.
class _TextSelectionHandlePainter extends CustomPainter {
  _TextSelectionHandlePainter({this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final double radius = size.width / 2.0;
    final Rect circle =
        Rect.fromCircle(center: Offset(radius, radius), radius: radius);
    final Rect point = Rect.fromLTWH(0.0, 0.0, radius, radius);
    final Path path = Path()
      ..addOval(circle)
      ..addRect(point);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TextSelectionHandlePainter oldPainter) {
    return color != oldPainter.color;
  }
}

class _MaterialTextSelectionControls extends TextSelectionWithToolbarControls {
  /// Returns the size of the Material handle.
  @override
  Size getHandleSize(double textLineHeight) =>
      const Size(_kHandleSize, _kHandleSize);

  /// Builder for material-style copy/paste text selection toolbar.
  @override
  Widget buildToolbar(
      BuildContext context,
      Rect globalEditableRegion,
      double textLineHeight,
      Offset selectionMidpoint,
      List<TextSelectionPoint> endpoints,
      ToolbarBuilder toolbarBuilder,
      ToolbarTextSelectionDelegate delegate) {
    assert(debugCheckHasMediaQuery(context));
    assert(debugCheckHasMaterialLocalizations(context));

    // The toolbar should appear below the TextField when there is not enough
    // space above the TextField to show it.
    final TextSelectionPoint startTextSelectionPoint = endpoints[0];
    final TextSelectionPoint endTextSelectionPoint =
        endpoints.length > 1 ? endpoints[1] : endpoints[0];
    const double closedToolbarHeightNeeded =
        _kToolbarScreenPadding + _kToolbarHeight + _kToolbarContentDistance;
    final double paddingTop = MediaQuery.of(context).padding.top;
    final double availableHeight = globalEditableRegion.top +
        startTextSelectionPoint.point.dy -
        textLineHeight -
        paddingTop;
    final bool fitsAbove = closedToolbarHeightNeeded <= availableHeight;
    final Offset anchor = Offset(
      globalEditableRegion.left + selectionMidpoint.dx,
      fitsAbove
          ? globalEditableRegion.top +
              startTextSelectionPoint.point.dy -
              textLineHeight -
              _kToolbarContentDistance
          : globalEditableRegion.top +
              endTextSelectionPoint.point.dy +
              _kToolbarContentDistanceBelow,
    );

    return Stack(
      children: <Widget>[
        CustomSingleChildLayout(
          delegate: _TextSelectionToolbarLayout(
            anchor,
            _kToolbarScreenPadding + paddingTop,
            fitsAbove,
          ),
          child: _TextSelectionToolbar(
            delegate: delegate,
            toolbarBuilder: toolbarBuilder,
            isAbove: fitsAbove,
          ),
        ),
      ],
    );
  }

  /// Builder for material-style text selection handles.
  @override
  Widget buildHandle(
      BuildContext context, TextSelectionHandleType type, double textHeight) {
    final ThemeData theme = Theme.of(context);
    final Color handleColor = theme.useTextSelectionTheme
        ? TextSelectionTheme.of(context).selectionHandleColor ??
            theme.colorScheme.primary
        : theme.textSelectionHandleColor;
    final Widget handle = SizedBox(
      width: _kHandleSize,
      height: _kHandleSize,
      child: CustomPaint(
        painter: _TextSelectionHandlePainter(
          color: handleColor,
        ),
      ),
    );

    // [handle] is a circle, with a rectangle in the top left quadrant of that
    // circle (an onion pointing to 10:30). We rotate [handle] to point
    // straight up or up-right depending on the handle type.
    switch (type) {
      case TextSelectionHandleType.left: // points up-right
        return Transform.rotate(
          angle: math.pi / 2.0,
          child: handle,
        );
      case TextSelectionHandleType.right: // points up-left
        return handle;
      case TextSelectionHandleType.collapsed: // points up
        return Transform.rotate(
          angle: math.pi / 4.0,
          child: handle,
        );
    }
    assert(type != null);
    return null;
  }

  /// Gets anchor for material-style text selection handles.
  ///
  /// See [TextSelectionWithToolbarControls.getHandleAnchor].
  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    switch (type) {
      case TextSelectionHandleType.left:
        return const Offset(_kHandleSize, 0);
      case TextSelectionHandleType.right:
        return Offset.zero;
      default:
        return const Offset(_kHandleSize / 2, -4);
    }
  }
}

/// Text selection controls that follow the Material Design specification.
final TextSelectionWithToolbarControls
    materialTextSelectionWithToolbarControls = _MaterialTextSelectionControls();
