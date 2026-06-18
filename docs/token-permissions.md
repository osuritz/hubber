# Token permissions

Hubber is **read-only** — it never writes, comments, merges, or pushes. These instructions show you the smallest token that works for each provider, so you're not handing over more access than necessary.

---

## GitHub.com

GitHub offers two token types. Either works; fine-grained PATs are the better choice for new tokens.

### Fine-grained PAT (recommended)

Fine-grained PATs scope permissions per repository, which makes them the tightest option.

**Minimum permissions:**

| Permission | Level | Why |
|---|---|---|
| **Metadata** | Read-only | Required for all fine-grained PATs — can't be removed |
| **Pull requests** | Read-only | Lists your open PRs, incoming review requests, and draft PRs |
| **Commit statuses** | Read-only | CI/check status on your outgoing PRs |

> **Tip:** Set **Repository access** to *All repositories* (or at minimum every repo you want Hubber to track). If a repo is missing from the list, Hubber simply won't see PRs from it.

**How to create one:**

1. Go to **github.com → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
   (direct link: [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new))
2. Give it a name (e.g. "Hubber") and an expiration.
3. Under **Repository access**, choose *All repositories* or select specific repos.
4. Under **Permissions**, expand **Repository permissions** and set:
   - Pull requests → Read-only
   - Commit statuses → Read-only
   (Metadata is already Read-only and cannot be changed.)
5. Click **Generate token** and paste it into Hubber.

### Classic PAT

Classic PATs use coarser scopes that apply across all your repos.

**Minimum scopes:**

| Scope | Why |
|---|---|
| `repo` | Needed to read PRs and CI status in **private** repositories |
| `public_repo` | Sufficient if you only track **public** repositories |

> **What NOT to grant:** `admin:org`, `admin:repo_hook`, `gist`, `delete_repo`, `write:*` — Hubber doesn't need any of these.

**How to create one:**

1. Go to **github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)**
   (direct link: [github.com/settings/tokens/new](https://github.com/settings/tokens/new))
2. Give it a name and an expiration.
3. Check **`repo`** (or just `public_repo` for public-only tracking).
4. Click **Generate token** and paste it into Hubber.

---

## GitHub Enterprise Server

Identical to GitHub.com — the same token types and the same permissions apply. The only difference is that you create the token on your GHES instance, not on github.com.

**Fine-grained PAT:** `your-ghes-host.com → Settings → Developer settings → Personal access tokens → Fine-grained tokens`

**Classic PAT:** `your-ghes-host.com → Settings → Developer settings → Personal access tokens → Tokens (classic)`

Use the same permission table from the GitHub.com section above. When adding the account in Hubber, enter your server URL (e.g. `https://github.your-company.com`).

---

## GitLab

Hubber talks exclusively to GitLab's GraphQL API to read your identity, authored MRs, review requests, reviewer status, pipeline results, and discussion counts.

**Minimum scope: `read_api`**

> `read_api` grants read access to the full API, including GraphQL — which is exactly what Hubber needs.
>
> **Do NOT use `api`** — that scope includes write access. It will work, but it's more access than Hubber needs.
>
> **Do NOT use only `read_user`** — that scope only covers the REST `/user` endpoint and won't let Hubber run its GraphQL queries.

**How to create one:**

1. Go to your avatar (top-right) → **Edit profile → Access tokens**
   - GitLab.com direct link: [gitlab.com/-/user_settings/personal_access_tokens](https://gitlab.com/-/user_settings/personal_access_tokens)
   - Self-managed: the same page on your server, e.g. `https://gitlab.your-company.com/-/user_settings/personal_access_tokens`
2. Give it a name (e.g. "Hubber") and an expiration date.
3. Check **`read_api`**. That's it — nothing else is needed.
4. Click **Create personal access token**, copy it, and paste it into Hubber.

**Self-managed GitLab** works the same way — just enter your server URL when adding the account in Hubber.

---

## Token rejected?

A few things to check if Hubber rejects your token:

- **Wrong scope:** Re-create the token with the exact permissions listed above. A `read_user`-only GitLab token or a `public_repo` classic GitHub token used against private repos are common mismatches.
- **SAML / SSO enforcement:** If your GitHub organization uses SAML SSO, the token also needs to be **authorized for that org** after creation. Look for the *Authorize* button next to your org on the token's settings page.
- **Token expired:** PATs have expiration dates. Delete the old connection in Hubber and add it again with a fresh token.
- **Very old GHES / self-managed GitLab:** Hubber expects modern GraphQL fields. On an older self-managed instance some of those fields may not exist, which can cause the fetch to error — keeping your instance reasonably up to date avoids this.
