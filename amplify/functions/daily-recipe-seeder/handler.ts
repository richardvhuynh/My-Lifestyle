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

// Strips HTML tags and entities (e.g. "&nbsp;") that Spoonacular leaves in
// step and ingredient text, and collapses whitespace.
function cleanText(s: string): string {
  return (s || '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
    .replace(/&#39;|&rsquo;|&apos;/gi, "'").replace(/&quot;|&ldquo;|&rdquo;/gi, '"')
    .replace(/&deg;/gi, '°')
    .replace(/\s+/g, ' ')
    .trim();
}

// Herbs and seasonings read as spoons, not a "whole" count.
const SEASONINGS = ['salt', 'pepper', 'parsley', 'thyme', 'cilantro', 'coriander',
  'basil', 'oregano', 'rosemary', 'mint', 'dill', 'chive', 'sage', 'tarragon', 'marjoram'];

// Produce peppers are counted vegetables, not the "pepper" seasoning.
const PRODUCE_PEPPERS = ['bell pepper', 'red pepper', 'green pepper', 'yellow pepper',
  'orange pepper', 'sweet pepper', 'jalapeno', 'capsicum', 'poblano', 'serrano', 'habanero'];

function normalizeUnit(name: string, unit: string): string {
  const n = name.toLowerCase();
  if (PRODUCE_PEPPERS.some((p) => n.includes(p))) return unit;
  if (unit !== 'whole') return unit;
  return SEASONINGS.some((h) => n.includes(h)) ? 'tbsp' : unit;
}

// Imperative verbs that open a cooking instruction. Spoonacular's ingredient
// parser sometimes mistakes a step sentence for an ingredient (e.g. "Add the
// peppers", "Reduce the heat a little"); such entries begin with one of these
// and are rejected by isPlausibleIngredientName.
const INSTRUCTION_VERBS = new Set([
  'add', 'heat', 'reduce', 'cook', 'stir', 'season', 'serve', 'mix', 'place',
  'remove', 'bring', 'simmer', 'saute', 'sauté', 'bake', 'pour', 'combine',
  'whisk', 'beat', 'fold', 'drain', 'cut', 'chop', 'slice', 'dice', 'mince',
  'preheat', 'transfer', 'cover', 'let', 'set', 'spread', 'sprinkle', 'garnish',
  'roll', 'knead', 'boil', 'roast', 'grill', 'fry', 'blend', 'mash', 'peel',
  'grate', 'melt', 'arrange', 'divide', 'repeat', 'continue', 'allow', 'discard',
  'reserve', 'rinse', 'wash', 'soak', 'marinate', 'whip', 'turn', 'flip', 'top',
  'layer', 'drizzle', 'brush', 'dust', 'taste', 'adjust', 'refrigerate', 'chill',
  'freeze', 'warm', 'reheat', 'can', 'make', 'prepare', 'wipe',
]);

// True when a parsed name reads like a real ingredient rather than a stray
// instruction fragment: a short noun phrase with no sentence punctuation that
// doesn't open with an imperative cooking verb.
function isPlausibleIngredientName(name: string): boolean {
  const t = name.trim();
  if (!t) return false;
  if (t.includes('.') || t.includes('!')) return false;
  const words = t.split(/\s+/);
  if (words.length > 5) return false;
  if (INSTRUCTION_VERBS.has(words[0].toLowerCase())) return false;
  return true;
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

    const title = cleanText(r.title || '');
    if (!title) continue;
    const servings = Math.max(1, r.servings || 1);
    const nutrient = (name: string): number =>
      r.nutrition?.nutrients?.find((n: any) => n.name === name)?.amount ?? 0;

    const ingredients = (r.extendedIngredients ?? [])
      .map((e: any) => {
        const nm = cleanText((e.nameClean || e.name || '') as string);
        if (!nm || !isPlausibleIngredientName(nm)) return null;
        const amount = (e.amount ?? 0) > 0 ? e.amount : 1;
        return { amount, unit: normalizeUnit(nm, mapUnit(e.unit || '')), id: randomUUID().toUpperCase(), name: titleCase(nm) };
      })
      .filter((x: unknown) => x !== null);

    const steps: any[] = [];
    for (const group of r.analyzedInstructions ?? []) {
      for (const s of group.steps ?? []) {
        const text = cleanText(s.step || '');
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
