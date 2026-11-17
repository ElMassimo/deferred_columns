<h1 align="center">
Deferred Columns
<p align="center">
<a href="https://github.com/ElMassimo/deferred_columns/actions"><img alt="Build Status" src="https://github.com/ElMassimo/deferred_columns/workflows/build/badge.svg"/></a>
<a href="https://github.com/ElMassimo/deferred_columns/blob/main/LICENSE.txt"><img alt="License" src="https://img.shields.io/badge/license-MIT-428F7E.svg"/></a>
</p>
</h1>

[Active Record]: https://guides.rubyonrails.org/active_record_basics.html
[ignored_columns]: https://api.rubyonrails.org/classes/ActiveRecord/ModelSchema/ClassMethods.html#method-i-ignored_columns-3D
[columns_on_demand]: https://github.com/willbryant/columns_on_demand
[Issues]: https://github.com/ElMassimo/deferred_columns/issues

Leave heavy columns out of the default `SELECT` of your [Active Record] models, and load them only in the queries that need them.

```ruby
class Song < ApplicationRecord
  defer_columns :lyrics, :waveform
end
```

```ruby
Song.where(album: abraxas)
# SELECT "songs"."id", "songs"."album_id", "songs"."track", "songs"."name", "songs"."composer"
# FROM "songs" WHERE "songs"."album_id" = 1

Song.with_deferred(:lyrics).where(album: abraxas)
# SELECT "songs"."id", "songs"."album_id", "songs"."track", "songs"."name", "songs"."composer", "songs"."lyrics"
# FROM "songs" WHERE "songs"."album_id" = 1
```

```ruby
song = Song.find_by(name: "Oye como va")

song.lyrics
# DeferredColumns::NotLoadedError: Song#lyrics is a deferred column, so it isn't loaded by default.
# Select it in the query, for example: Song.with_deferred(:lyrics), or load it into the record with load_deferred(:lyrics)
```

## Why? 🤔

Active Record loads every column of a table, whether or not the code reads it.

Most tables have a few columns that are much larger than the rest, and that only one or two places need: lyrics, documents, JSON payloads, binary blobs, embeddings. Every other query still transfers them from the database, decodes them, and allocates them.

Selecting columns explicitly works for a single query, but it's easy to miss one, and it doesn't apply to associations. [`ignored_columns`][ignored_columns] removes the column from the model altogether, so there's nothing to opt into.

This library makes leaving a column out the default, and loading it an explicit choice in the query.

## Features ⚡️

- One line per model, in the spirit of [`ignored_columns`][ignored_columns]
- Opt in per query, with `with_deferred(:lyrics)` or `with_deferred_columns`
- Name groups of columns that are read together, and opt into them at once
- Applies to associations, `preload`, `includes`, `eager_load`, `joins` and single table inheritance
- Leaves calculations alone: `count`, `pluck`, `exists?` and friends work as usual
- Raises instead of running a query per record when a column wasn't loaded
- Skips validations of deferred columns that weren't loaded
- No `default_scope`, and models without deferred columns keep `SELECT *`

## Installation 💿

Add this line to your application's Gemfile:

```ruby
gem 'deferred_columns'
```

And then run:

    $ bundle install

## Usage 🚀

### Declaring deferred columns

Call `defer_columns` in any model:

```ruby
class Album < ApplicationRecord
  defer_columns :liner_notes, :cover_art
end
```

Subclasses inherit the deferred columns of their parent, and can add their own:

```ruby
class LiveRecording < Song
  defer_columns :crowd_noise
end

LiveRecording.deferred_columns # => ["lyrics", "waveform", "crowd_noise"]
```

### Grouping columns

Pass `as:` to name a group of deferred columns that are usually read together:

```ruby
class Album < ApplicationRecord
  defer_columns :liner_notes, :cover_art, as: :booklet
end
```

Queries and records can then opt into the whole group by name, which keeps call sites short and in sync when the group changes:

```ruby
Album.with_deferred(:booklet)
album.load_deferred(:booklet)
```

Groups can be mixed with column names, a column can belong to several groups, and declaring the same group again adds to it.

### Loading deferred columns

`with_deferred` adds deferred columns to the default ones, in the same query:

```ruby
Song.with_deferred(:lyrics).find_by(name: "Samba pa ti")
Song.where(track: 1..3).with_deferred(:lyrics, :waveform)
album.songs.with_deferred(:lyrics)
```

`with_deferred_columns` loads every column, including the deferred ones:

```ruby
Album.with_deferred_columns.find(id)
```

Passing a column that isn't deferred raises an `ArgumentError`, which catches typos early:

```ruby
Song.with_deferred(:lirycs)
# ArgumentError: lirycs is not a deferred column of Song
```

An explicit `select` loads exactly the columns it names, deferred or not, and takes precedence over `with_deferred`:

```ruby
Song.select(:id, :name, :lyrics)
```

### Loading into a record you already have

When a record comes from somewhere you can't add `with_deferred` to, such as a job argument or `self` in a callback, `load_deferred` loads the columns you name into it, in a single query:

