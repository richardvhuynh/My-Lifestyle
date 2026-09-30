import { defineBackend } from '@aws-amplify/backend';
import { Function } from 'aws-cdk-lib/aws-lambda';
import { auth } from './auth/resource';
import { data } from './data/resource';
import { dailyRecipeSeeder } from './functions/daily-recipe-seeder/resource';

/**
 * @see https://docs.amplify.aws/react/build-a-backend/ to add storage, functions, and more
 */
const backend = defineBackend({
  auth,
  data,
  dailyRecipeSeeder,
});

// Let the nightly seeder read/write the shared Recipe table, and tell it the
// table's name via an environment variable.
const recipeTable = backend.data.resources.tables['Recipe'];
const seeder = backend.dailyRecipeSeeder.resources.lambda as Function;
recipeTable.grantReadWriteData(seeder);
seeder.addEnvironment('RECIPE_TABLE_NAME', recipeTable.tableName);
