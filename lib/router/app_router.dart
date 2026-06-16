import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_shell/app_scaffold.dart';
import '../app_shell/authenticated_scope.dart';
import '../app_shell/swipe_shell.dart';
import '../features/add/presentation/add_overlay.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/chat/presentation/chat_overlay.dart';
import '../features/ideas/presentation/ideas_page.dart';
import '../features/notes/presentation/note_detail_page.dart';
import '../features/notes/presentation/notes_page.dart';
import '../features/recap/presentation/recap_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/todo/presentation/todo_page.dart';
import '../shared/auth/domain/auth_repo.dart';
import '../shared/storage/firebase_storage_repo.dart';
import '../shared/storage/storage_repo.dart';
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
          StatefulShellRoute(
            builder: (context, state, navigationShell) =>
                AppScaffold(navigationShell: navigationShell),
            navigatorContainerBuilder: (context, navigationShell, children) =>
                SwipeShell(
                    navigationShell: navigationShell, children: children),
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
                  path: Routes.notes,
                  builder: (_, __) => const NotesPage(),
                  routes: [
                    // Category detail — stays on the branch navigator so the
                    // category-card icon flies in via Hero and the user-scoped
                    // NoteRepo (above the shell) is still in scope.
                    GoRoute(
                      path: 'category/:catId',
                      builder: (_, state) => NoteCategoryDetailPage(
                        catId: state.pathParameters['catId']!,
                      ),
                    ),
                    // Single note — pushed over the whole shell (root navigator)
                    // for a full-screen view, with the list image flying in via
                    // Hero. The Note is handed over through `extra`; a StorageRepo
                    // is provided here from the root FirebaseStorage singleton.
                    GoRoute(
                      path: ':noteId',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (_, state) {
                        final args = state.extra as NoteDetailArgs?;
                        return Provider<StorageRepo>(
                          create: (c) =>
                              FirebaseStorageRepo(c.read<FirebaseStorage>()),
                          child: NoteDetailPage(
                            noteId: state.pathParameters['noteId']!,
                            note: args?.note,
                            heroTag: args?.heroTag,
                          ),
                        );
                      },
                    ),
                  ],
                ),
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
