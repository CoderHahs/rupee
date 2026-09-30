# Requirements: Rupee

> **DRAFT.** Task 0 was decided on 2026-09-30 (`design.md` §1.5). The fork is `CoderHahs/rupee`.
>
> Evidence dates 2026-09-28 and 2026-09-29. Sure references are to `we-promise/sure@5e9e3b1`. "Existing" means a model or controller for the feature exists at that commit. Its behaviour has not been exercised.

## Introduction

Rupee is a Monarch-class personal finance app for desktop web and mobile. It has seven product constraints:

1. Multiple currencies, converted correctly at historical rates.
2. US and Canadian bank, card, loan and brokerage accounts.
3. Every feature in Monarch, Maybe and Sure. Sure forked Maybe's final release (v0.6.0), so the union is Sure plus the Monarch-only features. `design.md` §9 lists every feature with its source, status and phase.
4. Credit card benefits tracking: which card to use for a purchase, and which credits are about to lapse. None of the three products has this natively (`design.md` Appendix A.6).
5. AI native: an agent, also named Rupee, is the front door of the app (Requirement 13).
6. Encryption first: every layer that holds or carries household data is encrypted (Requirement 21).
7. Not tied to one aggregator: Plaid first, with MX and others behind the same connection model (Requirement 2).

The first user is a cross-border household with US and Canadian brokerage, retirement and registered accounts. It is personal for now, and should later open to other households (`design.md` §3.2).

Phase tags:

- **P0**: foundation.
- **P1**: card benefits.
- **P2**: mobile parity.
- **P3**: Monarch gaps.
- **P4**: more connectors, and opening up to other households.
- **Existing**: kept from Sure and regression-tested, not rebuilt.

### Glossary

- **Rupee**: the product, and the name of its AI agent.
- **Family**: a household. This is Sure's tenancy unit, and members share it.
- **Base currency**: the family's reporting currency.
- **Native currency**: an account's own currency.
- **Item**: one Plaid connection to one institution login. The Plaid Trial plan caps Production Items at 10.
- **Card product**: a catalog entry for a card, versioned over time.
- **Card instance**: a family's own card, linked to a credit card account.
- **Credit**: a fixed-amount statement credit that renews on a schedule.
- **Period**: the window in which one credit can be used. It is a calendar month, quarter, half-year or year; a cardmember year; or a multi-year window.
- **Earn rule**: a rewards multiplier for a merchant list, an MCC set, an issuer category or all purchases, with an optional cap.
- **SUB**: a sign-up (welcome) bonus with a spend requirement and a deadline.
- **MCC**: merchant category code.
- **PFC**: Plaid `personal_finance_category`.

## Requirements

### Requirement 1: Web and mobile access (P0 web, P2 mobile)

**User Story:** As a household member, I want the app in a desktop browser and on my phone, so that I can review finances at a desk and decide on the go.

#### Acceptance Criteria

1. The app SHALL serve its full feature set in a desktop browser and SHALL be installable as a PWA (existing `PwaController`).
2. The app SHALL ship iOS and Android clients built from Sure's Flutter app. They SHALL authenticate with OAuth2 (Doorkeeper) or an API key (existing API auth).
3. The mobile client SHALL provide these areas (P2):
   - dashboard;
   - accounts;
   - transactions, with categorize, split, tag, note and photo attachment;
   - budgets;
   - goals;
   - investments;
   - cash flow and reports;
   - bills;
   - card benefits;
   - account linking.
4. WHERE biometric lock is enabled, WHEN the mobile app returns to the foreground THEN it SHALL require biometrics or the device passcode before showing data (existing).
5. The mobile client SHALL receive push notifications for the events in Requirement 15 (P2).

### Requirement 2: US and Canadian account aggregation (P0)

**User Story:** As a cross-border household, I want my US and Canadian accounts to sync automatically, so that I don't maintain balances by hand.

#### Acceptance Criteria

