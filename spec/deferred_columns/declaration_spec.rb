# frozen_string_literal: true

RSpec.describe 'Declaring deferred columns' do
  def define_model(table: :songs, &block)
    Class.new(ActiveRecord::Base) do
      self.table_name = table
      self.inheritance_column = nil
      def self.name = 'Track'

      class_eval(&block) if block
    end
  end

  it 'exposes the deferred columns of each model' do
    expect(Song.deferred_columns).to eq(%w[lyrics waveform])
    expect(Album.deferred_columns).to eq(%w[liner_notes cover_art])
    expect(Playlist.deferred_columns).to eq([])
    expect(ActiveRecord::Base.deferred_columns).to eq([])
  end

  it 'accepts strings, symbols and arrays, and accumulates without duplicates' do
    model = define_model do
      defer_columns 'lyrics'
      defer_columns %i[waveform lyrics]
    end

    expect(model.deferred_columns).to eq(%w[lyrics waveform])
    expect(model.deferred_columns).to be_frozen
  end

  it 'is inherited, and additions in a subclass stay in the subclass' do
    expect(LiveRecording.deferred_columns).to eq(%w[lyrics waveform crowd_noise])
    expect(Song.deferred_columns).not_to include('crowd_noise')
    expect(LiveRecording.default_select_columns).to eq(%w[id album_id type track name composer])
    expect(Song.default_select_columns).to include('crowd_noise')
  end

  it 'applies the subclass columns to single table inheritance queries' do
    expect(LiveRecording.all.to_sql).not_to include('crowd_noise')
    expect(LiveRecording.first.has_attribute?(:crowd_noise)).to be(false)

    loaded_through_parent = Song.find_by!(name: 'Going Home')
    expect(loaded_through_parent).to be_a(LiveRecording)
    expect(loaded_through_parent.crowd_noise).to eq('Applause')
  end

  it 'leaves models alone until they declare a column' do
    model = define_model
    expect(model.all.to_sql).to eq('SELECT "songs".* FROM "songs"')

    model.defer_columns :lyrics
    expect(model.all.to_sql).not_to include('lyrics')
  end

  it 'ignores declared columns that the table does not have' do
    model = define_model { defer_columns :lyrics, :tablature }

    expect(model.default_select_columns).to eq(Song.column_names - %w[lyrics])
    expect(model.first.name).to eq('Singing Winds, Crying Beasts')
  end

  it 'picks up schema changes after reset_column_information' do
    model = define_model(table: :artists) { defer_columns :biography }
    expect(model.default_select_columns).to eq(%w[id name])

    ActiveRecord::Base.connection.add_column(:artists, :origin, :string)
    model.reset_column_information
    expect(model.default_select_columns).to eq(%w[id name origin])
  ensure
    ActiveRecord::Base.connection.remove_column(:artists, :origin) if ActiveRecord::Base.connection.column_exists?(:artists, :origin)
    model&.reset_column_information
  end

  it 'reports its version' do
    expect(DeferredColumns::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end
end
