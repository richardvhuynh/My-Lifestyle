import { defineAuth, secret } from '@aws-amplify/backend';

/**
 * Auth: email/password plus Sign in with Apple and Google.
 *
 * Provider secrets live in AWS (set via `ampx sandbox secret set <NAME>`) and are
 * referenced here with `secret(...)` — they never ship in the app bundle. The app
 * only receives the public Hosted-UI config (provider ids, domain, redirect) through
 * `amplify_outputs.json`. The redirect scheme `mylifestyle://` must also be registered
 * in the app target's URL Types.
 *
 * Required secrets (create the matching OAuth apps first):
 *   Apple  (developer.apple.com → Services ID + a Sign in with Apple key):
 *     SIWA_CLIENT_ID   — the Services ID (e.g. com.yourteam.mylifestyle.service)
 *     SIWA_TEAM_ID     — your Apple Team ID
 *     SIWA_KEY_ID      — the key id of the .p8 key
 *     SIWA_PRIVATE_KEY — contents of the .p8 private key
 *   Google (console.cloud.google.com → OAuth 2.0 Web client):
 *     GOOGLE_CLIENT_ID
 *     GOOGLE_CLIENT_SECRET
 *
 * @see https://docs.amplify.aws/gen2/build-a-backend/auth
 */
export const auth = defineAuth({
  loginWith: {
    email: true,
    externalProviders: {
      signInWithApple: {
        clientId: secret('SIWA_CLIENT_ID'),
        teamId: secret('SIWA_TEAM_ID'),
        keyId: secret('SIWA_KEY_ID'),
        privateKey: secret('SIWA_PRIVATE_KEY'),
      },
      google: {
        clientId: secret('GOOGLE_CLIENT_ID'),
        clientSecret: secret('GOOGLE_CLIENT_SECRET'),
      },
      // Native app redirect. Must match the URL scheme registered in the app.
      callbackUrls: ['mylifestyle://'],
      logoutUrls: ['mylifestyle://'],
    },
  },
});