1. The app SHALL link US and Canadian depository, credit card, loan and investment accounts through Plaid, using country codes US and CA (existing `Provider::Plaid#country_codes`).
2. The app SHALL link brokerage accounts through SnapTrade and Questrade. Coverage SHALL include Wealthsimple and Questrade registered accounts (TFSA, RRSP, FHSA). Both providers already exist, so this is configuration only.
3. WHERE Plaid and SnapTrade do not cover an institution, the app SHALL offer SimpleFIN Bridge, file import (Requirement 23) and manual accounts.
4. WHEN a user links a credit card or loan THEN the app SHALL request Plaid Liabilities for that Item (existing `get_primary_product`).
5. The app SHALL show how many Production Items are in use against the plan's Item cap. WHEN a new link would exceed the cap THEN the app SHALL block it and say why.
6. WHILE the Plaid plan is Trial, the app SHALL repair broken connections only through Link update mode. On the Trial plan, `/item/remove` does not restore Item capacity.
7. WHEN a user starts linking a brokerage that SnapTrade or Questrade supports THEN the app SHALL offer that connector first, so that Plaid Items stay reserved for banks and cards.
8. The app SHALL NOT depend on a single aggregator. It SHALL add the MX Platform API as a second aggregator, through the provider framework Sure already uses, and SHALL record each connection's provider (P4).
9. WHERE an aggregator has no production contract, the app SHALL keep it in that aggregator's development environment and SHALL NOT offer it to members (P4).

### Requirement 3: Connection health (P0)

**User Story:** As the household's admin, I want to know before a connection breaks and how to fix it, so that syncing never silently stops.

#### Acceptance Criteria

1. The app SHALL call Plaid `/item/get` for every Item at least daily. It SHALL store `error`, `error.error_code_reason`, `consent_expiration_time` and `update_type`.
2. WHEN an Item's consent expires within 14 days THEN the app SHALL notify family admins and offer an update-mode reconnect. For US and Canadian Items the expiry comes from `consent_expiration_time` in `/item/get`, or from a `PENDING_DISCONNECT` webhook whose reason is `INSTITUTION_TOKEN_EXPIRATION`; Plaid sends `PENDING_EXPIRATION` only for UK and EU Items.
3. WHEN an Item reports `ITEM_LOGIN_REQUIRED` THEN the app SHALL mark it as needing update (existing) and SHALL show a reconnect action on web and mobile.
4. WHERE the Plaid webhook endpoint is enabled, WHEN a `PENDING_DISCONNECT` webhook arrives THEN the app SHALL store its `reason` and `disconnect_time` and SHALL notify family admins. A reason of `INSTITUTION_TOKEN_EXPIRATION` SHALL also set the consent expiry (criterion 2).
5. WHERE the webhook endpoint is enabled:
   - WHEN `NEW_ACCOUNTS_AVAILABLE` arrives THEN the app SHALL offer update mode with account selection.
   - WHEN `LOGIN_REPAIRED` arrives THEN the app SHALL clear the reconnect prompt.
6. WHEN `USER_PERMISSION_REVOKED` or `USER_ACCOUNT_REVOKED` arrives THEN the app SHALL stop syncing the affected Item or account. It SHALL ask the user whether to delete the data synced from it.
7. The app SHALL verify each Plaid webhook's signature before acting on it (existing `validate_webhook!`). It SHALL return HTTP 200 for verified webhooks it does not handle.
8. The app SHALL show a connections page that lists every connection across providers. Each row SHALL show status, last successful sync and the next action required.

### Requirement 4: Multi-currency (P0)

**User Story:** As a household with USD and CAD accounts, I want every total in one currency at the rate that applied on the day, so that net worth and budgets are correct.

#### Acceptance Criteria

1. Every account SHALL have a native currency. Its balances, transactions, holdings and valuations SHALL be stored in that currency (existing).
2. Every family SHALL have one base currency, used for net worth, budgets, goals and reports (existing).
3. WHEN the app converts an amount THEN it SHALL use the rate for that amount's own date, not today's rate (existing `Money#exchange_to(date:)`).
4. WHEN either currency in a pair is CAD THEN the app SHALL take the rate from Bank of Canada Valet. Otherwise it SHALL use Frankfurter.
5. IF no rate is published for the date THEN the app SHALL use the most recent earlier rate, at most 7 days old. It SHALL mark the converted amount as carried forward.
6. IF no rate exists within 7 days THEN the app SHALL exclude the amount from base-currency totals and show a missing-rate warning. It SHALL NOT substitute a rate of 1.
7. WHEN a user sets a custom rate on a transaction THEN the app SHALL use it for that transaction instead of provider rates (existing `custom_rate:`).
8. Wherever the native and base currencies differ, the app SHALL show both amounts. On request it SHALL show the rate's source and date.
9. WHEN two transactions in different currencies form a transfer between the family's own accounts THEN the app SHALL match them as one transfer. It SHALL record the implied rate and its difference from the reference rate, in basis points.
10. The app SHALL show net worth in base currency with a breakdown by currency.

