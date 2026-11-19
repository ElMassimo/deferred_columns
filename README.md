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

Leave large columns out of [Active Record] queries by default.

```ruby
class Song < ApplicationRecord
  defer_columns :lyrics, :waveform
end

album.songs                        # no lyrics or waveform
album.songs.with_deferred(:lyrics) # includes lyrics in the same query
```

## Why? 🤔

An album page only needs a track list, but by default `album.songs` fetches the lyrics and waveform for every song.

You could use `select`, but then every query that loads songs needs a list of columns to keep.
[`ignored_columns`][ignored_columns] goes too far: you still want the lyrics on the song page.

With `defer_columns`, only the query for the song page needs to change.
If you forget to select the lyrics, `song.lyrics` raises rather than quietly running another query.

## Installation 💿

Add this line to your application's Gemfile:

```ruby
gem 'deferred_columns'
```

And then run:

    $ bundle install

## Usage 🚀

### Loading deferred columns

Use `with_deferred` to add one or more columns to the ones you'd normally get:

```ruby
Song.with_deferred(:lyrics).find_by(name: "Oye como va")
album.songs.with_deferred(:lyrics, :waveform)
Song.with_deferred_columns.find(id) # all columns
```

An unknown column or group raises `ArgumentError`. If you use `select`, Active Record
loads exactly the columns you name, even on a relation with `with_deferred`.

Subclasses inherit their parent's deferred columns and can add their own:

```ruby
class LiveRecording < Song
  defer_columns :crowd_noise
end

LiveRecording.deferred_columns # => ["lyrics", "waveform", "crowd_noise"]
```

### Grouping columns

If you usually read a few columns together, give them a name:

```ruby
class Album < ApplicationRecord
  defer_columns :liner_notes, :cover_art, as: :booklet
end

Album.with_deferred(:booklet)
```

You can mix group and column names in a query. A column can belong to more
than one group, and declaring a group again adds to it.

### Associations

`Album.includes(:songs)` leaves out the lyrics, just like `album.songs`.
To preload the lyrics too, use an association scope:

```ruby
class Album < ApplicationRecord
  has_many :songs
  has_many :songs_with_lyrics, -> { with_deferred(:lyrics) }, class_name: "Song"
end

Album.includes(:songs_with_lyrics)
```

The same scope works with `preload`, `eager_load`, and `has_many :through`.
In `Song.with_deferred(:lyrics).eager_load(:album)`, only the songs get the extra column.

### Loading into a record you already have

A job might receive a song without its lyrics. Use `load_deferred` to fetch them
without replacing the record:

```ruby
class RefreshLyricsJob < ApplicationJob
  def perform(song)
    song.load_deferred(:lyrics)
    song.update!(lyrics: LyricsService.normalize(song.lyrics))
  end
end
```

Without arguments, `load_deferred` fetches all missing deferred columns.
It skips the query for new records or when the columns are already loaded.

For a collection, load the missing columns with one query per model instead of one per record:

```ruby
DeferredColumns.load(album.songs, :lyrics)
```

Both forms accept group names and leave values you've already loaded or assigned alone.

### Testing

A record created in a test keeps every column in memory, so a test passes even
when the code under test reads a deferred column that production never loads.
Use `unload_deferred` to forget them, as if the record had been loaded by a query:

```ruby
FactoryBot.define do
  factory :song do
    after(:create, &:unload_deferred)
  end
end
```

A test that does want the columns in memory calls `song.load_deferred(:lyrics)`.

### Reading deferred columns

```ruby
song = Song.first
song.has_attribute?(:lyrics) # => false
song.as_json                 # omits lyrics
song.lyrics                  # raises DeferredColumns::NotLoadedError
```

`song[:lyrics]` and `song.read_attribute(:lyrics)` raise the same error.
It's a subclass of `ActiveModel::MissingAttributeError` and has `model` and `column` readers.

New records have all their columns. If you override an attribute reader, call
`super` as usual.

### Reporting instead of raising

In production you may want to know where you missed a `with_deferred` without
breaking the page:

```ruby
# config/initializers/deferred_columns.rb
DeferredColumns.on_not_loaded = ->(error) {
  Rails.env.local? ? raise(error) : Rails.error.report(error)
}
```

If the handler returns, `song.lyrics` fetches the lyrics and returns them. In a
loop that's an extra query per song, so use the report to find the query that needs `with_deferred(:lyrics)`.

The same handler runs if you try to preload lyrics into an association that
Active Record considers loaded. By default you get a `NotLoadedError` if the
lyrics are missing. If the handler returns, the preloader fetches them in bulk.

### Writing records

You don't need to load the lyrics to update a song, even if you're updating the lyrics themselves:

```ruby
song = Song.find_by(name: "El Nicoya")
song.update!(composer: "José Areas") # leaves lyrics untouched
song.update!(lyrics: "Instrumental")
```

### Validations

```ruby
class Album < ApplicationRecord
  defer_columns :liner_notes
  validates :name, :liner_notes, presence: true
end

album = Album.find_by(name: "Abraxas")
album.update!(name: "Abraxas (Remastered)") # validates name, skips liner_notes
```

Attribute validators such as `presence` and `length` skip a deferred column
unless you loaded or assigned it. On new records they run as usual.
In a custom `validate` method, check `has_attribute?(:liner_notes)` before reading it.

### Reloading

`reload` remembers which deferred columns you loaded and refreshes those in a second query:

```ruby
song = Song.with_deferred(:lyrics).find(id)
song.reload.lyrics # fresh lyrics, still no waveform
```

## How it works 🔧

Active Record builds the default `SELECT` in `Relation#build_select`. For
models with deferred columns, the gem lists the columns to fetch instead of
selecting `*`. There's no `default_scope`, and models without deferred columns
keep their usual queries. For `eager_load`, the gem adjusts the column list for
each model in the join.

`with_deferred` keeps the requested columns in a relation extension, so they
survive `merge` and association scopes without changing what `count` counts.
`pluck` and `exists?` build their own selects. Raw SQL is unchanged.

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
