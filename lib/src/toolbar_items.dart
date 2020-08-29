import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const double _kToolbarHeight = 44.0;

// Renders the menu items in the correct positions in the menu and its overflow
// submenu based on calculating which item would first overflow.
class TextSelectionToolbarItems extends MultiChildRenderObjectWidget {
  TextSelectionToolbarItems({
    Key key,
    @required this.isAbove,
    @required this.overflowOpen,
    @required List<Widget> children,
  })  : assert(children != null),
        assert(isAbove != null),
        assert(overflowOpen != null),
        super(key: key, children: children);

  final bool isAbove;
  final bool overflowOpen;

  @override
  _TextSelectionToolbarItemsRenderBox createRenderObject(BuildContext context) {
    return _TextSelectionToolbarItemsRenderBox(
      isAbove: isAbove,
      overflowOpen: overflowOpen,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _TextSelectionToolbarItemsRenderBox renderObject) {
    renderObject
      ..isAbove = isAbove
      ..overflowOpen = overflowOpen;
  }

  @override
  _TextSelectionToolbarItemsElement createElement() =>
      _TextSelectionToolbarItemsElement(this);
}

class _TextSelectionToolbarItemsElement extends MultiChildRenderObjectElement {
  _TextSelectionToolbarItemsElement(
    MultiChildRenderObjectWidget widget,
  ) : super(widget);

  static bool _shouldPaint(Element child) {
    return (child.renderObject.parentData as ToolbarItemsParentData)
        .shouldPaint;
  }

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    children.where(_shouldPaint).forEach(visitor);
  }
}

class _TextSelectionToolbarItemsRenderBox extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, ToolbarItemsParentData> {
  _TextSelectionToolbarItemsRenderBox({
    @required bool isAbove,
    @required bool overflowOpen,
  })  : assert(overflowOpen != null),
        assert(isAbove != null),
        _isAbove = isAbove,
        _overflowOpen = overflowOpen,
        super();

  // The index of the last item that doesn't overflow.
  int _lastIndexThatFits = -1;

  bool _isAbove;
  bool get isAbove => _isAbove;
  set isAbove(bool value) {
    if (value == isAbove) {
      return;
    }
    _isAbove = value;
    markNeedsLayout();
  }

  bool _overflowOpen;
  bool get overflowOpen => _overflowOpen;
  set overflowOpen(bool value) {
    if (value == overflowOpen) {
      return;
    }
    _overflowOpen = value;
    markNeedsLayout();
  }

  // Layout the necessary children, and figure out where the children first
  // overflow, if at all.
  void _layoutChildren() {
    // When overflow is not open, the toolbar is always a specific height.
    final BoxConstraints sizedConstraints = _overflowOpen
        ? constraints
        : BoxConstraints.loose(Size(
            constraints.maxWidth,
            _kToolbarHeight,
          ));

    int i = -1;
    double width = 0.0;
    visitChildren((RenderObject renderObjectChild) {
      i++;

      // No need to layout children inside the overflow menu when it's closed.
      // The opposite is not true. It is necessary to layout the children that
      // don't overflow when the overflow menu is open in order to calculate
      // _lastIndexThatFits.
      if (_lastIndexThatFits != -1 && !overflowOpen) {
        return;
      }

      final RenderBox child = renderObjectChild as RenderBox;
      child.layout(sizedConstraints.loosen(), parentUsesSize: true);
      width += child.size.width;

      if (width > sizedConstraints.maxWidth && _lastIndexThatFits == -1) {
        _lastIndexThatFits = i - 1;
      }
    });

    // If the last child overflows, but only because of the width of the
    // overflow button, then just show it and hide the overflow button.
    final RenderBox navButton = firstChild;
    if (_lastIndexThatFits != -1 &&
        _lastIndexThatFits == childCount - 2 &&
        width - navButton.size.width <= sizedConstraints.maxWidth) {
      _lastIndexThatFits = -1;
    }
  }

