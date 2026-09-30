# Rupee fork notes

Rupee is a fork of [Sure](https://github.com/we-promise/sure), which is itself a fork of Maybe Finance. It is licensed under AGPLv3 like both. It is not affiliated with or endorsed by Maybe Finance Inc.

The design, requirements and task list live in [`.kiro/specs/rupee/`](.kiro/specs/rupee/).

## How the fork stays mergeable

Fork code lives in files upstream does not have. An upstream file is edited only when there is no hook for the change, and every such edit is listed below so each upstream merge can re-check it.

### Upstream files the fork edits

| File                                   | Change                                                                                | Upstream candidate |
| -------------------------------------- | ------------------------------------------------------------------------------------- | ------------------ |
| `app/models/assistant/configurable.rb` | Both system prompts use `config.x.product_name` instead of the literal "Sure" (R13.5) | Yes                |
| `app/models/provider/plaid.rb`         | Plaid Link's `client_name` is `config.x.product_name` instead of "Sure Finances"      | Yes                |

### Files the fork adds

| File                          | Purpose                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `config/initializers/fork.rb` | Product name default, log filter addition, production boot checks and host allowlist |
| `lib/fork/boot_checks.rb`     | The boot checks as a pure module, so they can be tested without booting production   |
| `test/lib/fork/`              | Tests for the above                                                                  |
| `FORK.md`                     | This file                                                                            |
| `.kiro/specs/rupee/`          | Design, requirements and tasks                                                       |

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
