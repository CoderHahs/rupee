# Tasks: Rupee

> **DRAFT.** Task 0 was decided on 2026-09-30, and P0 is in progress. The design is in `design.md`, the requirements in `requirements.md`. The code is in `CoderHahs/rupee`.
>
> Estimates assume one operator working full-time with an AI agent. Double them for evenings and weekends.
>
> | Phase            | Tasks | Estimate                       |
> | ---------------- | ----- | ------------------------------ |
> | P0 foundation    | 1-8   | 1-2 weeks                      |
> | P1 card benefits | 9-18  | 3-5 weeks                      |
> | P2 mobile parity | 19-22 | 3-6 weeks                      |
> | P3 Monarch gaps  | 23-33 | 2-4 months                     |
> | P4 opening up    | 34-36 | 2-3 weeks, then contract-bound |

## Task 0: Decisions and setup (decided 2026-09-30)

- [x] 0.1 Base: fork Sure as `CoderHahs/rupee`, based at `0da863b` (D1)
  - _Requirements: 22.2_
- [x] 0.2 Personal use now; open to other households later (D2, design §3.2)
  - _Requirements: 22.4, 22.5, 22.6_
- [x] 0.3 Name: Rupee, which is also the AI agent's name
  - It sets `PRODUCT_NAME`, Plaid's `client_name`, the app ids, the callback scheme and the assistant prompts (design §4.12).
  - _Requirements: 22.4, 1.2, 13.5_
- [x] 0.4 Hosting: option A, on a cloud VM (D15, design §3.1)
  - The cloud provider and the tunnel are chosen in Task 3.1.
  - _Requirements: 21.3, 22.1_
- [x] 0.5 Repository: public and open source, with a personal git `user.email`
  - _Requirements: 22.2, 22.7_
- [x] 0.6 Time zone: America/New_York
  - _Requirements: 18.10, 15.4_

## P0: Foundation

- [ ] 1. Verify the premises before building
  - _Requirements: 2.1, 2.2, 2.5, 4.4, 5.4, 6.4, 9.5_
  - [ ] 1.1 Call Plaid `/institutions/search` for each of the household's institutions, with country codes US and CA
    - Record products (transactions, liabilities, investments), OAuth and Canadian Liabilities support per institution.
    - Confirm that Items needed fit within the 10-Item Trial cap once brokerages go to SnapTrade or Questrade.
    - _Requirements: 2.1, 2.2, 2.5, 9.5_
  - [ ] 1.2 Request one TSX and one TSXV ticker from the Alpha Vantage and EODHD free tiers, and choose `FORK_TSX_PRICE_PROVIDER` (open question 12)
    - _Requirements: 5.4_
  - [ ] 1.3 Read Sure's PFC matcher and pick the version to pin (open question 21)
    - _Requirements: 6.4_
  - [ ] 1.4 Read the Bank of Canada's Valet terms (open question 1)
    - _Requirements: 4.4_

- [x] 2. Fork scaffolding
  - _Requirements: 13.3, 18.8, 18.10, 22.2_
  - [x] 2.1 Create the fork layout from design §4.1: namespaces, `config/initializers/fork.rb`, `config/routes/fork.rb`, `config/fork_schedule.yml` and `FORK.md` with the hook list
    - _Requirements: 22.2_
  - [x] 2.2 Write the schedule loader, which creates, updates and removes only `fork:*` jobs
    - _Requirements: 22.2_
  - [x] 2.3 Write `bin/check-fork-surface`: hook list, file collisions, column collisions and the regenerated schema (design §5.1), and run it in `.github/workflows/fork.yml`
    - _Requirements: 22.2_
  - [x] 2.4 Create `household_settings` (design §5.2) and the household settings page
    - _Requirements: 13.3, 18.8, 18.10_
  - [x] 2.5 Build the AI switch: `Family#permitted_llm_provider`, the 10 call-site edits, the `Family` and `User` prepends, MCP -32010 and the import refusal (design §4.10)
    - _Requirements: 13.3_
  - [x] 2.8 Name the product and the agent Rupee: the `PRODUCT_NAME` default, Plaid's `client_name` and the product name in the assistant prompts (design §4.12)
    - _Requirements: 13.5, 22.4_
  - [x] 2.9 Build Rupee's onboarding consent: provider choice, what data is sent, and `ai_consented_at` (design §4.12)
    - _Requirements: 13.3, 13.8_
  - [x] 2.6 Build the time-zone confirmation and its banner (design §4.10)
    - _Requirements: 18.10_
  - [x] 2.7 Test: upstream's suite stays green, the surface check fails on each defect class, and no LLM host is contacted with the switch off
    - _Requirements: 22.2, 13.3_

