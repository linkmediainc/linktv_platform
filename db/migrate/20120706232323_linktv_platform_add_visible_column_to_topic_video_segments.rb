class LinktvPlatformAddVisibleColumnToTopicVideoSegments < ActiveRecord::Migration
  def self.up
    add_column :topic_video_segments, :visible, :boolean, :null => false, :default => true
    TopicVideoSegment.update_all("visible = 1")
  end

  def self.down
    remove_column :topic_video_segments, :visible
  end
end
