# frozen_string_literal: true

RSpec.describe 'Calculations on models with deferred columns' do
  let!(:abraxas) { Album.find_by!(name: 'Abraxas') }

  [
    -> { Song.all },
    -> { Song.with_deferred(:lyrics) },
    -> { Song.with_deferred_columns },
  ].each.with_index do |relation, index|
    describe "on relation ##{index + 1}" do
      let(:songs) { instance_exec(&relation).where(album: abraxas) }

      it 'counts rows' do
        expect(query { expect(songs.count).to eq(9) }).to include('COUNT(*)')
        expect(songs.count(:all)).to eq(9)
        expect(songs.distinct.count).to eq(9)
        expect(songs.count(:lyrics)).to eq(9)
        expect(songs.size).to eq(9)
        expect(songs.group(:composer).count).to include('José Areas' => 2, 'Gregg Rolie' => 2)
      end

      it 'aggregates columns' do
        expect(songs.sum(:track)).to eq(45)
        expect(songs.maximum(:track)).to eq(9)
        expect(songs.minimum(:name)).to eq('Black Magic Woman / Gypsy Queen')
        expect(songs.average(:track).to_d).to eq(5)
      end

      it 'plucks and picks exactly the requested columns, deferred or not' do
        expect(songs.order(:track).pluck(:track, :name).first).to eq([1, 'Singing Winds, Crying Beasts'])
        expect(songs.where(track: 3).pluck(:lyrics)).to eq(['Lyrics for Oye como va'])
        expect(songs.where(track: 3).pick(:waveform)).to eq('waveform-3')
        expect(songs.ids.size).to eq(9)
      end

      it 'checks existence and filters on deferred columns' do
        expect(songs.exists?).to be(true)
        expect(songs.exists?(lyrics: 'Lyrics for El Nicoya')).to be(true)
        expect(songs.where(lyrics: 'Lyrics for El Nicoya').pick(:track)).to eq(9)
        expect(songs.order(:lyrics).first.track).to eq(2)
      end
    end
  end
end