- [ ] 3. Deployment, secrets and backups
  - _Requirements: 21.1, 21.3, 21.4, 21.5, 22.1, 22.4, 22.5_
  - [ ] 3.1 Choose the cloud provider and tunnel, and write the compose file with Caddy, the route allowlist and TLS (design §3.1, §7.1)
    - _Requirements: 21.3, 22.1_
  - [ ] 3.1a Provision the VM with encrypted volumes, Postgres on a Unix socket, and Tailscale (design §7.2)
    - _Requirements: 21.7, 21.8_
  - [x] 3.2 Add the boot checks: explicit encryption keys, a non-default `SECRET_KEY_BASE`, and `config.hosts` (design §7.2, finding 23)
    - _Requirements: 21.1, 21.3_
  - [x] 3.3 Add `hosted_link_url` to the log filter (design §7.3)
    - _Requirements: 21.5_
  - [ ] 3.4 Set up restic backups of the database dump and Active Storage, with the retention and checks in design §7.4
    - _Requirements: 21.4_
  - [ ] 3.5 Run the first restore drill and rehearse key rotation on the restored copy, before any real account is linked
    - _Requirements: 21.4, 21.9_
  - [x] 3.7 Add secret scanning on every push and pull request (design §8)
    - _Requirements: 22.7_
  - [x] 3.6 Add the AGPL footer with the running commit, and the README notices (design §7.7)
    - _Requirements: 22.4, 22.5_

- [ ] 4. Plaid gem upgrade and transaction signals
  - _Requirements: 6.4, 6.5_
  - [ ] 4.1 Upgrade `plaid` from 41.0.0 to 51.x and send the pinned PFC version (D5, D6)
    - _Requirements: 6.4_
  - [ ] 4.2 Persist MCC, PFC and `authorized_date` in `plaid_extra`, and add `CardBenefits::TransactionSignals` (design §4.4)
    - _Requirements: 6.4_
  - [ ] 4.3 Write `fork:plaid_signals_backfill` and its fill-rate report (answers open questions 3 and 7)
    - _Requirements: 6.5_
  - [ ] 4.4 Test: per-account counts and sums unchanged by the backfill; no callbacks run
    - _Requirements: 6.5_

- [ ] 5. Item budget and connection health
  - _Requirements: 2.5, 2.6, 2.7, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_
  - [ ] 5.1 Create `plaid_item_ledger_entries`, the backfill, and the guard in `Fork::PlaidItemBudget` (design §4.2)
    - _Requirements: 2.5, 2.6_
  - [ ] 5.2 Order the account-add chooser with brokerage connectors first (open question 16)
    - _Requirements: 2.7_
  - [ ] 5.3 Add the `plaid_items` and `plaid_accounts` health columns, and `fork:plaid_health_poll` (design §4.3)
    - _Requirements: 3.1, 3.2, 3.3_
  - [ ] 5.4 Extend the webhook processor for `PENDING_DISCONNECT`, `NEW_ACCOUNTS_AVAILABLE`, `LOGIN_REPAIRED` and the revocations, and exclude revoked Items from `syncable`
    - _Requirements: 3.4, 3.5, 3.6, 3.7_
  - [ ] 5.5 Build the `/connections` page, its statuses and next actions, and the banners
    - _Requirements: 3.8, 3.3_
  - [ ] 5.6 Test: one test per webhook code, a bad signature, an unhandled code, and the guard at 9, 10 and 11 Items
    - _Requirements: 2.5, 3.4, 3.5, 3.6, 3.7_

