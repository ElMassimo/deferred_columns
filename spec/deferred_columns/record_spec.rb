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
