# frozen_string_literal: true

RSpec.describe 'Groups of deferred columns' do
  def define_model(&block)
    Class.new(ActiveRecord::Base) do
      self.table_name = 'songs'
      self.inheritance_column = nil
      def self.name = 'Track'

      class_eval(&block)
    end
  end

  let(:abraxas) { Album.find_by!(name: 'Abraxas') }

  it 'defers the columns and names the group' do
    expect(Album.deferred_columns).to eq(%w[liner_notes cover_art])
    expect(Album.deferred_column_groups).to eq('booklet' => %w[liner_notes cover_art])
    expect(Album.deferred_column_groups).to be_frozen
    expect(Song.deferred_column_groups).to eq({})
  end

  it 'loads every column in the group with with_deferred and load_deferred' do
    album = Album.with_deferred(:booklet).find(abraxas.id)
    expect(album.liner_notes).to eq('Recorded at Wally Heider Studios, San Francisco.')
    expect(album.cover_art).to eq('Annunciation by Mati Klarwein')

    album = Album.find(abraxas.id)
    sql = query { album.load_deferred(:booklet) }
    expect(sql).to include(column(:albums, :liner_notes), column(:albums, :cover_art))
    expect(album.cover_art).to eq('Annunciation by Mati Klarwein')
  end

  it 'mixes groups and columns, loading each column once' do
    sql = Album.with_deferred(:booklet, :liner_notes).to_sql

    expect(sql.scan(column(:albums, :liner_notes)).size).to eq(1)
    expect(sql).to include(column(:albums, :cover_art))
  end

  it 'works in association scopes, including when preloading' do
    artist = nil
    statements = queries { artist = Artist.preload(:albums_with_booklet).find_by!(name: 'Santana') }

    expect(statements.last).to include(column(:albums, :liner_notes), column(:albums, :cover_art))
    expect(artist.albums_with_booklet.map(&:liner_notes)).to include('Live in Osaka.')
  end

  it 'adds to a group declared before, and lets columns belong to several groups' do
    model = define_model do
      defer_columns :lyrics, as: :words
      defer_columns :waveform, as: :words
      defer_columns :lyrics, :crowd_noise, as: :live
    end

    expect(model.deferred_columns).to eq(%w[lyrics waveform crowd_noise])
    expect(model.deferred_column_groups).to eq('words' => %w[lyrics waveform], 'live' => %w[lyrics crowd_noise])
  end

  it 'inherits the groups, and keeps additions in a subclass' do
    parent = define_model { defer_columns :lyrics, as: :words }
    child = Class.new(parent) do
      def self.name = 'Cover'

      defer_columns :waveform, as: :words
    end

    expect(child.deferred_column_groups).to eq('words' => %w[lyrics waveform])
    expect(parent.deferred_column_groups).to eq('words' => %w[lyrics])
  end

  it 'suggests the group when reading a column that was not loaded' do
    expect { abraxas.liner_notes }.to raise_error(
      DeferredColumns::NotLoadedError,
      "Album#liner_notes is a deferred column, so it isn't loaded by default. " \
      'Select it in the query, for example: Album.with_deferred(:booklet), ' \
      'or load it into the record with load_deferred(:booklet)',
    )
  end

  it 'rejects groups named after deferred columns, and the other way around' do
    expect { define_model { defer_columns :lyrics, :waveform, as: :lyrics } }
      .to raise_error(ArgumentError, "lyrics is a deferred column of Track, so it can't name a group")

    expect { define_model { defer_columns(:lyrics, as: :words).then { defer_columns :words } } }
      .to raise_error(ArgumentError, 'words already names a group of deferred columns in Track')
  end

  it 'rejects unknown groups' do
    expect { Album.with_deferred(:sleeve) }.to raise_error(ArgumentError, 'sleeve is not a deferred column or group of Album')
  end
end