### Requirement 5: Accounts and investments (existing, P0 configuration)

**User Story:** As an investor with US and Canadian registered accounts, I want every account type and its tax treatment represented, so that net worth and allocation are complete.

#### Acceptance Criteria

1. The app SHALL support these account types (existing): depository, credit card, loan, investment, crypto, property, vehicle, other asset and other liability.
2. Investment accounts SHALL carry a subtype and tax treatment (existing `Investment::SUBTYPES`).
   - US: brokerage, 401(k), Roth 401(k), 403(b), 457(b), TSP, IRA, Roth IRA, SEP, SIMPLE, 529, HSA and UGMA/UTMA.
   - Canada: TFSA, RRSP, FHSA, RESP, RDSP, LIRA, RRIF, LIF, DPSP, PRPP, the other locked-in types, and non-registered.
3. The app SHALL track holdings, trades, cost basis and investment performance (existing).
4. The app SHALL price TSX and TSXV listings through a provider that supports them: Alpha Vantage (`.TRT` and `.TRV` suffixes) or EODHD (`TO` and `V`). Each such security SHALL be assigned to one provider, with no automatic fallback to another. Yahoo Finance SHALL serve US listings and suffixed Canadian tickers only.
5. WHEN a price is unavailable THEN the app SHALL show the last known price with its observation date, not zero.
6. The app SHALL keep property, vehicle and crypto valuation (existing: RentCast, Realie, and the exchange and on-chain connectors).

### Requirement 6: Transactions

**User Story:** As a household member, I want transactions cleaned up, categorized and reviewable, so that reports and budgets are accurate.

#### Acceptance Criteria

1. The app SHALL provide (existing):
   - search and filters;
   - categories, tags and merchants;
   - notes;
   - splits;
   - attachments, up to 10 per transaction;
   - rules, including AI rules;
   - automatic categorization.
2. The app SHALL detect and match transfers between the family's accounts (existing).
3. The app SHALL let the user review fuzzy-matched pending/posted pairs (existing).
4. WHEN Plaid returns a transaction THEN the app SHALL store its `merchant_category_code`, its `personal_finance_category` (primary, detailed and confidence level, with the taxonomy version requested) and its `authorized_date` (P0).
5. WHEN criterion 4 first ships THEN the app SHALL backfill those fields for each Item's available history (P0).
6. WHEN a pending transaction posts THEN the user's edits to it SHALL carry over to the posted transaction: category, notes, tags, splits and merchant (P3, Monarch).
7. WHERE review mode is enabled:
   - new transactions SHALL wait in a review queue until marked reviewed;
   - the app SHALL remind the user about unreviewed transactions weekly.

   (P3, Monarch.)
8. WHEN a user attaches a receipt image THEN the app SHALL extract merchant, date and total and offer to fill in the transaction (P3, Monarch).
9. The app SHALL accept receipts forwarded by email and attach them to the matching transaction (P3, Monarch). Sure has no inbound mail path: Action Mailbox is loaded but not installed.

### Requirement 7: Budgets

**User Story:** As a household, I want budgets that match how we actually spend, so that we can plan each month.

#### Acceptance Criteria

1. The app SHALL support monthly category budgets for the household and for individual members, with rollover per category (existing `Budget::RolloverCalculator`).
2. Budget amounts SHALL be in base currency. Spending in other currencies SHALL count at the rate for the transaction date.
3. The app SHALL support flex budgeting (P3; Monarch, not re-verified this pass; absent from Sure):
   - each category is grouped as fixed, flexible or non-monthly;
   - the flexible categories share a single pool.
4. The app SHALL let members share budgets (existing `budget_share`).

### Requirement 8: Recurring transactions and bills (existing)

**User Story:** As a household, I want every recurring bill and subscription in one place, so that nothing is paid late or forgotten.

#### Acceptance Criteria

