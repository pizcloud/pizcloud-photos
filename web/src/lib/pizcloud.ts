import { PUBLIC_DEFAULT_SERVICE_NAME, PUBLIC_MAIN_DOMAIN } from '$env/static/public';
import { getBaseUrl as getSdkBaseUrl } from '@immich/sdk';

export const getBaseUrl = () => {
  return getSdkBaseUrl();
};

export function getAccountUrl() {
  return `https://account.${PUBLIC_MAIN_DOMAIN}`;
}

export async function logOut() {
  const url = getAccountUrl() + `/api/users/logout?service=${PUBLIC_DEFAULT_SERVICE_NAME}`;
  const res = await fetch(url, { credentials: 'include' });
  const jsonRes = await res.json();
  if (jsonRes.redirectUri) {
    globalThis.location.href = jsonRes.redirectUri;
  }
  return jsonRes;
}
