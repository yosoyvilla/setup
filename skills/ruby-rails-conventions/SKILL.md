---
name: ruby-rails-conventions
description: Ruby and Rails conventions for large Rails codebases - monoliths, online platforms and API gateways. Use when writing, reviewing, testing or debugging Ruby or Rails code - models, migrations, service objects, jobs, RSpec/minitest, ActiveRecord query performance, and Rails upgrade hazards.
---

# Ruby / Rails conventions

For large Rails surfaces (tens of thousands of files across a monolith, satellite apps and an
API gateway) on Rails 8.

## Migrations — the expensive mistakes

- **A NOT NULL column with a default is not one safe step on a large table.** Add the column
  nullable, backfill in batches, then add the constraint. Rails/Postgres will otherwise hold a
  lock proportional to table size.
- **Rails drops the DB-level default after backfilling** an `add_column ... default:`. Do not rely
  on the database to enforce it afterwards.
- `helm rollback` / app rollback does NOT revert a migration. Schema and code roll back on
  different clocks; every migration must be backward-compatible with the previous release.
- Use `disable_ddl_transaction!` with `algorithm: :concurrently` for index creation on big tables,
  and never inside a transaction.
- `strong_migrations` warnings are load-bearing; silencing one needs a comment saying why.

## ActiveRecord

- N+1 is the default failure mode: `includes`/`preload`/`eager_load` deliberately, and know which
  one you are asking for (`includes` may choose either).
- `find_each`/`in_batches` for anything unbounded. A bare `.all.each` over a production table is a
  memory incident.
- `pluck` over `map(&:attr)` when you only need columns; `exists?` over `present?` on a relation.
- Scopes return relations, never arrays - a scope that calls `.to_a` breaks chaining.
- `update_all`/`delete_all` skip callbacks and validations. That is sometimes the point; say so in
  a comment when it is.

## Structure

- Fat model, skinny controller is the baseline; extract to a service object (`app/services`) once
  a model method needs more than its own state.
- Jobs are idempotent and take primitives (ids), never AR objects - the record may have changed or
  vanished by the time the job runs.
- Concerns for shared behaviour, not for organising one model's own code.

## Testing

- RSpec where present, minitest otherwise; match the file's neighbours, do not introduce a second
  framework.
- Test behaviour through public interfaces. A test that stubs the method under test proves nothing.
- `travel_to` for time, never `sleep`. Freeze time in anything touching `created_at` windows.
- Factories over fixtures; build over create unless persistence is the thing under test.

## Style

- `rubocop` is the arbiter; run it before claiming done.
- Guard clauses over nested conditionals; `&.` only where nil is genuinely expected.
- Keyword arguments for anything with more than two parameters.
- Frozen string literals at the top of new files.
