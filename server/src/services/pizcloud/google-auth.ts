import { GoogleAuth } from 'google-auth-library';

export async function getGoogleAccessToken(): Promise<string> {
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  if (!token || !token.token) throw new Error('Failed to obtain Google access token');
  return token.token;
}
