# frozen_string_literal: true

RSpec.describe 'Writing records loaded without their deferred columns' do
  let(:song) { Song.find_by!(name: "Mother's Daughter") }
  let(:album) { Album.find_by!(name: 'Abraxas') }

  def stored(record, column)
    record.class.unscoped.where(id: record.id).pick(column)
  end

  it 'updates other columns without touching the deferred ones' do
    sql = queries { song.update!(composer: 'Gregg Rolie (Santana)') }.grep(/UPDATE/).sole

    expect(sql).to include('"composer"')
    expect(sql).not_to include('lyrics')
    expect(stored(song, :lyrics)).to eq("Lyrics for Mother's Daughter")
    expect(stored(song, :composer)).to eq('Gregg Rolie (Santana)')
  end

  it 'is not dirty after loading' do
    expect(song.changed?).to be(false)
    expect(song.changed_attributes).to be_empty
    expect(queries { song.save! }.grep(/UPDATE/)).to be_empty
  end

  it 'persists a deferred column assigned without loading it' do
    song.lyrics = 'New lyrics'

    expect(song.lyrics).to eq('New lyrics')
    expect(song.changed).to eq(%w[lyrics])
    expect(queries { song.save! }.grep(/UPDATE/).sole).to include('"lyrics"')
    expect(stored(song, :lyrics)).to eq('New lyrics')
  end

  it 'supports update, update_column and update_all on deferred columns' do
    song.update!(lyrics: 'Updated')
    expect(stored(song, :lyrics)).to eq('Updated')

    song.update_column(:waveform, 'flat'.b)
    expect(stored(song, :waveform)).to eq('flat')

    Song.where(album: album).update_all(lyrics: nil)
    expect(Song.where(album: album).pluck(:lyrics).uniq).to eq([nil])
  end

  it 'creates records with deferred columns' do
    created = album.songs.create!(track: 10, name: 'Jingo', lyrics: 'Jingo-lo-ba', waveform: 'w'.b)

    expect(created.lyrics).to eq('Jingo-lo-ba')
    expect(stored(created, :lyrics)).to eq('Jingo-lo-ba')
    expect(stored(created, :waveform)).to eq('w')
  end

  it 'destroys records' do
    expect { song.destroy! }.to change(Song, :count).by(-1)
  end

  describe 'validations' do
    it 'skips validations of deferred columns that were not loaded' do
      expect(album.valid?).to be(true)
      expect(song.valid?).to be(true)
      expect { album.update!(name: 'Abraxas (Remastered)') }.not_to raise_error
    end

    it 'still validates the loaded attributes of a combined validation' do
      album.name = ''

      expect(album.valid?).to be(false)
      expect(album.errors.attribute_names).to eq([:name])
    end

    it 'validates deferred columns that were loaded' do
      loaded = Album.with_deferred(:liner_notes).find(album.id)
      loaded.liner_notes = ''

      expect(loaded.valid?).to be(false)
      expect(loaded.errors.attribute_names).to eq([:liner_notes])
    end

    it 'validates deferred columns that were assigned' do
      song.lyrics = 'la ' * 1_000

      expect(song.valid?).to be(false)
      expect(song.errors.attribute_names).to eq([:lyrics])
    end

    it 'validates every column on new records' do
      expect(Album.new(name: 'Caravanserai').valid?).to be(false)
      expect(Album.new(name: 'Caravanserai', liner_notes: 'Recorded in 1972.').valid?).to be(true)
    end

    it 'leaves validators of models without deferred columns alone' do
      validated = Class.new do
        include ActiveModel::Validations

        def self.name = 'Setlist'

        attr_accessor :title

        validates :title, presence: true
      end

      expect(validated.new.valid?).to be(false)
      expect(validated.new.tap { |setlist| setlist.title = 'Woodstock' }.valid?).to be(true)
    end
  end
end
