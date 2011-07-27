class RemoveTruveo < ActiveRecord::Migration
  def self.up
    r = ContentTypeSemanticApi.scoped(:joins => :semantic_api, :conditions => "semantic_apis.name = 'Truveo'").first
    r.destroy
    SemanticApi.delete_all("name = 'Truveo'")
  end

  def self.down
  end
end
