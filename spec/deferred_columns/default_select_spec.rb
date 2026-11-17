# frozen_string_literal: true

RSpec.describe 'Leaving deferred columns out of the default SELECT' do
  let!(:abraxas) { Album.find_by!(name: 'Abraxas') }
  let!(:oye_como_va_id) { Song.unscoped.find_by!(name: 'Oye como va').id }
  let(:song_columns) { %w[id album_id type track name composer crowd_noise] }
  let(:lean_song_select) { song_columns.map { |name| column(:songs, name) }.join(', ') }

  it 'enumerates the remaining columns in table order' do
    expect(Song.where(track: 3).to_sql).to eq(%(SELECT #{lean_song_select} FROM "songs" WHERE "songs"."track" = 3))
    expect(Song.default_select_columns).to eq(song_columns)
  end

  it 'keeps SELECT * for models without deferred columns' do
    expect(Playlist.all.to_sql).to eq('SELECT "playlists".* FROM "playlists"')
    expect(PlaylistEntry.where(position: 1).to_sql).to start_with('SELECT "playlist_entries".* FROM')
  end

  {
    'where' => -> { Song.where(track: 3).to_a },
    'find' => -> { Song.find(oye_como_va_id) },
    'find_by' => -> { Song.find_by(name: 'Oye como va') },
    'find_by!' => -> { Song.find_by!(name: 'Oye como va') },
    'first' => -> { Song.first },
    'last' => -> { Song.last },
    'take' => -> { Song.take },
    'all.each' => -> { Song.all.each { |song| song } },
    'find_or_create_by' => -> { Song.find_or_create_by(name: 'Oye como va') },
    'distinct' => -> { Song.distinct.to_a },
    'order + limit + offset' => -> { Song.order(:track).limit(2).offset(1).to_a },
    'group + having' => -> { Song.group(:id).having('COUNT(*) > 0').to_a },
    'unscoped' => -> { Song.unscoped.to_a },
    'lock' => -> { Song.lock.where(track: 1).to_a },
  }.each do |finder, load|
    it "leaves them out of #{finder}" do
      statements = queries { instance_exec(&load) }.grep(/\ASELECT/)

      expect(statements).not_to be_empty
      statements.each do |sql|
        expect(sql).to include(column(:songs, :name))
        expect(sql).not_to include(column(:songs, :lyrics))
        expect(sql).not_to include(column(:songs, :waveform))
        expect(sql).not_to include('"songs".*')
      end
    end
  end

  it 'leaves them out of find_each and in_batches' do
    statements = queries { Song.find_each(batch_size: 4) { |song| song } }

    expect(statements.size).to eq(3)
    expect(statements).to all(start_with("SELECT #{lean_song_select} FROM"))
    expect(queries { Song.in_batches(of: 5).each_record { |song| song } }.grep(/lyrics/)).to be_empty
  end

  it 'leaves them out of records loaded through associations' do
    song = Song.find_by!(name: 'Samba pa ti')
    playlist = Playlist.find_by!(name: 'Latin Rock')

    expect(query { abraxas.songs.to_a }).not_to include('lyrics')
    expect(query { abraxas.opening_track }).not_to include('lyrics')
    expect(query { song.album }).not_to include('liner_notes')
    expect(query { abraxas.artist }).not_to include('biography')
    expect(query { playlist.songs.to_a }).not_to include('lyrics')
    expect(abraxas.songs.map(&:name)).to eq(Catalog::ABRAXAS.map(&:first))
  end

  it 'leaves them out of preload and includes' do
    statements = queries { Artist.preload(albums: :songs).to_a }
    expect(statements.size).to eq(3)
    expect(statements.join).not_to match(/biography|liner_notes|cover_art|lyrics|waveform/)

    statements = queries { Album.includes(:songs).where(name: 'Abraxas').to_a }
    expect(statements.join).not_to match(/liner_notes|lyrics/)
  end

  it 'leaves them out of eager_load' do
    sql = query { Album.eager_load(:songs, :artist).where(name: 'Abraxas').to_a }

    expect(sql).to include(%("songs"."name" AS))
    expect(sql).not_to match(/biography|liner_notes|cover_art|lyrics|waveform/)

    album = Album.eager_load(:songs).find_by!(name: 'Abraxas')
    expect(album.songs.size).to eq(9)
    expect(album.songs.first.has_attribute?(:lyrics)).to be(false)
  end

  it 'qualifies every column, so joins are never ambiguous' do
    songs = Song.joins(:album).where(albums: { name: 'Abraxas' }).order(:track).to_a
    expect(songs.map(&:track)).to eq((1..9).to_a)

    albums = Album.joins(:songs).where(songs: { name: 'Samba pa ti' }).to_a
    expect(albums.map(&:name)).to eq(['Abraxas'])
  end

  it 'leaves them out of a query from a subquery' do
    songs = Song.from(Song.where(album: abraxas), :songs).where(track: 1..3).to_a

    expect(songs.size).to eq(3)
    expect(songs.first.has_attribute?(:lyrics)).to be(false)
  end

  it 'leaves them out when reloading a record' do
    song = Song.with_deferred(:lyrics).find_by!(name: 'Oye como va')
    expect(song.lyrics).to eq('Lyrics for Oye como va')

    expect(query { song.reload }).not_to include('lyrics')
    expect(song.has_attribute?(:lyrics)).to be(false)
  end

  it 'respects ignored_columns' do
    expect(Album.default_select_columns).to eq(%w[id artist_id name release_date])
    expect(Album.select_all_columns.to_sql).not_to include('legacy_label')
  end

  it 'loads nothing for none' do
    expect(queries { Song.none.to_a }).to be_empty
  end
end
