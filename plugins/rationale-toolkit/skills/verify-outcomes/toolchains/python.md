# Python Toolchain

## Lint

```bash
ruff check .
```

- Auto-fix: `ruff check --fix .`
- Do NOT use `python -m ruff` unless `ruff` is not on PATH.

## Format

```bash
ruff format .
```

- Check only (no write): `ruff format --check .`

## Type Check

Detect from project config:

| Indicator | Tool | Command |
|-----------|------|---------|
| `pyrightconfig.json` or pyright in dev deps | pyright | `pyright` |
| `mypy.ini` or `[mypy]` in setup.cfg | mypy | `mypy .` |
| Neither present | pyright | `pyright` (preferred default) |

## Test

```bash
pytest
```

- Specific file: `pytest <path>`
- Specific test: `pytest <path>::<test_name>`
- Coverage: `pytest --cov=<package> --cov-report=term-missing`
- Verbose: `pytest -v`

If the project uses `uv`:
```bash
uv run pytest
```

## Build

For projects with `pyproject.toml`:
```bash
python -m build
```

For uv-managed projects:
```bash
uv build
```

## Dev Server

Common frameworks and ports:
- FastAPI: 8000 (`uvicorn main:app --reload`)
- Django: 8000 (`python manage.py runserver`)
- Flask: 5000 (`flask run`)

Check before starting:
```bash
lsof -i :8000 -i :5000 | grep LISTEN
```

Hot reload: FastAPI with `--reload`, Django dev server, and Flask debug mode all support auto-reload on file save.

## Package Management

- Use `uv` if `uv.lock` is present; otherwise fall back to `pip`.
- Never edit `uv.lock`, `requirements.txt`, or `pyproject.toml` dependencies directly — use CLI:
  - `uv add <pkg>` / `uv add --dev <pkg>`
  - `pip install <pkg>` (only if not using uv)