1. The app SHALL detect recurring income and expenses and show them as a list and a calendar (existing).
2. The app SHALL provide the bills workspace: overview, all bills, calendar and paycheck plan, with overdue, due, partial and paid states (existing `BillsController`). Sure gates Bills behind preview features, which each member turns on for themselves, so every member who uses Bills SHALL enable them.
3. The app SHALL publish a token-authenticated iCal feed of upcoming bills. The feed SHALL carry no balances or account data (existing `BillsFeedsController`).
4. The app SHALL surface a subscription audit (existing insight generator).

### Requirement 9: Card and loan statement sync (P0 for US; Canada best-effort)

**User Story:** As a card holder, I want the statement balance, minimum due and due date pulled automatically, so that I never miss a payment.

#### Acceptance Criteria

1. WHEN Plaid Liabilities returns a credit account THEN the app SHALL store:
   - `next_payment_due_date`;
   - `minimum_payment_amount`;
   - `last_statement_balance` and `last_statement_issue_date`;
   - `last_payment_amount` and `last_payment_date`;
   - `is_overdue`;
   - every entry of `aprs`, with its `apr_type`.
2. The account's headline APR SHALL be the entry whose `apr_type` is `purchase_apr`. IF no such entry exists THEN the headline APR SHALL be empty. It SHALL NOT fall back to `aprs[0]`, because Plaid's own sample response lists `balance_transfer_apr` first.
3. WHEN a card's due date is known THEN the app SHALL create or update that card's bill occurrence with the due date and the minimum and statement amounts. The bill SHALL be paid from a funding account: the one already on the card's bill, else the source of the card's latest transfer, else one the member chooses. IF none is known THEN the app SHALL record the statement and ask the member.
4. WHEN payments to the card posted after the statement date reach the statement balance THEN the app SHALL mark the occurrence paid. WHEN they reach only the minimum THEN it SHALL mark the occurrence partial.
5. IF the institution does not provide a field THEN the app SHALL show "not provided by the institution", not zero. Plaid documents limited Canadian Liabilities coverage.
6. The app SHALL let the user enter a due date and statement balance manually for any card or loan without Liabilities data.
7. The app SHALL apply criteria 1 and 3-6 to the equivalent fields of mortgage and student loan Liabilities, where Plaid returns them.

### Requirement 10: Net worth, dashboard and reports

**User Story:** As a household, I want to see where the money goes and how net worth moves, so that we can make decisions.

#### Acceptance Criteria

1. The app SHALL provide (existing):
   - net worth over time;
   - a balance sheet;
   - a customizable dashboard;
   - cash flow, including a Sankey view;
   - an income statement;
   - spending by category;
   - printable reports;
   - CSV export.
2. The app SHALL let the user save a report configuration (filters, grouping and date range) under a name and reopen it later (P3, Monarch).
3. The app SHALL provide a treemap of spending with drill-down from category to transactions (P3; Monarch; absent from Sure).
4. The app SHALL produce a weekly recap, on the dashboard and by email (P3, Monarch). It SHALL cover spending against budget, notable transactions and the change in net worth.

### Requirement 11: Goals and forecasting

**User Story:** As a household saving for goals and retirement, I want goals tracked and my trajectory projected, so that I know whether we are on track.

#### Acceptance Criteria

1. The app SHALL support goals funded by allocations from one or more accounts, with pledges and progress (existing `goal`, `goal_account` and `goal_pledge`).
2. The app SHALL project net worth forward from recurring income and expenses, planned contributions and return assumptions set by the user (P3, Monarch Plus).
3. The app SHALL let the user compare scenarios that change those inputs (P3, Monarch Plus).
4. WHEN a scenario withdraws from a US 401(k) or IRA before age 59 and a half THEN the projection SHALL apply the early-withdrawal penalty (P3, Monarch Plus).

### Requirement 12: Equity compensation (P3, candidate to pull forward)

**User Story:** As an employee with RSUs, I want grants and vesting tracked, so that net worth reflects my shares and I can see upcoming vests.

#### Acceptance Criteria

1. The app SHALL record equity grants (RSU, ISO, NSO and ESPP). Each grant SHALL have a grant date, a share count and a vesting schedule, plus a strike price where applicable.
2. The app SHALL value vested and unvested shares at the latest price, converted to base currency.
3. Net worth SHALL include vested shares and SHALL show unvested value separately.
4. WHEN a vest date passes THEN the app SHALL record the vest, using that date's price as its cost basis.
5. WHEN vested shares are deposited into a linked brokerage account THEN the user SHALL be able to mark the vest as transferred, so that the shares are counted once.
6. The app SHALL list upcoming vests.

