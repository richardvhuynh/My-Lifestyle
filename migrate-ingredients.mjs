// One-off migration: strip Spoonacular instruction fragments that its parser
// mislabeled as ingredients (e.g. "Add the peppers") from existing Recipe
// records. Mirrors isPlausibleIngredientName in the app + seeder. Free: scan →
// filter ingredients JSON in place → update-item. Safe to re-run (idempotent).
import { DynamoDBClient, ScanCommand, UpdateItemCommand } from '@aws-sdk/client-dynamodb';

const TABLE = 'Recipe-4mxmqvv35vf4ppq56vtw5g3eka-NONE';
const client = new DynamoDBClient({ region: 'us-east-2' });

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

function isPlausibleIngredientName(name) {
  const t = (name || '').trim();
  if (!t) return false;
  if (t.includes('.') || t.includes('!')) return false;
  const words = t.split(/\s+/);
  if (words.length > 5) return false;
  if (INSTRUCTION_VERBS.has(words[0].toLowerCase())) return false;
  return true;
}

let scanned = 0, updated = 0, removed = 0;
let startKey;
do {
  const out = await client.send(new ScanCommand({
    TableName: TABLE,
    ProjectionExpression: 'id, ingredients',
    ExclusiveStartKey: startKey,
  }));
  for (const item of out.Items ?? []) {
    scanned++;
    const raw = item.ingredients?.S;
    if (!raw) continue;
    let list;
    try { list = JSON.parse(raw); } catch { continue; }
    if (!Array.isArray(list)) continue;
    const kept = list.filter((ing) => isPlausibleIngredientName(ing?.name));
    if (kept.length === list.length) continue;
    removed += list.length - kept.length;
    await client.send(new UpdateItemCommand({
      TableName: TABLE,
      Key: { id: item.id },
      UpdateExpression: 'SET ingredients = :i',
      ExpressionAttributeValues: { ':i': { S: JSON.stringify(kept) } },
    }));
    updated++;
  }
  startKey = out.LastEvaluatedKey;
} while (startKey);

console.log(`scanned ${scanned} recipes, updated ${updated}, removed ${removed} junk ingredients`);
