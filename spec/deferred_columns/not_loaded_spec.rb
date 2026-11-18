# frozen_string_literal: true

RSpec.describe 'Deferred columns that were not loaded' do
  let(:reported) { [] }

  def reporting
    handler = DeferredColumns.on_not_loaded
    DeferredColumns.on_not_loaded = ->(error) { reported << error }
    yield
  ensure
    DeferredColumns.on_not_loaded = handler
  end

  def preload(records, associations, scope)
    ActiveRecord::Associations::Preloader.new(records:, associations:, scope:).call
  end

  describe 'on_not_loaded' do
    let(:song) { Song.find_by!(name: 'Oye como va') }

    it 'loads the column when the handler reports the error instead of raising it' do
      song
      reporting do
        sql = query { expect(song.lyrics).to eq('Lyrics for Oye como va') }
        expect(sql).to include(column(:songs, :lyrics))
        expect(sql).not_to include('waveform')
        expect(queries { song.lyrics }).to be_empty

        expect(song[:waveform]).to eq('waveform-3')
        expect(Song.find(song.id).read_attribute(:waveform)).to eq('waveform-3')
      end

      expect(reported.map(&:class)).to all(eq(DeferredColumns::NotLoadedError))
      expect(reported.map(&:column)).to eq(%w[lyrics waveform waveform])
      expect(reported.first.backtrace.join("\n")).to include(__FILE__)
      expect(song).not_to be_changed
    end

    it 'raises by default, without querying' do
      song
      expect(queries { expect { song.lyrics }.to raise_error(DeferredColumns::NotLoadedError) }).to be_empty
    end
  end

  describe 'when preloading an association that was already loaded' do
    let(:albums) { Album.where(name: %w[Abraxas Lotus]).order(:name).to_a }

    it 'raises when the preload scope opts into columns the records lack' do
      albums.first.songs.load

      expect { preload(albums, :songs, Song.with_deferred(:lyrics)) }.to raise_error(DeferredColumns::NotLoadedError, <<~MESSAGE.squish)
        Album#songs was already loaded without Song#lyrics, so preloading it again with that deferred column skipped it.
        Opt into it where the association is first loaded, for example: Song.with_deferred(:lyrics)
      MESSAGE
    end

    it 'loads the columns into the loaded records when the handler reports instead' do
      albums.first.songs.load

      statements = reporting { queries { preload(albums, :songs, Song.with_deferred(:lyrics, :waveform)) } }

      expect(reported.size).to eq(1)
      expect(statements.size).to eq(2)
      expect(statements.last).to match(/SELECT "songs"."id", "songs"."lyrics", "songs"."waveform" FROM "songs" WHERE/)
      expect(albums.flat_map(&:songs).map(&:lyrics)).to all(be_present)
    end

    it 'does nothing when the loaded records already have them' do
      album = Album.preload(:songs_with_lyrics).find_by!(name: 'Abraxas')
      album.association(:songs).target = album.songs.with_deferred(:lyrics).to_a

      expect(queries {
        preload([album], :songs, Song.with_deferred(:lyrics))
        preload([album], :songs_with_lyrics, nil)
      }).to be_empty
    end

    it 'checks the opt-ins of the association scope too, including through associations' do
      playlist = Playlist.find_by!(name: 'Latin Rock')
      playlist.association(:songs_with_waveform).target = playlist.songs.to_a

      reporting { preload([playlist], :songs_with_waveform, nil) }

      expect(reported.map(&:message)).to all(start_with('Playlist#songs_with_waveform was already loaded without Song#waveform'))
      expect(playlist.songs_with_waveform.map(&:waveform)).to all(start_with('waveform-'))
    end
  end

  describe 'DeferredColumns.load' do
    it 'reads the values without instantiating records' do
      songs = Song.where(album: Album.find_by!(name: 'Abraxas')).to_a
      instantiated = []
      callback = ->(*, payload) { instantiated << payload[:class_name] }

      ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') { DeferredColumns.load(songs, :lyrics) }

      expect(instantiated).to be_empty
      expect(songs.map(&:lyrics)).to all(start_with('Lyrics for'))
    end
  end
end