### Requirement 13: Rupee, the AI agent (AI native)

**User Story:** As a household member, I want an agent named Rupee that answers questions about our finances, acts on my behalf when I confirm, and tells me what needs attention, so that I notice problems early.

#### Acceptance Criteria

1. The app SHALL keep the AI assistant (chat with tool calls), AI rules and the MCP server (existing), with the assistant named Rupee.
2. The app SHALL keep the automatic insights (existing): budget, cash-flow warning, idle cash, goal depletion, net-worth milestone, savings-rate change, spending anomaly and subscription audit.
3. An admin SHALL be able to turn AI off for the whole family, and it SHALL stay off until an admin consents (criterion 8). While it is off, no family data SHALL reach an LLM provider by any path: chat, insights, categorization, merchant detection, PDF and document import, vector-store uploads or the MCP server. Guests SHALL get AI only when an admin allows it. Sure's per-member `ai_enabled` flag does not cover categorization, merchant detection or imports (`design.md` finding 9).
4. The assistant SHALL answer "which card should I use at X" and "which credits expire soon" through tools backed by Requirements 18 and 19 (P1).
5. Rupee SHALL be reachable from every page on the web and from its own tab on mobile (P2), and the product name SHALL appear in its prompts instead of "Sure" (P0).
6. WHEN Rupee proposes a change (create, update or delete) in web or mobile chat THEN the change SHALL apply only after the member confirms it (P1).
7. Rupee SHALL give each member a daily briefing of what needs attention: bills due, credits expiring, connection problems and excluded amounts. With AI off, a template SHALL write it (P1).
8. At onboarding an admin SHALL choose Rupee's model provider, including a self-hosted OpenAI-compatible model, SHALL see which data Rupee sends, and SHALL consent before any household data leaves the host (P0).

### Requirement 14: Household sharing and collaboration

**User Story:** As a couple, I want shared and personal views of our money, so that each of us sees what we should.

#### Acceptance Criteria

1. The app SHALL support multiple members per family, invitations, per-account sharing and ownership, and shared budgets (existing).
2. The app SHALL let an admin invite an outside person, such as a partner or financial professional, with read-only access limited to chosen accounts (P3). This approximates Monarch's advisor collaboration, without an advisor marketplace.

### Requirement 15: Notifications

**User Story:** As a household member, I want timely reminders on the channel I choose, so that I act before a deadline.

#### Acceptance Criteria

1. The app SHALL deliver notifications in-app, by email, and by push to registered mobile devices. Sure's push works only on iOS in managed mode, and browser push is not planned.
2. The app SHALL notify about:
   - connection problems (Requirement 3);
   - bills due (Requirements 8 and 9);
   - credits nearing the end of their period (Requirement 18);
   - SUB deadlines, annual fees and rotating-category activation (Requirement 20);
   - the weekly recap (Requirement 10).
3. Each member SHALL be able to turn each notification type on or off per channel.
4. The app SHALL batch card-benefit reminders into at most one digest per member per day.
5. The app SHALL send any given reminder at most once. A reminder is identified by its type, subject, period and lead time.

### Requirement 16: Credit score (P3, approximation only)

**User Story:** As a household member, I want to track my credit scores over time, so that I notice changes.

#### Acceptance Criteria

1. The app SHALL let a member record credit scores with bureau, scoring model and date, and SHALL chart them over time.
2. The app SHALL NOT pull scores automatically. No bureau or aggregator integration is in scope (`design.md` §9).

### Requirement 17: Card catalog and card instances (P1)

**User Story:** As a holder of US and Canadian cards, I want the app to know each card's earn rates, credits and protections, so that it can tell me when and where to use each card.

#### Acceptance Criteria

1. The app SHALL maintain a catalog of US and Canadian card products. Each product SHALL record:
   - issuer, network and country;
   - billing currency;
   - annual fee and foreign transaction fee;
   - rewards program;
   - earn rules, credits, benefits and protections;
   - source URLs and a `verified_on` date.
