---
name: typescript-react-conventions
description: TypeScript and React conventions for a React Router 7 + Tailwind + Vite pnpm monorepo. Use when writing, reviewing or debugging TypeScript, React components, hooks, loaders/actions, or frontend build config.
---

# TypeScript / React conventions

Stack: React Router 7, Tailwind, Vite 6, pnpm workspaces; a TypeScript-dominant frontend monorepo.

## TypeScript

- `strict` stays on. A new `any` needs a comment naming what is unknown and why.
- Prefer `unknown` + a narrowing check over `any` at every boundary that parses external data.
- `as` is an assertion, not a conversion - it silences the compiler without changing the value.
  Parse and validate instead (zod or a hand-written guard) at API and storage boundaries.
- Discriminated unions over optional-field soup; make illegal states unrepresentable.
- Export types alongside the values they describe; avoid a central `types.ts` dumping ground.
- `satisfies` when you want inference preserved and the shape checked.

## Money and numbers

- Money is integer cents end to end. Never a float, never a string that gets `parseFloat`ed.
- Any percentage or proportion applied to money rounds explicitly (`Math.round`) at the point of
  application - a fractional cent will surface later as an off-by-one in a total.

## React

- Function components and hooks only. No class components in new code.
- Derive during render rather than mirroring props into state; `useEffect` that only syncs state to
  other state is a bug in the data flow.
- `useEffect` needs a complete dependency array and a cleanup function for anything subscribing.
- Keys are stable ids, never array indices, for any list that can reorder or splice.
- Colocate a component with its own hooks/helpers; lift out only at the third consumer.

## React Router 7

- Data loading belongs in loaders, mutations in actions - not in `useEffect`.
- Loaders run on navigation: keep them cheap and parallel; do not chain awaits that could run
  together.
- Handle the pending and error states explicitly; a route without an error boundary fails blank.

## Build and repo

- pnpm workspaces: add a dependency to the package that uses it, not the root.
- `tsc --noEmit` is the type gate; a passing Vite build does not type-check.
- Path aliases come from `tsconfig.json`, mirrored in Vite config - change both or neither.
- Run the typecheck and the tests before claiming done; a green dev server proves neither.
