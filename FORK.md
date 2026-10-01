# Rupee fork notes

Rupee is a fork of [Sure](https://github.com/we-promise/sure), which is itself a fork of Maybe Finance. It is licensed under AGPLv3 like both. It is not affiliated with or endorsed by Maybe Finance Inc.

The design, requirements and task list live in [`.kiro/specs/rupee/`](.kiro/specs/rupee/).

## How the fork stays mergeable

Fork code lives in files upstream does not have. An upstream file is edited only when there is no hook for the change, and every such edit is listed below so each upstream merge can re-check it.

### Upstream files the fork edits

| File                                                       | Change                                                                       | Upstream candidate |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------- | ------------------ |
| `app/models/assistant/configurable.rb`                     | Both system prompts use `config.x.product_name` instead of "Sure" (R13.5)    | Yes                |
| `app/models/assistant/function/get_account_statement.rb`   | Tool description says "the app" instead of "Sure"                            | Yes                |
| `app/models/provider/plaid.rb`                             | Plaid Link's `client_name` is the product name instead of "Sure Finances"    | Yes                |
| `app/models/user.rb`                                       | The authenticator-app issuer is the product name instead of "Sure Finances"  | Yes                |
| `app/controllers/concerns/webauthn_relying_party.rb`       | The passkey prompt shows the product name instead of "Sure"                  | Yes                |
| `app/views/impersonation_sessions/_approval_bar.html.erb`  | Support banners use the product name                                         | Yes                |
| `app/views/layouts/doorkeeper/application.html.erb`        | The OAuth consent heading uses the product name                              | Yes                |
| `public/offline.html`                                      | Page title "Offline - Rupee" (static file, so the name is literal)           | No                 |
| `mobile/` display names, l10n and README                   | App name "Rupee" on Android and iOS; English and Swedish strings             | No                 |
| Tests asserting English copy (8 files)                     | Expected strings say Rupee, and the VCR cassette's `client_name` is "Rupee"  | No                 |

### Files the fork adds

| File                          | Purpose                                                                                     |
| ----------------------------- | ------------------------------------------------------------------------------------------- |
| `config/initializers/fork.rb` | Product name default, fork locales, log filter addition, boot checks and host allowlist     |
| `config/fork/locales/en.yml`  | Generated English overrides for strings where upstream names the app "Sure"                 |
| `lib/fork/boot_checks.rb`     | The boot checks as a pure module, so they can be tested without booting production          |
| `lib/fork/branding.rb`        | Finds upstream's English "Sure" strings and renders the overrides                           |
| `lib/tasks/fork.rake`         | `bin/rails fork:locales` regenerates the overrides                                          |
| `test/lib/fork/`              | Tests for the above                                                                         |
| `FORK.md`                     | This file                                                                                   |
| `.kiro/specs/rupee/`          | Design, requirements and tasks                                                              |

### Branding

The name is Rupee everywhere a person sees it in English. Rather than edit about 30 upstream locale files, `bin/rails fork:locales` writes an override for each English string that names "Sure" into `config/fork/locales/en.yml`, which loads after `config/locales`. `test/lib/fork/branding_test.rb` fails when the generated file no longer matches upstream, so after each upstream merge run `bin/rails fork:locales` and commit the result. The overrides say "Rupee" literally, so a different `PRODUCT_NAME` also needs them regenerated.

Deliberately still "Sure":

- Strings about Sure's export format and the "Import from Sure" option, because those files really are Sure exports (`Fork::Branding::KEEP_KEYS`).
- The managed-mode "Contribute and support Sure" page, which is upstream's donation flow.
- Translations other than English and Swedish. Their fallback is upstream's text.
- Internal identifiers that are stored or sent elsewhere: provider `User-Agent` headers, the `Sure Mobile` OAuth application record that `mobile_device.rb` looks up by name, the `X-Sure-*` API headers, `Sure.version`, and the mobile app ids (`am.sure.mobile`), which change with the mobile work in design §4.9.

The authenticator issuer only labels new enrolments. Codes from existing ones still verify, because a TOTP code depends on the secret alone.

`config/initializers/fork.rb` runs after `brand.rb` and `filter_parameter_logging.rb` because initializers load in name order. Renaming it would silently undo the product name default.

## Production requirements

In production Rupee refuses to boot unless all of these are set. Upstream Sure only logs a warning when the encryption keys are missing, and without them it stores provider tokens in plaintext.

| Variable                                       | Notes                                                                                       |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`         | From `bin/rails db:encryption:init`                                                         |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`   | From `bin/rails db:encryption:init`                                                         |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | From `bin/rails db:encryption:init`                                                         |
| `SECRET_KEY_BASE`                              | From `bin/rails secret`. The values in `compose.example.yml` and `.env.example` are refused |
| `APP_DOMAIN`                                   | The only host allowed besides `FORK_PUBLIC_HOST`                                            |
| `FORK_PUBLIC_HOST` (optional)                  | The tunnel's public host for the webhook routes                                             |

`/up` is exempt from host authorization so container health checks work. `assets:precompile` with `SECRET_KEY_BASE_DUMMY` skips the checks.

Keep the three encryption keys and `SECRET_KEY_BASE` in a password manager as well as on the host. Losing the encryption keys makes every encrypted column unreadable, including in backups.

**An instance that already ran without keys** has plaintext rows. Set the keys plus `ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED_DATA=true`, run `bin/rails security:backfill_encryption`, then remove that variable.

## Key rotation runbook

Status: **not yet rehearsed.** It is rehearsed on a restored copy before real accounts are linked (task 3.5, R21.9).

Rails encrypts with the last primary key in a list and decrypts with any of them.

1. Take a backup and confirm it restores.
2. Generate a new primary key with `bin/rails db:encryption:init` and keep only its `primary_key`.
3. Set the primary key to the list `old,new` (the app must parse the variable as a list; not yet implemented).
4. Deploy. New writes use the new key and old rows still decrypt.
5. Re-save every encrypted record so it is encrypted with the new key.
6. Confirm no row still needs the old key, then remove it from the list and deploy.

Rails does not support rotating the deterministic key for columns that are queried, because the same plaintext must always produce the same ciphertext. Rotating it means re-encrypting those columns in one maintenance window.

## Merging upstream

1. `git fetch upstream` and merge `upstream/main` into a branch.
2. Re-check each row of "Upstream files the fork edits".
3. Run the full test suite.
4. Record the merged upstream commit below.

| Date                   | Upstream commit merged |
| ---------------------- | ---------------------- |
| 2026-09-30 (fork base) | `0da863b7`             |