```ruby
class RefreshLyricsJob < ApplicationJob
  def perform(song)
    song.load_deferred(:lyrics)
    song.update!(lyrics: LyricsService.normalize(song.lyrics))
  end
end
```

Without arguments, it loads every deferred column the record doesn't have yet. It doesn't query when the columns are already loaded, or for new records.

For several records, such as a preloaded association or an array, `DeferredColumns.load` does the same with one query per model:

```ruby
DeferredColumns.load(album.songs, :lyrics)
```

Records that already have the columns keep their values, so it only queries for what's missing. Still, prefer `with_deferred` in the query that loads the records when you can, which needs no extra query.

### Associations

Associations, `preload`, `includes` and `eager_load` all leave deferred columns out.

To load them along with an association, define an association with a scope:

```ruby
class Album < ApplicationRecord
  has_many :songs
  has_many :songs_with_lyrics, -> { with_deferred(:lyrics) }, class_name: "Song"
end

Album.preload(:songs_with_lyrics)
```

> **Note**
>
> `eager_load` builds a single query for every model involved, and always uses their default columns. Use `preload` with a scoped association instead, or select the table explicitly:
>
> ```ruby
> Song.eager_load(:album).select(Song.arel_table[Arel.star])
> ```

### Reading deferred columns

Reading a deferred column that the query didn't load raises `DeferredColumns::NotLoadedError`, without running a query:

```ruby
song = Song.first

song.lyrics                  # raises DeferredColumns::NotLoadedError
song.has_attribute?(:lyrics) # => false
song.as_json                 # leaves lyrics out
```

The error is a subclass of `ActiveModel::MissingAttributeError`, so existing rescues keep working. It also exposes `model` and `column`.

Other ways of reading attributes, such as `song[:lyrics]` and `read_attribute(:lyrics)`, behave as they do for any column a query didn't select.

New records have every column, so `Song.new.lyrics` works as usual.

You can override the reader in the model and call `super`:

```ruby
class Song < ApplicationRecord
  defer_columns :lyrics

  def lyrics
    super&.strip
  end
end
```

### Writing records

Saving a record only writes the columns that changed, so updating other columns leaves deferred columns untouched:

```ruby
song = Song.find_by(name: "El Nicoya")
song.update!(composer: "José Areas")
# UPDATE "songs" SET "composer" = 'José Areas' WHERE "songs"."id" = 9
```

Assigning a deferred column doesn't require loading it first:

```ruby
song.update!(lyrics: "Instrumental")
```

### Validations

A deferred column that wasn't loaded can't have changed, so its validations are skipped:

```ruby
class Album < ApplicationRecord
  defer_columns :liner_notes

  validates :name, :liner_notes, presence: true
end

album = Album.find_by(name: "Abraxas")
album.update!(name: "Abraxas (Remastered)")   # validates name, skips liner_notes
```

The validations run as usual when the column was loaded or assigned, and on new records.

> **Note**
>
> This applies to validators such as `presence` or `length`. A custom `validate` method that reads a deferred column should check `has_attribute?` first.

### Calculations

Calculations build their own `SELECT`, and work the same with or without `with_deferred`:

```ruby
Song.with_deferred(:lyrics).where(album: abraxas).count
# SELECT COUNT(*) FROM "songs" WHERE "songs"."album_id" = 1

Song.where(album: abraxas).pluck(:lyrics)
```

### Reloading

`reload` keeps the deferred columns the record had loaded, reading their latest values in a second query, and leaves out the rest:

```ruby
song = Song.with_deferred(:lyrics).find(id)
song.reload.lyrics # works
```

### What it doesn't do

- It doesn't load deferred columns lazily. A query per record is easy to miss and expensive in a loop, so missing columns raise instead.
- It doesn't change raw SQL, such as `find_by_sql`.
- It only changes reads. If a column is expensive to write, for example because of a large index, moving it to a separate table is still the better fit.

## How it works 🔧

When a query doesn't select any columns, Active Record either selects `*` or, for models with [`ignored_columns`][ignored_columns], lists the remaining columns. This library adds deferred columns to that same decision in `Relation#build_select`.

`eager_load` builds its `SELECT` from each model's column names instead, so the library also adjusts those.

`with_deferred` stores the requested columns as a relation extension, so they survive `merge` and association scopes, and `count` keeps counting rows.

## Compatibility

- Ruby 3.1 or newer
- Active Record 7.2, 8.0, 8.1 and `main`
- Tested on SQLite and PostgreSQL

## Running tests 🧪

```sh
bundle install
bin/rspec
```

To run the tests against a specific version of Rails, set `BUNDLE_GEMFILE` to one of the files in `gemfiles`:

```sh
BUNDLE_GEMFILE=gemfiles/Gemfile-rails.7.2.x bundle install
BUNDLE_GEMFILE=gemfiles/Gemfile-rails.7.2.x bin/rspec
```

The tests run on an in-memory SQLite database by default. To run them on PostgreSQL, set `DATABASE_URL`:

```sh
createdb deferred_columns_test
DATABASE_URL=postgres:///deferred_columns_test bin/rspec
```

## Acknowledgements 🙏

- [columns_on_demand], which first left columns out of the default `SELECT` from `Relation#build_select`

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
