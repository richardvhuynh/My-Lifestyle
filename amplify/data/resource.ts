import { type ClientSchema, a, defineData } from '@aws-amplify/backend';

/*== Data model & authorization ===========================================
Authorization is enforced server-side per model so a signed-in user can only
touch their own data. The API runs in `userPool` mode (every caller is an
authenticated Cognito user — the app is sign-in gated), which is what makes
owner-based rules possible.

Identity: owner-based rules compare against Cognito's default owner claim
(`sub::username`). The client constructs the same string for cross-user
references (post authorId, friendship ids, fitness `viewers`) so the values
match what `ownersDefinedIn` checks. See `IdentityService` on the Swift side.
=========================================================================*/
const schema = a.schema({
  // Private to each user: only the creator can read/write their todos.
  Todo: a
    .model({
      content: a.string(),
    })
    .authorization((allow) => [allow.owner()]),

  // The shared, global Spoonacular catalog. Every signed-in user reads the same
  // records. `create`/`update` stay open to authenticated users so the one-time
  // seed and the lazy nutrition back-fill keep working; `delete` is denied so no
  // user can wipe the shared catalog. `ingredients`/`steps` are JSON strings.
  Recipe: a
    .model({
      name: a.string().required(),
      imageUrl: a.string(),
      category: a.string(),
      area: a.string(),
      servings: a.integer(),
      calories: a.integer(),
      protein: a.float(),
      carbs: a.float(),
      fat: a.float(),
      ingredients: a.string(),
      steps: a.string(),
      sourceId: a.string(),
    })
    .authorization((allow) => [allow.authenticated().to(['read', 'create', 'update'])]),

  // A recipe a user authored themselves. Private: only its owner can read,
  // edit, or delete it. Mirrors the catalog's field shape for easy reuse.
  UserRecipe: a
    .model({
      name: a.string().required(),
      imageUrl: a.string(),
      category: a.string(),
      area: a.string(),
      servings: a.integer(),
      calories: a.integer(),
      protein: a.float(),
      carbs: a.float(),
      fat: a.float(),
      ingredients: a.string(),
      steps: a.string(),
    })
    .authorization((allow) => [allow.owner()]),

  // A member's shared fitness data. The owner has full access; everyone else is
  // denied EXCEPT identities listed in `viewers` (the owner's accepted friends),
  // who may read. This is the server-enforced "friends-only" gate. `viewers`
  // holds friend owner-identity strings (`sub::username`).
  FitnessProfile: a
    .model({
      userId: a.string().required(),
      displayName: a.string(),
      weeklySteps: a.string(),
      activities: a.string(),
      updatedAtEpoch: a.float(),
      viewers: a.string().array(),
    })
    .identifier(['userId'])
    .authorization((allow) => [
      allow.owner(),
      allow.ownersDefinedIn('viewers').to(['read']),
    ]),

  // A shared Community feed post. Any signed-in user can read the whole feed and
  // create a post; only the author can edit or delete their own post. Likes are
  // tracked separately (see CommunityLike) so liking never edits the post.
  CommunityPost: a
    .model({
      author: a.string().required(),
      authorId: a.string(),
      recipeName: a.string().required(),
      caption: a.string(),
      imageBase64: a.string(),
      createdAtEpoch: a.float(),
    })
    .authorization((allow) => [
      allow.authenticated().to(['read', 'create']),
      allow.owner(),
    ]),

  // One like by one user on one post. The liker owns their like record (create/
  // delete), so anyone can like any post without being able to modify it. Reads
  // are open to authenticated users so the feed can total likes and mark which
  // posts the current user liked.
  CommunityLike: a
    .model({
      postId: a.string().required(),
      // The liker's stable owner-identity (`sub::username`), stamped by the client
      // so "has the current user liked this?" is a reliable match independent of the
      // implicit owner claim's format.
      userId: a.string(),
    })
    .authorization((allow) => [
      allow.owner(),
      allow.authenticated().to(['read']),
    ]),

  // A comment by one user on one post. Any signed-in user can read the thread and
  // add a comment; only the comment's author can edit or delete their own. Reads
  // are open so every member sees the full discussion under a post.
  CommunityComment: a
    .model({
      postId: a.string().required(),
      author: a.string().required(),
      authorId: a.string(),
      text: a.string().required(),
      createdAtEpoch: a.float(),
    })
    .authorization((allow) => [
      allow.authenticated().to(['read', 'create']),
      allow.owner(),
    ]),

  // A directional friend edge created by its author (`fromId` is the owner, so
  // each user only ever writes records they own — no cross-user updates). A
  // friendship is "mutual" when edges exist in both directions and neither is
  // declined. Authenticated read lets a user discover edges pointing at them
  // (incoming requests) and detect mutual links. Records hold only identities +
  // status, never fitness data. `status` is "active" or "declined".
  Friendship: a
    .model({
      fromId: a.string().required(),
      fromName: a.string(),
      toUsername: a.string().required(),
      toId: a.string(),
      status: a.string().required(),
    })
    .authorization((allow) => [
      allow.ownerDefinedIn('fromId'),
      allow.authenticated().to(['read']),
    ]),
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: 'userPool',
  },
});
