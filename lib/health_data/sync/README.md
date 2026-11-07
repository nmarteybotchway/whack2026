# Sync

Place collection coordination, per-source cursors, retry handling, and optional
Firebase upload logic here. Advance cursors only after successful persistence.

Scope uploads to the signed-in user's `users/{uid}/` subtree. Upload only when
cloud sharing is enabled, and propagate corrections and deletions. Background
collection will need platform support and appropriate permissions.
