import 'package:flutter/material.dart';

/// A unified desktop-friendly and mobile-adaptive scrollbar wrapper for Anx Reader.
///
/// Ensures:
/// 1. Anti-duplication: Prevents nested/duplicate native scrollbars by suppressing
///    inner scrollbars on the child via [ScrollConfiguration].
/// 2. Detached controller safety: Guards [thumbVisibility] when the controller has
///    not yet been attached to a [ScrollPosition] (e.g. during asynchronous loading).
/// 3. Standard interaction: Supports hover expansion and dragging.
class AppScrollbar extends StatefulWidget {
  const AppScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.interactive = true,
    this.thickness,
    this.radius,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final bool interactive;
  final double? thickness;
  final Radius? radius;

  @override
  State<AppScrollbar> createState() => _AppScrollbarState();
}

class _AppScrollbarState extends State<AppScrollbar> {
  ScrollController? _currentController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentController =
        widget.controller ?? PrimaryScrollController.maybeOf(context);
  }

  @override
  void didUpdateWidget(AppScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _currentController =
          widget.controller ?? PrimaryScrollController.maybeOf(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveController = _currentController;
    final hasClients = effectiveController?.hasClients ?? false;
    final effectiveThumbVisibility = hasClients ? widget.thumbVisibility : false;
    final effectiveInteractive =
        (widget.controller != null || hasClients) && widget.interactive;

    assert(() {
      if (widget.controller == null && !hasClients) {
        debugPrint(
          'AppScrollbar: controller is null and PrimaryScrollController has no clients. '
          'Ensure you pass an explicit ScrollController on desktop platforms.',
        );
      }
      return true;
    }());

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (!hasClients && (effectiveController?.hasClients ?? false)) {
          setState(() {});
        }
        return false;
      },
      child: Scrollbar(
        controller: widget.controller,
        thumbVisibility: effectiveThumbVisibility,
        interactive: effectiveInteractive,
        thickness: widget.thickness,
        radius: widget.radius,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: widget.child,
        ),
      ),
    );
  }
}
