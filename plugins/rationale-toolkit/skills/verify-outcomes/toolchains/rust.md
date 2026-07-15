# Rust Toolchain

## Lint

```bash
cargo clippy -- -D warnings
```

- `-D warnings` treats all warnings as errors — prevents "it's just a warning" drift.
- Auto-fix: `cargo clippy --fix`
- If the project uses a workspace, this runs across all crates by default.

## Format

```bash
cargo fmt
```

- Check only (no write): `cargo fmt -- --check`

## Type / Static Check

```bash
cargo check
```

- Faster than `cargo build` — type checks without producing binary.
- For all targets (tests, benches, examples): `cargo check --all-targets`

## Test

```bash
cargo test
```

- Specific test: `cargo test <test_name>`
- Specific module: `cargo test --lib <module>::`
- Show output: `cargo test -- --nocapture`
- Doc tests only: `cargo test --doc`
- Ignored tests (marked `#[ignore]`): `cargo test -- --ignored`

## Build

```bash
cargo build
```

- Release build: `cargo build --release`
- Check compilation without full build: `cargo check` (preferred for verification)

## Dev Server

Rust web services typically use ports 3000 (Axum), 8000 (Rocket), or 8080 (Actix).

Check before starting:
```bash
lsof -i :3000 -i :8000 -i :8080 | grep LISTEN
```

Rust does NOT have built-in hot reload. If the project uses `cargo-watch`:
```bash
cargo watch -x run
```

Otherwise, must manually `cargo run` after changes.

## Dependency Management

- Never edit `Cargo.toml` dependencies section or `Cargo.lock` directly.
- Add dependency: `cargo add <crate>`
- Add dev dependency: `cargo add --dev <crate>`
- Remove: `cargo remove <crate>`
- Update: `cargo update`