2. Each earn rule SHALL match on one of: a merchant list, an MCC set, an issuer category, or all purchases. A rule MAY have a cap per period and a rate that applies after the cap.
3. Catalog entries SHALL be versioned by `effective_from`. WHEN a product's terms change THEN periods that have already closed SHALL keep the terms that applied to them.
4. IF an entry's `verified_on` is more than 180 days old THEN the app SHALL mark it stale wherever the entry is shown.
5. The catalog SHALL be data files in the repository. A sync task SHALL validate them and load them into the database all or nothing.
6. WHEN a member adds a card THEN the app SHALL link a catalog product, or a custom product, to a credit card account. It SHALL record the open date, which anchors cardmember-year credits and the annual fee date.
7. A member SHALL be able to override an earn rule, credit or fee for their own card without changing the catalog.
8. Each catalog entry SHALL cite the issuer's own pages. Entries SHALL NOT be copied from third-party compilations whose license does not allow it.

### Requirement 18: Card credits (P1)

**User Story:** As a card holder, I want to see which credits I haven't used and be reminded before they lapse, so that I don't lose value I pay an annual fee for.

#### Acceptance Criteria

1. For each credit on a member's card, the app SHALL compute the current period from the credit's cadence and reset basis. The period is one of: a calendar month, quarter, half-year or year; a cardmember year from the open date; or a multi-year window.
2. WHEN a credit requires enrollment and the member has not marked it enrolled THEN the app SHALL show it as "not enrolled" and SHALL NOT count it as available value.
3. WHEN a transaction on the card matches a credit's qualifying rule THEN the app SHALL record it as usage in the period that contains the transaction date. Usage SHALL be capped at the credit amount.
4. WHEN a statement credit posts that matches the credit's posting pattern THEN the app SHALL record it as received.
5. WHEN a qualifying purchase is refunded THEN the app SHALL reverse its usage.
6. IF a match's confidence is below the threshold THEN the app SHALL ask the member to confirm it rather than apply it.
7. The app SHALL show, for each card and credit, the amount, used, received, remaining and days left in the period.
8. WHEN a credit has value remaining and its period ends within the lead time THEN the app SHALL remind the member. The lead time SHALL default to 7 days and SHALL be configurable.
9. A member SHALL be able to record usage manually and to reject a wrong match.
10. A period SHALL end at the end of its last day in the family's time zone. A cardmember year that starts on 29 February SHALL start on 28 February in non-leap years.

### Requirement 19: Which card to use (P1)

**User Story:** As a card holder, I want to know which card to use for a purchase, so that I get the best return without memorizing earn charts.

#### Acceptance Criteria

1. WHEN a member asks about a merchant or category, optionally with an amount and currency, THEN the app SHALL rank the family's cards by estimated value. It SHALL give the reason for each card: the rule matched, cap remaining, FX fee and any credit available.
2. Estimated value SHALL be computed as follows, with the result converted to base currency:
   1. Start with amount x applicable multiplier x point value.
   2. Subtract the foreign transaction fee WHEN the purchase currency differs from the card's billing currency.
   3. Add any unused credit that applies.
3. The ranking SHALL respect the cap remaining in the current cap period. Once a cap is used up, it SHALL use the after-cap rate.
4. The app SHALL resolve a merchant's category in this order:
   1. the member's override;
   2. an earn rule's merchant list;
   3. MCC;
   4. the issuer's category map;
   5. PFC;
   6. the app category.
5. Point values SHALL have a default per program, in the program's currency, and SHALL be editable per family.
6. WHEN a rotating category requires activation THEN the app SHALL remind members at the start of each period until they mark it activated.
7. The ranking SHALL be available on the web, on mobile (P2), and to the AI assistant.

### Requirement 20: Welcome offers, fees and card value (P1)

**User Story:** As a card holder, I want welcome offers, fees and each card's real value tracked, so that I can decide whether to keep, downgrade or cancel a card.

#### Acceptance Criteria

1. The app SHALL track each welcome offer's spend requirement, deadline and progress, and SHALL remind the member before the deadline. Progress SHALL count purchases only: it SHALL exclude fees, interest, cash advances and balance transfers, and SHALL net out refunds.
2. The app SHALL detect annual fee postings and SHALL remind the member before the next expected fee. It SHALL use Plaid's `transaction_code` value `membership fee` where available, and a descriptor pattern otherwise.
3. The app SHALL compute each card's value per cardmember year: credits received plus estimated rewards, minus the annual fee.
4. The app SHALL produce a missed-value report. It SHALL list credits that expired unused, and purchases where another of the family's cards would have earned more than the card used, by more than a threshold.
5. The app SHALL let members record rewards balances per program, with an optional expiry date, and SHALL remind them before expiry.

