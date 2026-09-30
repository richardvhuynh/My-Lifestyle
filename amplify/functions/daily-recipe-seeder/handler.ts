import { DynamoDBClient, ScanCommand, BatchWriteItemCommand } from '@aws-sdk/client-dynamodb';
import { randomUUID } from 'node:crypto';

const client = new DynamoDBClient({});
const TABLE = process.env.RECIPE_TABLE_NAME!;
const API_KEY = process.env.SPOONACULAR_API_KEY!;

// Spoonacular unit string → the app's MeasurementUnit raw values.
const UNITS: Record<string, string> = {
  g: 'g', gram: 'g', gr: 'g', kg: 'kg', kilogram: 'kg',
  oz: 'oz', ounce: 'oz', lb: 'lb', pound: 'lb',
  ml: 'ml', milliliter: 'ml', millilitre: 'ml',
  l: 'L', liter: 'L', litre: 'L', cup: 'cup',
  tablespoon: 'tbsp', tbsp: 'tbsp', tbs: 'tbsp', tbl: 'tbsp',
  teaspoon: 'tsp', tsp: 'tsp', 'fl oz': 'fl oz', 'fluid ounce': 'fl oz',
};

function mapUnit(raw: string): string {
  let u = (raw || '').toLowerCase().trim();
  if (u.endsWith('s')) u = u.slice(0, -1);
  return UNITS[u] ?? 'whole';
}

function round1(x: number): number {
  return Math.round(x * 10) / 10;
}

function titleCase(s: string): string {
  return s.replace(/\b\w/g, (c) => c.toUpperCase());
}

/// Reads every existing sourceId so we don't add duplicates on repeat runs.
async function existingSourceIds(): Promise<Set<string>> {
  const ids = new Set<string>();
  let startKey: Record<string, unknown> | undefined;
  do {
    const out = await client.send(new ScanCommand({
      TableName: TABLE,
      ProjectionExpression: 'sourceId',
      ExclusiveStartKey: startKey as any,
    }));
    for (const item of out.Items ?? []) {
      if (item.sourceId?.S) ids.add(item.sourceId.S);
    }
    startKey = out.LastEvaluatedKey as any;
  } while (startKey);
  return ids;
}

export const handler = async () => {
  if (!TABLE || !API_KEY) {
    console.error('Missing RECIPE_TABLE_NAME or SPOONACULAR_API_KEY');
    return;
  }

  const existing = await existingSourceIds();

  const url = `https://api.spoonacular.com/recipes/complexSearch?apiKey=${API_KEY}`
    + `&number=100&addRecipeInformation=true&addRecipeNutrition=true`
    + `&fillIngredients=true&instructionsRequired=true&sort=random`;
  const response = await fetch(url);
  if (!response.ok) {
    console.error('Spoonacular request failed:', response.status, await response.text());
    return;
  }
  const data: any = await response.json();
  const now = new Date().toISOString();

  const items: Record<string, any>[] = [];
  const seen = new Set<string>();

  for (const r of data.results ?? []) {
    const sourceId = `spoonacular-${r.id}`;
    if (existing.has(sourceId) || seen.has(sourceId)) continue;
    seen.add(sourceId);

    const title = (r.title || '').trim();
    if (!title) continue;
    const servings = Math.max(1, r.servings || 1);
    const nutrient = (name: string): number =>
      r.nutrition?.nutrients?.find((n: any) => n.name === name)?.amount ?? 0;

    const ingredients = (r.extendedIngredients ?? [])
      .map((e: any) => {
        const nm = ((e.nameClean || e.name || '') as string).trim();
        if (!nm) return null;
        const amount = (e.amount ?? 0) > 0 ? e.amount : 1;
        return { amount, unit: mapUnit(e.unit || ''), id: randomUUID().toUpperCase(), name: titleCase(nm) };
      })
      .filter((x: unknown) => x !== null);

    const steps: any[] = [];
    for (const group of r.analyzedInstructions ?? []) {
      for (const s of group.steps ?? []) {
        const text = (s.step || '').trim();
        if (!text) continue;
        steps.push({ id: randomUUID().toUpperCase(), instruction: text, order: steps.length + 1 });
      }
    }

    const item: Record<string, any> = {
      id: { S: randomUUID() },
      __typename: { S: 'Recipe' },
      createdAt: { S: now },
      updatedAt: { S: now },
      name: { S: title },
      servings: { N: String(servings) },
      sourceId: { S: sourceId },
      calories: { N: String(Math.round(nutrient('Calories') * servings)) },
      protein: { N: String(round1(nutrient('Protein') * servings)) },
      carbs: { N: String(round1(nutrient('Carbohydrates') * servings)) },
      fat: { N: String(round1(nutrient('Fat') * servings)) },
      ingredients: { S: JSON.stringify(ingredients) },
      steps: { S: JSON.stringify(steps) },
    };
    if (r.image) item.imageUrl = { S: r.image };
    if (r.dishTypes?.[0]) item.category = { S: titleCase(r.dishTypes[0]) };
    if (r.cuisines?.[0]) item.area = { S: r.cuisines[0] };
    items.push(item);
  }

  for (let i = 0; i < items.length; i += 25) {
    const batch = items.slice(i, i + 25).map((it) => ({ PutRequest: { Item: it } }));
    await client.send(new BatchWriteItemCommand({ RequestItems: { [TABLE]: batch } }));
  }

  console.log(`daily-recipe-seeder: added ${items.length} new recipes (skipped ${(data.results?.length ?? 0) - items.length} duplicates).`);
};
