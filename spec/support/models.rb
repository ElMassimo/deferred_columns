# frozen_string_literal: true

# Active Record also reads DATABASE_URL, so it's removed once read; CI sets it empty for SQLite.
if (database_url = ENV.delete('DATABASE_URL').to_s).empty?
  ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
else
  ActiveRecord::Base.establish_connection(database_url)
end

ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :artists, force: true do |t|
    t.string :name, null: false
    t.text :biography
  end

  create_table :albums, force: true do |t|
    t.references :artist
    t.string :name, null: false
    t.date :release_date
    t.text :liner_notes
    t.binary :cover_art
    t.string :legacy_label
  end

  create_table :songs, force: true do |t|
    t.references :album
    t.string :type
    t.integer :track
    t.string :name
    t.string :composer
    t.text :lyrics
    t.binary :waveform
    t.text :crowd_noise
  end

  create_table :playlists, force: true do |t|
    t.string :name
  end

  create_table :playlist_entries, force: true do |t|
    t.references :playlist
    t.references :song
    t.integer :position
  end
end

class Artist < ActiveRecord::Base
  defer_columns :biography

  has_many :albums
  has_many :albums_with_booklet, -> { with_deferred(:booklet) }, class_name: 'Album'
end

class Album < ActiveRecord::Base
  self.ignored_columns += %w[legacy_label]
  defer_columns :liner_notes, :cover_art, as: :booklet

  belongs_to :artist
  has_many :songs, -> { order(:track) }
  has_many :songs_with_lyrics, -> { with_deferred(:lyrics).order(:track) }, class_name: 'Song'
  has_one :opening_track, -> { where(track: 1) }, class_name: 'Song'

  validates :name, :liner_notes, presence: true
end

class Song < ActiveRecord::Base
  defer_columns :lyrics, :waveform

  belongs_to :album
  has_many :playlist_entries

  validates :name, presence: true
  validates :lyrics, length: { maximum: 2_000 }
end

class LiveRecording < Song
  defer_columns :crowd_noise
end

class Playlist < ActiveRecord::Base
  has_many :playlist_entries, -> { order(:position) }
  has_many :songs, through: :playlist_entries
  has_many :songs_with_waveform, -> { with_deferred(:waveform) }, through: :playlist_entries, source: :song
end

class PlaylistEntry < ActiveRecord::Base
  belongs_to :playlist
  belongs_to :song
end

module Catalog
  ABRAXAS = [
    ['Singing Winds, Crying Beasts', 'Michael Carabello'],
    ['Black Magic Woman / Gypsy Queen', 'Peter Green, Gábor Szabó'],
    ['Oye como va', 'Tito Puente'],
    ['Incident at Neshabur', 'Alberto Gianquinto, Carlos Santana'],
    ['Se acabó', 'José Areas'],
    ["Mother's Daughter", 'Gregg Rolie'],
    ['Samba pa ti', 'Carlos Santana'],
    ["Hope You're Feeling Better", 'Gregg Rolie'],
    ['El Nicoya', 'José Areas'],
  ].freeze

  def self.seed
    santana = Artist.create!(name: 'Santana', biography: 'Latin rock band formed in San Francisco in 1966.')

    abraxas = santana.albums.create!(
      name: 'Abraxas',
      release_date: Date.new(1970, 9, 23),
      liner_notes: 'Recorded at Wally Heider Studios, San Francisco.',
      cover_art: 'Annunciation by Mati Klarwein'.b,
    )
    ABRAXAS.each.with_index(1) do |(name, composer), track|
      abraxas.songs.create!(track:, name:, composer:, lyrics: "Lyrics for #{name}", waveform: "waveform-#{track}".b)
    end

    lotus = santana.albums.create!(name: 'Lotus', release_date: Date.new(1974, 5, 1), liner_notes: 'Live in Osaka.')
    lotus.songs.create!(type: 'LiveRecording', track: 1, name: 'Going Home', composer: 'Santana', lyrics: 'Instrumental', crowd_noise: 'Applause')

    Playlist.create!(name: 'Latin Rock').tap do |playlist|
      Song.where(name: ['Oye como va', 'Samba pa ti']).order(:track).each.with_index(1) do |song, position|
        playlist.playlist_entries.create!(song:, position:)
      end
    end
  end
end
