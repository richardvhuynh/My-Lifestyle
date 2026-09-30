import { defineFunction, secret } from '@aws-amplify/backend';

/// A scheduled Lambda that runs once a day (server-side, no app needed) and
/// adds ~100 fresh Spoonacular recipes to the shared catalog. Kept within
/// Spoonacular's free tier: one ~100-point request per day.
export const dailyRecipeSeeder = defineFunction({
  name: 'daily-recipe-seeder',
  schedule: 'every day',
  timeoutSeconds: 120,
  memoryMB: 512,
  environment: {
    SPOONACULAR_API_KEY: secret('SPOONACULAR_API_KEY'),
  },
});
