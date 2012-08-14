class CreateLocations < ActiveRecord::Migration
  def self.up
    create_table :locations do |t|
      t.with_options(:null => false) do |tt|
        tt.string :name
        # float with :limit => 25 should give us MySQL's double, which is what we want
        tt.float :latitude, :limit => 25
        tt.float :longitude, :limit => 25
      end
      t.timestamps
    end
    add_index :locations, :name, :unique => true
    
    add_column :video_segments, :location_id, :integer, :null => true
    add_index :video_segments, :location_id
  end

  def self.down
    remove_column :video_segments, :location_id
    drop_table :locations
  end
end