- [ ] 6. Exchange rates
  - _Requirements: 4.4, 4.5, 4.6, 4.8, 4.9, 4.10_
  - [ ] 6.1 Add `Provider::BankOfCanada` and the router, and select it at deploy (D9)
    - _Requirements: 4.4_
  - [ ] 6.2 Add `exchange_rates.source` and `observed_on`, the importer changes and the backfill (design §4.6)
    - _Requirements: 4.5, 4.8_
  - [ ] 6.3 Build `Fork::Fx.lookup`, the guards in `rates_for` and its callers, and the banners
    - _Requirements: 4.5, 4.6_
  - [ ] 6.4 Render `fork/fx_amount` wherever a converted amount is shown (open question 16)
    - _Requirements: 4.8_
  - [ ] 6.5 Write `transfer_fx_details` from the `Transfer` extension, and the net-worth breakdown by currency
    - _Requirements: 4.9, 4.10_
  - [ ] 6.6 Test: the §6.1 and §6.2 examples, the missing-rate fixture across every page, and the nightly Valet check
    - _Requirements: 4.4, 4.5, 4.6, 4.9_

- [ ] 7. Security prices
  - _Requirements: 5.4, 5.5_
  - [ ] 7.1 Map XTSX (TSX Venture) to `.TRV` and `V` with CAD, and assign TSX and TSXV listings to the chosen provider (D20)
    - _Requirements: 5.4_
  - [ ] 7.2 Add `security_prices.observed_on`, the backfill, and the carried-price label (D21)
    - _Requirements: 5.5_
  - [ ] 7.3 Add `Fork::HealthCheckPolicy` and `Fork::DetailsThrottle` (design §4.7)
    - _Requirements: 5.5_
  - [ ] 7.4 Test: no null `observed_on` after the backfill, and a failed health check keeps prices
    - _Requirements: 5.5_

- [ ] 8. Liabilities and card statement bills
  - _Requirements: 1.1, 1.4, 2.1, 2.3, 2.4, 3.7, 4.1, 4.2, 4.3, 4.7, 5.1, 5.2, 5.3, 5.6, 6.1, 6.2, 6.3, 7.1, 7.2, 7.4, 8.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 10.1, 11.1, 13.1, 13.2, 14.1, 21.2, 21.4, 22.3, 23.1_
  - [ ] 8.1 Move the three Liabilities processors to `enrich_attributes`, and select `purchase_apr` (finding 3)
    - _Requirements: 9.1, 9.2, 9.7_
  - [ ] 8.2 Create `liability_statements` and `Fork::Liabilities::Recorder`, with manual entry
    - _Requirements: 9.1, 9.5, 9.6_
  - [ ] 8.3 Build BillLinker, the `RecurringOccurrence` prepend and `fork:liability_payment_match` (design §4.5)
    - _Requirements: 9.3, 9.4_
  - [ ] 8.4 Test: the §6.8 states, a moved due date, a zero balance, and a payment counted once
    - _Requirements: 9.3, 9.4_
  - [ ] 8.5 Link the household's real accounts once the restore drill (3.5) has passed
    - _Requirements: 2.1, 21.4_
  - [ ] 8.6 Walk every feature marked Existing in design §9 on the deployed instance with real data, and file what does not work
    - "Existing" means the code is present at the pin, not that it was exercised.
    - _Requirements: 1.1, 1.4, 2.3, 2.4, 3.7, 4.1, 4.2, 4.3, 4.7, 5.1, 5.2, 5.3, 5.6, 6.1, 6.2, 6.3, 7.1, 7.2, 7.4, 8.1, 8.2, 8.3, 8.4, 10.1, 11.1, 13.1, 13.2, 14.1, 21.2, 23.1_
  - [ ] 8.7 Offer the upstream candidates in the hook list: MCC and PFC persistence, the Liabilities mapping, the `apr_type` fix and the Bank of Canada provider (design §4.1)
    - _Requirements: 22.3_

