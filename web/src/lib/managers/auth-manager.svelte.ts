import { goto } from '$app/navigation';
import { page } from '$app/state';
import { AppRoute } from '$lib/constants';
import { eventManager } from '$lib/managers/event-manager.svelte';
import { logOut } from '$lib/pizcloud';
import {
  clearAuthLoginResultMarker,
  reportAuthLogoutFailure,
  reportAuthLogoutSuccess,
} from '$lib/services/pizcloud/auth-event.service'; // pizcloud
import { isSharedLinkRoute } from '$lib/utils/navigation';
import { logout } from '@immich/sdk';

class AuthManager {
  isSharedLink = $derived(isSharedLinkRoute(page.route?.id));
  params = $derived(this.isSharedLink ? { key: page.params.key, slug: page.params.slug } : {});

  async logout() {
    let redirectUri;
    let sdkLogoutSucceeded = false; // pizcloud

    try {
      const response = await logout();
      sdkLogoutSucceeded = true; // pizcloud
      const res = await logOut(); // pizcloud
      if (response.redirectUri) {
        redirectUri = response.redirectUri;
      }
    } catch (error) {
      console.log('Error logging out:', error);
      if (!sdkLogoutSucceeded) {
        reportAuthLogoutFailure({ reasonCode: 'sdk_logout_failed', source: 'web.auth_manager.logout' });
      } // pizcloud
    }

    if (sdkLogoutSucceeded) {
      clearAuthLoginResultMarker();
      reportAuthLogoutSuccess({ source: 'web.auth_manager.logout' });
    } // pizcloud

    redirectUri = redirectUri ?? AppRoute.AUTH_LOGIN;

    try {
      if (redirectUri.startsWith('/')) {
        await goto(redirectUri);
      } else {
        globalThis.location.href = redirectUri;
      }
    } finally {
      eventManager.emit('AuthLogout');
    }
  }
}

export const authManager = new AuthManager();
