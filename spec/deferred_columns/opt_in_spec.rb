# frozen_string_literal: true

RSpec.describe 'Opting into deferred columns' do
  let!(:abraxas) { Album.find_by!(name: 'Abraxas') }

  describe 'with_deferred' do
    it 'adds the given columns to the default ones, in table order' do
      sql = Song.with_deferred(:lyrics).where(track: 3).to_sql

      selected = %w[id album_id type track name composer lyrics crowd_noise].map { |name| column(:songs, name) }

      expect(sql).to start_with("SELECT #{selected.join(', ')} FROM")
      expect(sql).not_to include('waveform')
    end

    it 'loads them in the same query' do
      song = nil
      sql = query { song = Song.with_deferred(:lyrics).find_by!(name: 'Oye como va') }

      expect(sql).to include(column(:songs, :lyrics))
      expect(queries { expect(song.lyrics).to eq('Lyrics for Oye como va') }).to be_empty
      expect { song.waveform }.to raise_error(DeferredColumns::NotLoadedError)
    end

    it 'accepts several columns, arrays and strings, and accumulates across calls' do
      [
        Song.with_deferred(:lyrics, :waveform),
        Song.with_deferred(%w[lyrics waveform]),
        Song.with_deferred(:lyrics).with_deferred('waveform'),
        Song.with_deferred(:lyrics).where(track: 1).with_deferred(:waveform, :lyrics),
      ].each do |relation|
        expect(relation.first.attributes.keys).to eq(Song.column_names)
      end
    end

    it 'works anywhere in the chain, and on associations' do
      expect(Song.where(track: 7).with_deferred(:lyrics).first.lyrics).to eq('Lyrics for Samba pa ti')
      expect(abraxas.songs.with_deferred(:lyrics).map(&:lyrics)).to all(start_with('Lyrics for'))
      expect(Playlist.first.songs.with_deferred(:waveform).first.waveform).to eq('waveform-3')
    end

    it 'survives merge' do
      song = Song.where(track: 2).merge(Song.with_deferred(:waveform)).first

      expect(song.waveform).to eq('waveform-2')
      expect(song.has_attribute?(:lyrics)).to be(false)
    end

    it 'works in association scopes, including when preloading' do
      expect(abraxas.songs_with_lyrics.first.lyrics).to eq('Lyrics for Singing Winds, Crying Beasts')

      albums = nil
      statements = queries { albums = Album.preload(:songs_with_lyrics).where(name: 'Abraxas').to_a }
      expect(statements.last).to include(column(:songs, :lyrics))
      expect(albums.first.songs_with_lyrics.map(&:lyrics)).to all(start_with('Lyrics for'))
    end

    it 'keeps counting rows, and plucking only what was asked for' do
      relation = Song.with_deferred(:lyrics, :waveform).where(album: abraxas)

      expect(query { expect(relation.count).to eq(9) }).to match(/SELECT COUNT\(\*\) FROM "songs"/)
      expect(relation.pluck(:name)).to eq(Catalog::ABRAXAS.map(&:first))
      expect(relation.exists?).to be(true)
    end

    it 'is ignored by an explicit select, which loads exactly the selected columns' do
      expect(Song.select(:id, :name).with_deferred(:lyrics).first.attributes.keys).to eq(%w[id name])
      expect(Song.with_deferred(:lyrics).select(:id, :lyrics).first.attributes.keys).to eq(%w[id lyrics])
      expect(Song.with_deferred(:lyrics).reselect(:id).first.attributes.keys).to eq(%w[id])
    end

    it 'rejects columns that are not deferred' do
      expect { Song.with_deferred(:name) }
        .to raise_error(ArgumentError, 'name is not a deferred column of Song')
      expect { Song.with_deferred(:lyrics, :lirycs, :title) }
        .to raise_error(ArgumentError, 'lirycs, title are not deferred columns of Song')
      expect { Playlist.with_deferred(:lyrics) }
        .to raise_error(ArgumentError, 'lyrics is not a deferred column of Playlist')
      expect { Song.with_deferred }
        .to raise_error(ArgumentError, 'with_deferred requires at least one column')
    end

    it 'checks the columns of the relation model, not its base class' do
      expect(LiveRecording.with_deferred(:crowd_noise).first.crowd_noise).to eq('Applause')
      expect { Song.with_deferred(:crowd_noise) }
        .to raise_error(ArgumentError, 'crowd_noise is not a deferred column of Song')
    end
  end

  describe 'select_all_columns' do
    it 'loads every column, including the deferred ones' do
      album = Album.select_all_columns.find_by!(name: 'Abraxas')

      expect(album.attributes.keys).to eq(%w[id artist_id name release_date liner_notes cover_art])
      expect(album.liner_notes).to eq('Recorded at Wally Heider Studios, San Francisco.')
      expect(album.cover_art).to eq('Annunciation by Mati Klarwein')
    end

    it 'works on relations and associations, and keeps SELECT * for models without deferred columns' do
      expect(abraxas.songs.select_all_columns.first.lyrics).to eq('Lyrics for Singing Winds, Crying Beasts')
      expect(Song.where(track: 1).select_all_columns.to_sql).to include(column(:songs, :waveform))
      expect(Playlist.select_all_columns.to_sql).to eq('SELECT "playlists".* FROM "playlists"')
    end

    it 'is also available as with_deferred_columns' do
      expect(Album.with_deferred_columns.to_sql).to eq(Album.select_all_columns.to_sql)
      expect(abraxas.songs.with_deferred_columns.first.waveform).to eq('waveform-1')
    end
  end

  describe 'select' do
    it 'loads deferred columns like any other' do
      song = Song.select(:id, :name, :lyrics).find_by!(name: 'Se acabó')

      expect(song.lyrics).to eq('Lyrics for Se acabó')
      expect(song.attributes.keys).to eq(%w[id name lyrics])
    end

    it 'loads them for eager_load when selecting the whole table' do
      song = Song.eager_load(:album).select(Song.arel_table[Arel.star]).find_by!(name: 'El Nicoya')

      expect(song.lyrics).to eq('Lyrics for El Nicoya')
      expect(song.album.name).to eq('Abraxas')
    end
  end
end