### Requirement 21: Security, privacy and backups (P0)

**User Story:** As the operator, I want financial data and credentials protected and recoverable, so that a breach or disk failure is not a disaster.

#### Acceptance Criteria

1. Provider credentials SHALL be encrypted at rest (existing for Plaid: `encrypts :access_token`). The Active Record encryption keys SHALL be supplied as secrets, SHALL never be committed, and SHALL be backed up separately from the database. The app SHALL refuse to start in production without them, because Sure otherwise stores provider tokens unencrypted (`design.md` finding 23).
2. The app SHALL support MFA, passkeys and OIDC SSO (existing).
3. All traffic SHALL use TLS. WHERE the app is reachable only on a private network, the only public routes SHALL be the Plaid webhook and, if enabled, the iCal feed. Files for mobile universal links, if used, SHALL be served from a separate static host.
4. The app SHALL back up the database and uploaded files daily to encrypted off-host storage. A restore SHALL be tested before real accounts are linked, and quarterly after that.
5. Logs SHALL NOT contain access tokens, secrets or full account numbers.
6. A member SHALL be able to export all family data and to delete it (existing).
7. All household data at rest SHALL be encrypted: volume encryption for the database and uploaded files, and application-level encryption for credentials, tokens, raw provider payloads and personal identifiers.
8. Connections to the database SHALL use TLS unless the database runs on the same host.
9. The encryption keys SHALL have a documented rotation procedure, rehearsed on a restored copy before real accounts are linked.

### Requirement 22: Deployment, upstream tracking and licensing (P0)

**User Story:** As the operator, I want the app easy to run, current with upstream, and license-compliant, so that maintenance stays small and legal risk stays low.

#### Acceptance Criteria

1. The app SHALL deploy with Docker, following Sure's hosting guide.
2. The codebase SHALL be a fork of Sure that merges upstream at least monthly. New code SHALL live in its own namespaces, with minimal edits to upstream files.
3. Changes that are not specific to this fork SHALL be offered upstream. These include MCC and PFC persistence, the Liabilities mapping, the `apr_type` fix, the exchange-rate guards and the Bank of Canada provider. `design.md` §4.1 marks each upstream edit.
4. The app SHALL keep the AGPLv3 license. It SHALL state that it is based on Maybe Finance and Sure, and that it is not affiliated with or endorsed by Maybe Finance Inc. It SHALL NOT use the Maybe name or logo.
5. WHERE people other than the operator use the app over a network, the app SHALL offer them the complete corresponding source of the running version (AGPLv3 section 13).
6. WHERE the app is operated commercially, it SHALL use a paid Plaid plan. Plaid describes the Trial plan as suited to hobbyist use.
7. The repository is public. It SHALL contain no secrets, credentials or household financial data, and CI SHALL scan every push for secrets.

### Requirement 23: Imports and exports (existing)

**User Story:** As someone moving from another tool, I want my history imported, and I want to be able to take my data out, so that I'm not locked in.

#### Acceptance Criteria

1. The app SHALL import CSV, QIF, PDF statements, trades and rules, and exports from Mint, YNAB, Actual and Sure (existing).
2. The app SHALL export all family data. It SHALL also export transactions as CSV, including for spreadsheet pulls authenticated by an API key (existing).

## Out of Scope

- **Card-linked offer automation** (Amex Offers and similar). No public API exists; competitors use browser extensions or credential scraping.
- **Loyalty-account scraping.** Rewards balances are entered by hand (Requirement 20.5).
- **Automatic credit-score pulls** (Requirement 16.2).
- **Canadian bill sync beyond Plaid Liabilities.** The only other sources found are enterprise partnerships. Revisit when Canada's consumer-driven banking regulations are finalized, expected late 2026 or early 2027.
- **An advisor marketplace.**
- **Monarch's roadmap voting.** It is a product process, not a feature.
- **Ideas found in none of the three products.** Recorded, not planned: TFSA/RRSP/FHSA contribution-room tracking, and cross-border tax reporting.
