# Security Audit — Keys & Secrets

Audit date: 2026-04-12

---

## Summary

| Secret | Where stored | In .gitignore? | Safe to commit? | Risk |
|--------|-------------|----------------|-----------------|------|
| Claude API key (`sk-ant-api03-…`) | `Config.xcconfig` | ✅ Yes | ❌ No | **High** if exposed |
| Supabase anon key (`sb_publishable_…`) | `SupabaseConfig.swift` | ❌ No | ✅ By design | Low |
| Supabase project URL | `SupabaseConfig.swift` | ❌ No | ✅ By design | Low |

---

## Claude API Key

**File**: `NomLens/Config.xcconfig`
**Status**: Gitignored — will NOT be committed

```
# .gitignore
NomLens/Config.xcconfig   ← present, covers the real key file
```

The `.example` file (`Config.xcconfig.example`) is tracked and contains only placeholders — safe.

### How it's used at runtime

```
Config.xcconfig  →  Info.plist $(CLAUDE_API_KEY)  →  APIKeyStore.key  →  ClaudeService
```

`APIKeyStore` reads from Keychain first (user-entered via Settings), then falls back to the bundle value from Info.plist. In a production/public App Store build, the xcconfig value is empty so only the keychain path works.

### Risk if the file were committed

The key is a full Anthropic API key (`sk-ant-api03-…`). Exposure would allow anyone to run Claude API calls billed to this account. Rotate immediately at console.anthropic.com if it leaks.

### Recommendations

- Keep `NomLens/Config.xcconfig` in `.gitignore` — already done ✅
- Add a pre-commit hook or CI check to block any file containing `sk-ant-api` from being committed
- Consider using a secrets scanner (e.g. `git-secrets`, `gitleaks`) on the repo

---

## Supabase Anon Key

**File**: `NomLens/Services/SupabaseConfig.swift`
**Status**: Tracked in git — intentional

```swift
static let anonKey = "sb_publishable_32OliLTW_R4pe6J1PlGa1w_i7xRNd0Z"
```

This is Supabase's **publishable** key — equivalent to a public API key. It is designed to be embedded in client apps and is safe to ship in a compiled binary. Access is governed entirely by **Row Level Security (RLS)** policies on the Supabase side.

### What the anon key can do

Only what RLS explicitly permits. The backend should be configured so that:
- Anonymous users can READ public sources/scans (browse archive)
- Anonymous users can INSERT sources, scans, characters (contribute)
- Anonymous users CANNOT update or delete records they don't own
- The `contributor_device_id` is used as a soft ownership token (not cryptographic)

### Risk

Low by Supabase's design — similar to a Firebase public config. However:
- If RLS is misconfigured, the anon key would be the attack surface
- The project ID (`nqdxtcsclxzbuqwzqxdz`) is also public — someone could probe the API directly

### Recommendations

- Verify RLS policies are enabled on `sources`, `scans`, `characters`, and `scan-images` bucket ✅ (assumed done — backend confirmed working)
- Rotate the anon key via Supabase dashboard if abuse is detected (all existing app installs would break until updated)

---

## Supabase Project URL

**File**: `NomLens/Services/SupabaseConfig.swift`
**Status**: Tracked in git — intentional

```swift
static let url = "https://nqdxtcsclxzbuqwzqxdz.supabase.co"
```

Public information. No risk beyond identifying the project.

---

## Info.plist

**File**: `NomLens/Info.plist`
**Status**: Tracked in git — safe as-is

Contains `$(CLAUDE_API_KEY)` — a variable reference, not the actual value. The substitution only happens at build time. The plist in the repo is safe.

---

## What would be exposed if you `git push` right now

Assuming `Config.xcconfig` stays gitignored:

| File | Contains | Exposed? |
|------|----------|----------|
| `SupabaseConfig.swift` | Supabase anon key + URL | ✅ Yes — intentional |
| `Info.plist` | `$(CLAUDE_API_KEY)` placeholder | ✅ Safe |
| `Config.xcconfig` | Real Claude API key | ❌ Gitignored, not pushed |
| `Config.xcconfig.example` | Placeholder values only | ✅ Safe |

**Bottom line**: safe to push as long as `Config.xcconfig` is gitignored, which it currently is.

---

## If you open-source the repo

Additional steps needed:
1. Rotate the Supabase anon key before publishing (the current one has been used in development)
2. Remove the Supabase project ID from `SupabaseConfig.swift` or replace with a placeholder + setup instructions
3. Verify no real key ever appeared in git history (`git log -p --all | grep sk-ant`)
