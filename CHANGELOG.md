# Changelog

## Unreleased

- Add `unload_deferred`, to forget deferred columns in records created in tests, so they behave like records loaded by a query.

## 0.0.3 (2026-11-18)

- Fix `NoMethodError` for the private `construct_join_dependency` when merging joins of another model, or in association scopes that reference an eager loaded association.

## 0.0.2 (2026-11-18)

- Rename `select_all_columns` to `with_deferred_columns`.
- Add named groups of deferred columns, with `defer_columns ..., as: :name`.
- Add `load_deferred`, to load deferred columns into a record that was loaded without them.
- Add `DeferredColumns.load`, to load deferred columns into many records with one query per model.
- Raise `NotLoadedError` from `read_attribute` and `[]` too, instead of returning `nil`.
- Keep the deferred columns a record had loaded when calling `reload`.
- Respect opt-ins in `eager_load`, and in `includes` when it eager loads, both in the query and in association scopes.
- Add `DeferredColumns.on_not_loaded`, to report a missing deferred column instead of raising, and load it with an extra query.
- Detect associations that were already loaded without the deferred columns that a preload scope opts into.
- Load deferred columns in `DeferredColumns.load` and `load_deferred` without instantiating a record per row.

## 0.0.1 (2026-11-17)

- Initial release: `defer_columns`, `with_deferred`, `select_all_columns`, and `DeferredColumns::NotLoadedError`.
- Supports Active Record 7.2, 8.0, 8.1 and main.
