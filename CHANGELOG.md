# Changelog

## 0.0.2 (2026-11-17)

- Rename `select_all_columns` to `with_deferred_columns`.
- Add `load_deferred`, to load deferred columns into a record that was loaded without them.
- Keep the deferred columns a record had loaded when calling `reload`.

## 0.0.1 (2026-11-17)

- Initial release: `defer_columns`, `with_deferred`, `select_all_columns`, and `DeferredColumns::NotLoadedError`.
- Supports Active Record 7.2, 8.0, 8.1 and main.
