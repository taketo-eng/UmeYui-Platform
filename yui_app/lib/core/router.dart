import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';

GoRouter createRouter(AuthProvider authProvider) {
  return GoRouter(
    initialLocation: '/login',
    // 認証状態が変わった時にルーター再評価
    refreshListenable: authProvider,

    // リダイレクトロジック
    // 全ての画面遷移前に呼ばれる
    redirect: (context, state) {
      final status = authProvider.status;
      final isLoginPage = state.matchedLocation == '/login';

      // 認証状態確認中
      if (status == AuthStatus.unknown) return null;

      if (status == AuthStatus.unauthenticated && !isLoginPage) {
        return '/login';
      }

      if (status == AuthStatus.authenticated && isLoginPage) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => const MaterialPage(
          key: ValueKey('home'),
          child: HomeScreen(),
        ),
      ),
    ],
  );
}
