import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class AuthGuard extends AutoRouteGuard {
  static const Duration _validateTokenTimeout = Duration(seconds: 7); // pizcloud

  final ApiService _apiService;
  final _log = Logger("AuthGuard");
  AuthGuard(this._apiService);
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) async {
    // pizcloud
    // resolver.next(true);

    void denyAndRedirectToLogin(String message, {bool fine = false}) {
      if (fine) {
        _log.fine(message);
      } else {
        _log.warning(message);
      }
      resolver.next(false);
      unawaited(router.replaceAll([const LoginRoute()]));
    }
    // #pizcloud

    try {
      // Look in the store for an access token
      Store.get(StoreKey.accessToken);

      // Validate the access token with the server before allowing navigation
      // final res = await _apiService.authenticationApi.validateAccessToken(); // pizcloud
      _apiService.ensureEndpointFromStore(); // pizcloud
      final res = await _apiService.authenticationApi.validateAccessToken().timeout(_validateTokenTimeout); // pizcloud
      if (res == null || res.authStatus != true) {
        // If the access token is invalid, block the route and take user back to login
        denyAndRedirectToLogin('User token is invalid. Redirecting to login', fine: true); // pizcloud
        return; // pizcloud
      }

      resolver.next(true); // pizcloud
      return; // pizcloud
    } on StoreKeyNotFoundException catch (_) {
      // If there is no access token, block the route and take us to the login page
      denyAndRedirectToLogin('No access token in the store.'); // pizcloud
      return;
    } on ApiException catch (e) {
      // On an unauthorized request, block the route and take us to the login page
      if (e.code == HttpStatus.unauthorized) {
        denyAndRedirectToLogin('Unauthorized access token.'); // pizcloud
        return;
      }

      // pizcloud
      // Preserve the existing fail-open behavior for non-auth validation errors.
      _log.warning('Error validating access token from server [API EXCEPTION]: ${e.code} ${e.message}');
      resolver.next(true);
      return;
    } on TimeoutException catch (_) {
      // Preserve the existing fail-open behavior if token validation takes too long.
      _log.warning('Timed out while validating access token after $_validateTokenTimeout.');
      resolver.next(true);
      return;
    } catch (e) {
      // Preserve the existing fail-open behavior for unexpected validation errors.
      _log.warning('Error validating access token from server: $e');
      resolver.next(true);
      return;
    }
  }

  // #pizcloud
}
