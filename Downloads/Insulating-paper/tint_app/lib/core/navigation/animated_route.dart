// Simple animated page transitions
// Provides clean slide animations without complexity

import 'package:flutter/material.dart';

/// SlideUp transition - simple, elegant page entry
class SlideUpRoute extends MaterialPageRoute {
  SlideUpRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) : super(
    builder: builder,
    settings: settings,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      )),
      child: child,
    );
  }
}

/// FadeIn transition - subtle fade animation
class FadeInRoute extends MaterialPageRoute {
  FadeInRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) : super(
    builder: builder,
    settings: settings,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }
}

/// Combination of fade + slide for product detail
class DetailRoute extends MaterialPageRoute {
  DetailRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) : super(
    builder: builder,
    settings: settings,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    ));

    return SlideTransition(
      position: slideAnimation,
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}
