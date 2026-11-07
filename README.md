# whack2026

See [Shopping assistant](docs/assistant.md) for assistant behavior, personality
settings, data access and local verification.

## Data layout

All data belonging to a user is stored in Firebase under `users/{uid}/`, where
`{uid}` is the signed-in user's Firebase Auth UID (`FirebaseAuth.instance.currentUser!.uid`).
Nothing user-specific should be written outside this path, so security rules can
restrict each user to their own subtree:

```
users/
  {uid}/
    ...   # everything for this user
```
