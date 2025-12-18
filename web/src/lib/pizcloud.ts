import { PUBLIC_MAIN_DOMAIN } from '$env/static/public';

export const getBaseUrl = () => {
  return '/api';
};

export function getAccountUrl() {
  return `https://account.${PUBLIC_MAIN_DOMAIN}`;
}

export async function logOut() {
  const url = getAccountUrl() + '/api/users/logout?service=photos_dev';
  const res = await fetch(url);
  const jsonRes = await res.json();
  if (jsonRes.redirectUri) {
    globalThis.location.href = jsonRes.redirectUri;
  }
  return jsonRes;
}
