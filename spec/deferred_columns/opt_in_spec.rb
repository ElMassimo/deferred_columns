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

    it 'works in association scopes when eager loading' do
      [
        -> { Album.eager_load(:songs_with_lyrics) },
        -> { Album.includes(:songs_with_lyrics).where(songs: { track: 1..9 }) },
        -> { Album.includes(:songs_with_lyrics).references(:songs) },
      ].each do |relation|
        album = nil
        sql = query { album = instance_exec(&relation).where(name: 'Abraxas').to_a.sole }

        expect(sql).to include(%("songs"."lyrics" AS))
        expect(sql).not_to include('waveform')
        expect(album.songs_with_lyrics.map(&:lyrics)).to all(start_with('Lyrics for'))
        expect(album.has_attribute?(:liner_notes)).to be(false)
      end
    end

    it 'works in through association scopes, when preloading or eager loading' do
      %i[preload eager_load].each do |strategy|
        playlist = Playlist.public_send(strategy, :songs_with_waveform).find_by!(name: 'Latin Rock')

        expect(playlist.songs_with_waveform.map(&:waveform)).to all(start_with('waveform-'))
        expect(playlist.songs_with_waveform.first.has_attribute?(:lyrics)).to be(false)
      end
    end

    it 'loads them for the root model when eager loading' do
      song = nil
      sql = query { song = Song.with_deferred(:lyrics).eager_load(:album).find_by!(name: 'El Nicoya') }

      expect(sql).to include(%("songs"."lyrics" AS))
      expect(sql).not_to match(/waveform|liner_notes/)
      expect(song.lyrics).to eq('Lyrics for El Nicoya')
      expect(song.album.has_attribute?(:liner_notes)).to be(false)
      expect(Album.with_deferred(:booklet).eager_load(:songs).find_by!(name: 'Abraxas').songs.first.has_attribute?(:lyrics)).to be(false)
    end

    it 'merges the joins of a relation of another model' do
      relation = Album.joins(:songs).merge(Song.joins(:playlist_entries)).distinct

      expect(relation.pluck(:name)).to contain_exactly('Abraxas')
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
        .to raise_error(ArgumentError, 'name is not a deferred column or group of Song')
      expect { Song.with_deferred(:lyrics, :lirycs, :title) }
        .to raise_error(ArgumentError, 'lirycs, title are not deferred columns or groups of Song')
      expect { Playlist.with_deferred(:lyrics) }
        .to raise_error(ArgumentError, 'lyrics is not a deferred column or group of Playlist')
      expect { Song.with_deferred }
        .to raise_error(ArgumentError, 'with_deferred requires at least one column')
    end

    it 'checks the columns of the relation model, not its base class' do
      expect(LiveRecording.with_deferred(:crowd_noise).first.crowd_noise).to eq('Applause')
      expect { Song.with_deferred(:crowd_noise) }
        .to raise_error(ArgumentError, 'crowd_noise is not a deferred column or group of Song')
    end
  end

  describe 'with_deferred_columns' do
    it 'loads every column, including the deferred ones' do
      album = Album.with_deferred_columns.find_by!(name: 'Abraxas')

      expect(album.attributes.keys).to eq(%w[id artist_id name release_date liner_notes cover_art])
      expect(album.liner_notes).to eq('Recorded at Wally Heider Studios, San Francisco.')
      expect(album.cover_art).to eq('Annunciation by Mati Klarwein')
    end

    it 'works on relations and associations, and keeps SELECT * for models without deferred columns' do
      expect(abraxas.songs.with_deferred_columns.first.lyrics).to eq('Lyrics for Singing Winds, Crying Beasts')
      expect(Song.where(track: 1).with_deferred_columns.to_sql).to include(column(:songs, :waveform))
      expect(Playlist.with_deferred_columns.to_sql).to eq('SELECT "playlists".* FROM "playlists"')
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