## P1: Card benefits

- [ ] 9. Card catalog
  - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5, 17.8_
  - [ ] 9.1 Create `card_catalog_loads`, `card_products` and `card_product_versions` (design §5.3)
    - _Requirements: 17.1, 17.3_
  - [ ] 9.2 Write `CardBenefits::CatalogLoader` with the five checks and the all-or-nothing load
    - _Requirements: 17.2, 17.5, 17.8_
  - [ ] 9.3 Write catalog entries for the household's cards from the issuers' own pages
    - _Requirements: 17.1, 17.8_
  - [ ] 9.4 Add the staleness badge and `stale: true` in every response
    - _Requirements: 17.4_
  - [ ] 9.5 Test: each loader check rejects its defect and leaves the previous catalog in force
    - _Requirements: 17.5_

- [ ] 10. Card instances and overrides
  - _Requirements: 17.6, 17.7, 18.10, 19.4_
  - [ ] 10.1 Create `card_instances`, custom products and the `Account` association; handle product changes
    - _Requirements: 17.6_
  - [ ] 10.2 Create `card_overrides` and `card_category_overrides`
    - _Requirements: 17.7, 19.4_
  - [ ] 10.3 Block turning card benefits on until the time zone is confirmed
    - _Requirements: 18.10_

- [ ] 11. Credit periods and enrollment
  - _Requirements: 18.1, 18.2, 18.10_
  - [ ] 11.1 Write `CardBenefits::PeriodCalculator` for every basis, including `every_years`
    - _Requirements: 18.1, 18.10_
  - [ ] 11.2 Create periods idempotently in `fork:card_credit_match`, and record enrollment
    - _Requirements: 18.1, 18.2_
  - [ ] 11.3 Test: the §6.3 years, and periods tiling every day from 2024 to 2030
    - _Requirements: 18.1, 18.10_

- [ ] 12. Credit matching
  - _Requirements: 18.3, 18.4, 18.5, 18.6, 18.9_
  - [ ] 12.1 Write `CardBenefits::CreditMatcher`: tiers, confidence, the threshold, postings and refunds (design §4.8)
    - _Requirements: 18.3, 18.4, 18.5, 18.6_
  - [ ] 12.2 Let members confirm, reject and add usage
    - _Requirements: 18.6, 18.9_
  - [ ] 12.3 Test: the §6.7 example
    - _Requirements: 18.3, 18.4, 18.5, 18.6_

- [ ] 13. Card benefits page
  - _Requirements: 14.1, 17.7, 18.7_
  - [ ] 13.1 Build `/card_benefits` with amount, used, received, remaining and days left per credit
    - _Requirements: 18.7_
  - [ ] 13.2 Apply the account permissions for reads, overrides and annotations (design §4.8)
    - _Requirements: 14.1, 17.7_

- [ ] 14. Which card to use
  - _Requirements: 4.6, 19.1, 19.2, 19.3, 19.4, 19.5_
  - [ ] 14.1 Write `CardBenefits::PurchaseFilter`, `CategoryResolver` and `CapTracker`
    - _Requirements: 19.3, 19.4_
  - [ ] 14.2 Write `CardBenefits::Recommender` and `/card_benefits/recommendation`
    - _Requirements: 19.1, 19.2, 19.3_
  - [ ] 14.3 Create `reward_program_values`
    - _Requirements: 19.5_
  - [ ] 14.4 Test: the §6.4, §6.5 and §6.6 examples, and a card with no rate listed as not ranked
    - _Requirements: 19.1, 19.2, 19.3, 19.4, 4.6_

