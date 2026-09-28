---
name: php-conventions
description: PHP conventions for legacy PHP 7.4 web applications deployed through CI to Kubernetes. Use when writing, reviewing or debugging PHP where the runtime is pinned below 8.0 and the application is public-facing.
---

# PHP conventions

These apply to PHP **7.4** services. Local tooling is often newer - target 7.4 syntax and
semantics unless a repository's own `composer.json` says otherwise.

## Language level — 7.4, not 8.x

Available: typed properties, arrow functions (`fn()`), null coalescing assignment (`??=`),
spread in arrays. **Not** available: named arguments, constructor property promotion, `match`,
nullsafe `?->`, enums, `readonly`, union types in signatures. Any of those breaks production even
when it runs locally on a newer interpreter.

## Types and safety

- `declare(strict_types=1);` at the top of new files.
- Type every parameter and return that 7.4 allows; document the rest in docblocks so static
  analysis still sees them.
- `==` is a trap with mixed types. Use `===` unless loose comparison is deliberate and commented.
- Never interpolate into SQL. Prepared statements with bound parameters, always.
- Escape on output, not input: `htmlspecialchars($v, ENT_QUOTES, 'UTF-8')`.

## Money and filters

- Money is integer minor units, even for currencies with no practical decimal. Format only at the
  presentation layer, with thousands separators and two decimals.
- Range filters are inclusive of their bounds unless a product rule says otherwise. An exclusive
  `<` on a maximum silently hides records priced exactly at the user's limit.

## Structure

- PSR-12 formatting, PSR-4 autoloading; follow the repository's existing namespace layout.
- Thin controllers, business logic in services, data access behind repositories.
- No logic in templates beyond looping and escaping.

## Errors and logging

- Throw typed exceptions; do not return `false` from something that could explain itself.
- **Log the reason on a 4xx rejection.** A validation refusal whose reason never reaches a log is
  the most expensive class of support ticket on a public-facing application.
- Never log full request bodies for authenticated users; redact identifiers.

## Verification

- Run the repository's own linter and static analysis before claiming done.
- A change that passes locally but fails in CI is not done.
