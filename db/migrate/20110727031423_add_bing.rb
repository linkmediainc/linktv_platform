class AddBing < ActiveRecord::Migration
  def self.up
    bing = BingApi.create!({
        :name => "Bing",
        :url => "http://api.search.live.net/json.aspx",
        :query_params => nil,
        :quota_config => nil,
        :active => true,
        :lifetime => nil})
    ct_videos = ContentType.find_by_name('Related Videos')
    ContentTypeSemanticApi.create!({:semantic_api_id => bing.id, :content_type_id => ct_videos.id})
  end

  def self.down
  end
end