- [ ] 15. Rotating categories, welcome offers and fees
  - _Requirements: 19.6, 20.1, 20.2_
  - [ ] 15.1 Create `rotating_activations` and the activation flow
    - _Requirements: 19.6_
  - [ ] 15.2 Create `welcome_offers` and `CardBenefits::WelcomeOfferTracker`
    - _Requirements: 20.1_
  - [ ] 15.3 Create `card_fee_events` and `CardBenefits::FeeDetector`
    - _Requirements: 20.2_
  - [ ] 15.4 Test: the §6.9 and §6.10 examples
    - _Requirements: 20.1, 20.2_

- [ ] 16. Card value, missed value and reward balances
  - _Requirements: 20.3, 20.4, 20.5_
  - [ ] 16.1 Write `CardBenefits::CardValue` and `CardBenefits::MissedValue`
    - _Requirements: 20.3, 20.4_
  - [ ] 16.2 Create `reward_balances`
    - _Requirements: 20.5_
  - [ ] 16.3 Test: the §6.11 example, and missed value leaving out periods ended by a product change
    - _Requirements: 20.3, 20.4_

- [ ] 17. Notifications
  - _Requirements: 1.5, 3.2, 3.4, 4.6, 15.1, 15.2, 15.3, 15.4, 15.5, 18.8, 19.6, 20.1, 20.2, 20.5_
  - [ ] 17.1 Create the four notification tables (design §5.4) and the planner, digest and dispatch jobs
    - _Requirements: 15.2, 15.4, 15.5_
  - [ ] 17.2 Wire every event source in design §4.10, including the P0 connection and FX events
    - _Requirements: 15.2, 3.2, 3.4, 4.6, 18.8, 19.6, 20.1, 20.2, 20.5_
  - [ ] 17.3 Build the inbox, the preferences page and `Fork::NotificationMailer`
    - _Requirements: 15.1, 15.3_
  - [ ] 17.4 Build `push_devices` and `Fork::Push::FcmClient` on the server
    - _Requirements: 15.1, 1.5_
  - [ ] 17.5 Test: a second planner run creates nothing, the digest hour across daylight-saving changes, and retries stop after 5 attempts
    - _Requirements: 15.4, 15.5_

- [ ] 18. Assistant tools and export
  - _Requirements: 13.4, 19.7, 21.6, 23.2_
  - [ ] 18.1 Add `get_card_recommendation` and `get_expiring_credits` (design §4.8)
    - _Requirements: 13.4, 19.7_
  - [ ] 18.2 Add the `Family::DataExporter` and `Family::DataImporter` prepends (design §5.6)
    - _Requirements: 21.6, 23.2_
  - [ ] 18.3 Test: a fork export imports into a fresh family, and a plain Sure import of it succeeds
    - _Requirements: 21.6, 23.2_

## P2: Mobile parity

- [ ] 19. Fork API
  - _Requirements: 1.3, 3.3, 22.3_
  - [ ] 19.1 Build the `/api/ext/v1` endpoints in design §4.9, with scopes and preview gates
    - _Requirements: 1.3, 3.3_
  - [ ] 19.2 Offer the gap-filling endpoints upstream (open question 22)
    - _Requirements: 22.3_

- [ ] 20. Mobile screens
  - _Requirements: 1.2, 1.3, 3.3, 19.7, 22.4_
  - [ ] 20.1 Build the R1.3 areas on the fork API, including the Cards tab and the connections screen
    - _Requirements: 1.3, 19.7, 3.3_
  - [ ] 20.2 Rename the app ids and callback scheme to Rupee
    - _Requirements: 1.2, 22.4_

