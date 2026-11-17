# frozen_string_literal: true

RSpec.describe 'Reading deferred columns' do
  let(:song) { Song.find_by!(name: 'Black Magic Woman / Gypsy Queen') }

  it 'raises without querying when the column was not loaded' do
    song

    expect(queries {
      expect { song.lyrics }.to raise_error(DeferredColumns::NotLoadedError) { |error|
        expect(error.message).to eq(
          "Song#lyrics is a deferred column, so it isn't loaded by default. " \
          'Select it in the query, for example: Song.with_deferred(:lyrics), ' \
          'or load it into the record with load_deferred(:lyrics)',
        )
        expect(error.model).to eq(Song)
        expect(error.column).to eq('lyrics')
      }
    }).to be_empty
  end

  it 'raises an error that existing MissingAttributeError rescues handle' do
    expect { song.waveform }.to raise_error(ActiveModel::MissingAttributeError)
    expect(DeferredColumns::NotLoadedError.ancestors).to include(ActiveModel::MissingAttributeError)
  end

  it 'names the subclass that was loaded' do
    live = LiveRecording.first

    expect { live.crowd_noise }.to raise_error(DeferredColumns::NotLoadedError, /\ALiveRecording#crowd_noise .* LiveRecording\.with_deferred\(:crowd_noise\), /)
    expect { live.lyrics }.to raise_error(DeferredColumns::NotLoadedError, /\ALiveRecording#lyrics/)
  end

  it 'reads the column when it was loaded' do
    expect(Song.with_deferred(:lyrics).find(song.id).lyrics).to eq('Lyrics for Black Magic Woman / Gypsy Queen')
    expect(Song.select(:id, :waveform).find(song.id).waveform).to eq('waveform-2')
  end

  it 'reads it on new records, which have every column' do
    new_song = Song.new(name: 'Jingo', lyrics: 'Jingo-lo-ba')

    expect(new_song.lyrics).to eq('Jingo-lo-ba')
    expect(new_song.waveform).to be_nil
    expect(Song.new.lyrics).to be_nil
  end

  it 'keeps the other ways of reading attributes as Active Record defines them for unselected columns' do
    unselected = Song.select(:id).find(song.id)

    expect(song.has_attribute?(:lyrics)).to be(false)
    expect(song.has_attribute?(:name)).to be(true)
    expect { song[:lyrics] }.to raise_error(ActiveModel::MissingAttributeError)
    expect { unselected[:name] }.to raise_error(ActiveModel::MissingAttributeError)
    expect(song.read_attribute(:lyrics)).to eq(unselected.read_attribute(:name))
    expect(Song.attribute_names).to include('lyrics', 'waveform')
  end

  it 'serializes and inspects only the loaded columns' do
    expect(song.attributes.keys).to eq(%w[id album_id type track name composer crowd_noise])
    expect(song.as_json.keys).not_to include('lyrics', 'waveform')
    expect(song.as_json).to include('name' => 'Black Magic Woman / Gypsy Queen')
    expect(song.inspect).to start_with('#<Song id: ')
    expect(song.inspect).not_to include('lyrics')
  end

  it 'lets models override the reader and call super' do
    shouting = Class.new(ActiveRecord::Base) do
      self.table_name = 'songs'
      self.inheritance_column = nil
      defer_columns :lyrics

      def self.name = 'ShoutingSong'

      def lyrics = super.upcase
    end

    expect(shouting.with_deferred(:lyrics).find(song.id).lyrics).to eq('LYRICS FOR BLACK MAGIC WOMAN / GYPSY QUEEN')
    expect { shouting.find(song.id).lyrics }.to raise_error(DeferredColumns::NotLoadedError, /\AShoutingSong#lyrics/)
  end
end
