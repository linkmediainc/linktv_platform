namespace :linktv do

  desc "Sets up the new vsearch api."
  task :add_vsearch_api => :environment do
    api = SemanticApi.find_or_create_by_type('VsearchApi', :name => 'VSearch', 
      :url => 'http://vsearch.linktv.org/api/video/search', :active => 1, :deleted => 0)
    related_videos_type = ContentType.find_by_name('Related Videos')
    unless api.content_type_semantic_apis.find_by_content_type_id(related_videos_type.id)   
      api.content_type_semantic_apis.create(:content_type => related_videos_type) 
    end
    if truveo_api = SemanticApi.find_by_type('TruveoApi')
      truveo_api.update_attribute(:active, false)
      ContentTypeSemanticApi.destroy_all(:semantic_api_id => truveo_api.id)
    end
  end
  
end