- [ ] 21. Linking from the phone
  - _Requirements: 1.2, 2.1, 3.3_
  - [ ] 21.1 Build Hosted Link: `plaid_link_sessions`, the webhook handling, the completion job and the sweep (design §4.9)
    - _Requirements: 1.2, 2.1_
  - [ ] 21.2 Add `flutter_web_auth_2` and the app's link and reconnect flows
    - _Requirements: 1.2, 3.3_
  - [ ] 21.3 Test end to end in the Plaid Sandbox, new and update mode (open question 17)
    - _Requirements: 1.2, 2.1_

- [ ] 22. Push on the phone
  - _Requirements: 1.2, 1.4, 1.5, 15.1_
  - [ ] 22.1 Decide whether to join the Apple Developer Program ($99 a year), which iOS push and universal links need (design §4.9)
    - _Requirements: 1.5_
  - [ ] 22.2 Add `firebase_messaging` behind `FORK_PUSH`, device registration and notification opening
    - _Requirements: 1.5, 15.1_
  - [ ] 22.3 Run the manual device checklist in design §8
    - _Requirements: 1.2, 1.4, 1.5_

## P3: Monarch gaps

Each P3 task starts with its own short design, from the sketch in design §5.7.

- [ ] 23. Carry edits from pending to posted transactions
  - _Requirements: 6.6_
- [ ] 24. Review mode and its weekly reminder
  - _Requirements: 6.7_
- [ ] 25. Receipt extraction, and receipts forwarded by email (needs an inbound mail path)
  - _Requirements: 6.8, 6.9_
- [ ] 26. Saved report configurations
  - _Requirements: 10.2_
- [ ] 27. Spending treemap with drill-down
  - _Requirements: 10.3_
- [ ] 28. Weekly recap on the dashboard and by email
  - _Requirements: 10.4_
- [ ] 29. Net worth forecasting, scenarios and the early-withdrawal penalty
  - _Requirements: 11.2, 11.3, 11.4_
- [ ] 30. Equity compensation
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_
- [ ] 31. Credit score history, entered by hand
  - _Requirements: 16.1, 16.2_
- [ ] 32. Flex budgets
  - _Requirements: 7.3_
- [ ] 33. Outside read-only viewer limited to chosen accounts
  - _Requirements: 14.2_

## P4: More connectors and opening up

- [ ] 34. MX, a second aggregator (design §4.11)
  - _Requirements: 2.8, 2.9, 3.8, 6.4_
  - [ ] 34.1 Get MX development keys and allowlist the VM's address; answer open questions 24 to 26
    - _Requirements: 2.8, 2.9_
  - [ ] 34.2 Generate the provider with `rails g provider:global mx`, and add `MxItem` and `MxAccount`
    - _Requirements: 2.8_
  - [ ] 34.3 Import accounts and transactions with source `mx`, and add the `extra["mx"]` signals reader
    - _Requirements: 2.8, 6.4_
  - [ ] 34.4 Map member statuses onto the connection statuses, and list MX in the account-add chooser behind the production gate
    - _Requirements: 2.9, 3.8_
  - [ ] 34.5 Test against MX's development environment
    - _Requirements: 2.8, 2.9_
- [ ] 35. Rupee's agent features (design §4.12)
  - _Requirements: 1.3, 13.1, 13.5, 13.6, 13.7_
  - [ ] 35.1 Turn chat write tools into proposals that apply on confirmation
    - _Requirements: 13.6_
  - [ ] 35.2 Add `get_connection_health` and `get_upcoming_reminders`
    - _Requirements: 13.1, 13.7_
  - [ ] 35.3 Write the daily briefing, with the template fallback
    - _Requirements: 13.7_
  - [ ] 35.4 Add the Rupee tab to the mobile app
    - _Requirements: 13.5, 1.3_
- [ ] 36. Opening up to other households (design §3.2)
  - _Requirements: 21.3, 21.7, 22.6_
  - [ ] 36.1 Move to hosting option B, a paid Plaid plan, and a privacy policy and terms of use
    - _Requirements: 22.6, 21.3_
  - [ ] 36.2 Decide on per-household encryption keys (open question 27)
    - _Requirements: 21.7_
