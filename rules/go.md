# Go Conventions

> Obsidian: ~/Documents/obsidian-vault/claude-code/go.md
> Applies to: Project-a Go services (Go 1.17+)

## Code Style
- `gofmt` / `go fmt` always applied — non-negotiable
- Errors wrapped with `%w` (not `%v`) so callers can `errors.Is`/`errors.As`
- Error messages lowercase, no trailing period: `"failed to connect"` not `"Failed to connect."`
- Context as first parameter on every function that does I/O or calls external services
- No global mutable state — use dependency injection

## Naming
- Exported: `PascalCase`. Unexported: `camelCase`
- Interfaces: single-method interfaces named by method + `er` (e.g., `Reader`, `Storer`)
- Avoid stutter: `user.User` → bad, `user.Profile` → good
- Test files: `_test.go` suffix, same package for white-box, `_test` package suffix for black-box

## Testing
- Table-driven tests: `[]struct{ name, input, want }` pattern
- Run with race detector in CI: `go test -race ./...`
- Benchmarks in `_test.go` with `Benchmark` prefix when performance is critical
- Use `testify/assert` or stdlib `testing` — no heavy mocking frameworks

## Linting
- `golangci-lint run ./...` — enforced in Project-a CI (GitHub Actions)
- Fix lint before pushing — CI will fail
- Key enabled linters: `errcheck`, `govet`, `staticcheck`, `revive`, `gocyclo`

## Versioning (Project-a services)
- `go.mod` version does NOT change between application releases — git tag is the version
- Build version injected via ldflags: `-ldflags "-X main.Version=vX.Y.Z"`
- Check `version.go` if present before assuming ldflags pattern

## Modules
- Dependencies pinned in `go.sum` — always commit both `go.mod` and `go.sum`
- `go mod tidy` before committing dependency changes
- Prefer stdlib over third-party for simple tasks

## Troubleshooting
```bash
go test -race ./...              # catch race conditions
go vet ./...                     # static analysis
golangci-lint run ./...          # full lint suite
go build ./...                   # confirm it compiles
GOTRACEBACK=all go test -run TestName  # verbose panic output
```