  // Returns true when the child should be painted, false otherwise.
  bool _shouldPaintChild(RenderObject renderObjectChild, int index) {
    // Paint the navButton when there is overflow.
    if (renderObjectChild == firstChild) {
      return _lastIndexThatFits != -1;
    }

    // If there is no overflow, all children besides the navButton are painted.
    if (_lastIndexThatFits == -1) {
      return true;
    }

    // When there is overflow, paint if the child is in the part of the menu
    // that is currently open. Overflowing children are painted when the
    // overflow menu is open, and the children that fit are painted when the
    // overflow menu is closed.
    return (index > _lastIndexThatFits) == overflowOpen;
  }

  // Decide which children will be pained and set their shouldPaint, and set the
  // offset that painted children will be placed at.
  void _placeChildren() {
    int i = -1;
    Size nextSize = const Size(0.0, 0.0);
    double fitWidth = 0.0;
    final RenderBox navButton = firstChild;
    double overflowHeight =
        overflowOpen && !isAbove ? navButton.size.height : 0.0;
    visitChildren((RenderObject renderObjectChild) {
      i++;

      final RenderBox child = renderObjectChild as RenderBox;
      final ToolbarItemsParentData childParentData =
          child.parentData as ToolbarItemsParentData;

      // Handle placing the navigation button after iterating all children.
      if (renderObjectChild == navButton) {
        return;
      }

      // There is no need to place children that won't be painted.
      if (!_shouldPaintChild(renderObjectChild, i)) {
        childParentData.shouldPaint = false;
        return;
      }
      childParentData.shouldPaint = true;

      if (!overflowOpen) {
        childParentData.offset = Offset(fitWidth, 0.0);
        fitWidth += child.size.width;
        nextSize = Size(
          fitWidth,
          math.max(child.size.height, nextSize.height),
        );
      } else {
        childParentData.offset = Offset(0.0, overflowHeight);
        overflowHeight += child.size.height;
        nextSize = Size(
          math.max(child.size.width, nextSize.width),
          overflowHeight,
        );
      }
    });

    // Place the navigation button if needed.
    final ToolbarItemsParentData navButtonParentData =
        navButton.parentData as ToolbarItemsParentData;
    if (_shouldPaintChild(firstChild, 0)) {
      navButtonParentData.shouldPaint = true;
      if (overflowOpen) {
        navButtonParentData.offset =
            isAbove ? Offset(0.0, overflowHeight) : Offset.zero;
        nextSize = Size(
          nextSize.width,
          isAbove ? nextSize.height + navButton.size.height : nextSize.height,
        );
      } else {
        navButtonParentData.offset = Offset(fitWidth, 0.0);
        nextSize = Size(nextSize.width + navButton.size.width, nextSize.height);
      }
    } else {
      navButtonParentData.shouldPaint = false;
    }

    size = nextSize;
  }

  @override
  void performLayout() {
    _lastIndexThatFits = -1;
    if (firstChild == null) {
      performResize();
      return;
    }

    _layoutChildren();
    _placeChildren();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    visitChildren((RenderObject renderObjectChild) {
      final RenderBox child = renderObjectChild as RenderBox;
      final ToolbarItemsParentData childParentData =
          child.parentData as ToolbarItemsParentData;
      if (!childParentData.shouldPaint) {
        return;
      }

      context.paintChild(child, childParentData.offset + offset);
    });
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ToolbarItemsParentData) {
      child.parentData = ToolbarItemsParentData();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {Offset position}) {
    // The x, y parameters have the top left of the node's box as the origin.
    RenderBox child = lastChild;
    while (child != null) {
      final ToolbarItemsParentData childParentData =
          child.parentData as ToolbarItemsParentData;

      // Don't hit test children aren't shown.
      if (!childParentData.shouldPaint) {
        child = childParentData.previousSibling;
        continue;
      }

      final bool isHit = result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          assert(transformed == position - childParentData.offset);
          return child.hitTest(result, position: transformed);
        },
      );
      if (isHit) return true;
      child = childParentData.previousSibling;
    }
    return false;
  }

  // Visit only the children that should be painted.
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitChildren((RenderObject renderObjectChild) {
      final RenderBox child = renderObjectChild as RenderBox;
      final ToolbarItemsParentData childParentData =
          child.parentData as ToolbarItemsParentData;
      if (childParentData.shouldPaint) {
        visitor(renderObjectChild);
      }
    });
  }
}
