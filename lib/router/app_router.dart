import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_shell/app_scaffold.dart';
import '../app_shell/authenticated_scope.dart';
import '../features/add/presentation/add_overlay.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/chat/presentation/chat_overlay.dart';
import '../features/ideas/presentation/ideas_page.dart';
import '../features/notes/presentation/notes_page.dart';
import '../features/recap/presentation/recap_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/todo/presentation/todo_page.dart';
import '../shared/auth/domain/auth_repo.dart';
import 'go_router_refresh_stream.dart';
import 'routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Built once in `app.dart` with the root-tier [AuthRepo].
GoRouter buildRouter(AuthRepo authRepo) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.calendar,
    refreshListenable: GoRouterRefreshStream(authRepo.authState),
    redirect: (context, state) {
      final loggedIn = authRepo.currentUserId != null;
      final atLogin = state.matchedLocation == Routes.login;
      if (!loggedIn) return atLogin ? null : Routes.login;
      if (atLogin) return Routes.calendar;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (_, __) => const LoginPage(),
      ),

      // Everything authenticated lives under this ShellRoute so the user-scoped
      // provider tier wraps the tab shell AND the pushed-over routes
      // (/settings, /add, /chat).
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AuthenticatedScope(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                AppScaffold(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                    path: Routes.calendar,
                    builder: (_, __) => const CalendarPage()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: Routes.todo, builder: (_, __) => const TodoPage()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: Routes.ideas, builder: (_, __) => const IdeasPage()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: Routes.notes, builder: (_, __) => const NotesPage()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: Routes.recap, builder: (_, __) => const RecapPage()),
              ]),
            ],
          ),
          GoRoute(
            path: Routes.settings,
            builder: (_, __) => const SettingsPage(),
          ),
          GoRoute(
            path: Routes.add,
            builder: (_, __) => const AddOverlay(),
          ),
          GoRoute(
            path: Routes.chat,
            builder: (_, __) => const ChatOverlay(),
          ),
        ],
      ),
    ],
  );
}
