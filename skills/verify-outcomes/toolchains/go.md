# Go Toolchain

## Lint

```bash
golangci-lint run
```

- If `.golangci.yml` / `.golangci.yaml` exists, it auto-reads project config.
- Do NOT fall back to `go vet` alone — `golangci-lint` includes `go vet` plus many more linters.
- Auto-fix (where supported): `golangci-lint run --fix`

## Format

```bash
gofmt -w .
```

- Or use `goimports -w .` if import ordering matters (preferred when available).
- Check only (no write): `gofmt -l .` (lists unformatted files)

## Type / Static Check

```bash
go vet ./...
```

- This is included in `golangci-lint run`, so if you already ran lint, you can skip this step.
- Build check: `go build ./...` (ensures compilation without producing binary)

## Test

```bash
go test ./...
```

- Specific package: `go test ./path/to/package`
- Verbose: `go test -v ./...`
- Coverage: `go test -coverprofile=coverage.out ./...` then `go tool cover -func=coverage.out`
- Race detection: `go test -race ./...` (use for thorough depth)
- Short mode (skip slow tests): `go test -short ./...`

## Build

```bash
go build ./...
```

- For specific binary: `go build -o <output> ./cmd/<name>`

## Dev Server

Go services typically run on port 8080.

Check before starting:
```bash
lsof -i :8080 | grep LISTEN
```

Most Go web servers do NOT have built-in hot reload. If the project uses `air` or `gow`:
```bash
air
# or
gow run .
```

Otherwise, must manually restart after changes.

## Module Management

- Never edit `go.mod` or `go.sum` directly.
- Add dependency: `go get <module>@<version>`
- Tidy: `go mod tidy`
- Update: `go get -u <module>`
