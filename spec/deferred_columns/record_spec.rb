# frozen_string_literal: true

RSpec.describe 'Loading deferred columns into a record' do
  let!(:song) { Song.find_by!(name: 'Samba pa ti') }

  describe 'load_deferred' do
    it 'loads the given columns in a single query, as if the query had selected them' do
      sql = query { expect(song.load_deferred(:lyrics, :waveform)).to equal(song) }

      expect(sql).to include(column(:songs, :lyrics), column(:songs, :waveform))
      expect(sql).not_to include(column(:songs, :name))
      expect(song.lyrics).to eq('Lyrics for Samba pa ti')
      expect(song.waveform).to eq('waveform-7')
      expect(song.changed?).to be(false)
    end

    it 'loads every deferred column the record lacks when given none' do
      song.load_deferred(:lyrics)

      sql = query { song.load_deferred }

      expect(sql).to include(column(:songs, :waveform))
      expect(sql).not_to include(column(:songs, :lyrics))
      expect(song.attributes.keys).to match_array(Song.column_names)
    end

    it 'skips the query when there is nothing to load' do
      loaded = Song.with_deferred(:lyrics).find(song.id)

      expect(queries { loaded.load_deferred(:lyrics) }).to be_empty
      expect(queries { Song.new.load_deferred }).to be_empty
    end

    it 'keeps values assigned before loading' do
      song.lyrics = 'Instrumental'
      song.load_deferred(:lyrics)

      expect(song.lyrics).to eq('Instrumental')
      expect(song.changed).to eq(%w[lyrics])
    end

    it 'loads the columns a subclass defers' do
      live = LiveRecording.first

      expect(live.load_deferred(:crowd_noise).crowd_noise).to eq('Applause')
    end

    it 'validates the loaded columns afterwards' do
      song.load_deferred(:lyrics).lyrics = 'la ' * 1_000

      expect(song.valid?).to be(false)
      expect(song.errors.attribute_names).to eq([:lyrics])
    end

    it 'rejects columns that are not deferred' do
      expect { song.load_deferred(:name) }.to raise_error(ArgumentError, 'name is not a deferred column or group of Song')
    end

    it 'raises when the record no longer exists' do
      Song.where(id: song.id).delete_all

      expect { song.load_deferred(:lyrics) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'DeferredColumns.load' do
    let!(:songs) { Album.find_by!(name: 'Abraxas').songs.to_a }

    it 'loads the columns into many records with a single query' do
      sql = query { expect(DeferredColumns.load(songs, :lyrics)).to eq(songs) }

      expect(sql).to include(column(:songs, :lyrics)).and(include('IN ('))
      expect(songs.map(&:lyrics)).to eq(Catalog::ABRAXAS.map { |name, _| "Lyrics for #{name}" })
      expect(songs.none?(&:changed?)).to be(true)
    end

    it 'accepts groups, single records and relations' do
      albums = Album.all.to_a
      DeferredColumns.load(albums, :booklet)
      expect(albums.map(&:liner_notes)).to all(be_present)

      expect(DeferredColumns.load(Song.where(track: 3), :waveform).first.waveform).to eq('waveform-3')
      expect(DeferredColumns.load(songs.first, :lyrics).first.lyrics).to start_with('Lyrics for')
    end

    it 'queries once per model' do
      records = [songs.first, LiveRecording.first, songs.last]

      expect(queries { DeferredColumns.load(records, :lyrics) }.size).to eq(2)
      expect(records.map(&:lyrics)).to eq(['Lyrics for Singing Winds, Crying Beasts', 'Instrumental', 'Lyrics for El Nicoya'])
    end

    it 'only queries for what is missing' do
      loaded = Song.with_deferred(:lyrics).where(track: 1..2).to_a

      expect(queries { DeferredColumns.load(loaded, :lyrics) }).to be_empty
      expect(queries { DeferredColumns.load([Song.new, Song.new], :lyrics) }).to be_empty
      expect(queries { DeferredColumns.load([], :lyrics) }).to be_empty
    end

    it 'keeps values assigned before loading' do
      songs.first.lyrics = 'Instrumental'
      DeferredColumns.load(songs, :lyrics)

      expect(songs.first.lyrics).to eq('Instrumental')
      expect(songs.second.lyrics).to eq('Lyrics for Black Magic Woman / Gypsy Queen')
    end

    it 'raises when a record no longer exists' do
      Song.where(id: songs.last.id).delete_all

      expect { DeferredColumns.load(songs, :lyrics) }.to raise_error(ActiveRecord::RecordNotFound, /Couldn't find Song with 'id'=/)
    end
  end

  describe 'reload' do
    it 'keeps the deferred columns the record had loaded' do
      loaded = Song.with_deferred(:lyrics).find(song.id)
      Song.where(id: song.id).update_all(lyrics: 'Updated lyrics')

      statements = queries { loaded.reload }

      expect(statements.size).to eq(2)
      expect(loaded.lyrics).to eq('Updated lyrics')
      expect(loaded.has_attribute?(:waveform)).to be(false)
    end

    it 'keeps every column of a record that had them all' do
      created = Album.find_by!(name: 'Abraxas').songs.create!(track: 10, name: 'Jingo', lyrics: 'Jingo-lo-ba')

      expect(created.reload.lyrics).to eq('Jingo-lo-ba')
      expect(created.waveform).to be_nil
    end

    it 'discards unsaved changes to deferred columns, like any other attribute' do
      loaded = Song.with_deferred(:lyrics).find(song.id)
      loaded.lyrics = 'Unsaved'

      expect(loaded.reload.lyrics).to eq('Lyrics for Samba pa ti')
      expect(loaded.changed?).to be(false)
    end
  end
end
