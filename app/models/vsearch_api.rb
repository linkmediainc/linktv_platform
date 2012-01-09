class VsearchApi < SemanticApi

  def query args
    begin
      return nil unless args[:text] && args[:text].is_a?(String) && !args[:text].empty?

      query = args[:topics_data].inject('') do |str, topic| 
        str += ('"' + topic['name'].gsub(/"/, '\"') + '" ')
      end
      params = { 'q' => query, 'mm' => 1 }

      # TODO: reset this
      self.url = "http://localhost:8000/api/video/search"
      uri = URI.parse(self.url + query_string(params))
      response = Net::HTTP.get_response uri

      results = JSON.parse response.body

      if response.code != '200'
        return {
          :status => "error",
          :response_code => response.code,
          :message => results
        }
      end

      result = {
        :status => nil
      }

      # This API really only accepts the one content type, video
      content_type = self.content_types[0]
      result[:content_types] ||= {}
      result[:content_types][content_type.id] = []
      
      high_score = (results.collect { |res| res['score'].to_f }).max rescue nil
      return result if high_score.nil?

      results_by_identifier = {}
      results.each do |item|
        # These are provision records only, and will only be saved if they are submitted by 
        # the client. Since we're using a non-URL for the identifier, we add the semantic API 
        # id for scoping purposes.
        identifier = "#{self.id}:#{item['url']}"
        next if results_by_identifier[identifier]
        results_by_identifier[identifier] = true;

        content_source = ContentSource.find_or_create_by_url(item['source']['url'],
          :name => item['source']['name'])

        result[:content_types][content_type.id] << ExternalContent.new({
          :data => item.to_json,
          :name => item['name'] || nil,
          :description => item['description'] || nil,
          :url => item['url'] || nil,
          :identifier => identifier,
          :duration => item['runtime'] || nil,
          :published_at => item['published_at'] || nil,
          :content_source => content_source,
          :score => (item['score'].to_f / high_score * 100).to_i || nil,
          :content_type => content_type,
          :semantic_api => self,
          :active => true,
          :deleted => false
        }) unless args[:omit_identifiers][identifier].present?
      end

      result[:status] = :success
      return result
    rescue => error
      raise
    end
  end

  # TODO: is this still used?
  # Extract the thumbnail URL from item data
  def self.thumbnail_url json
    item_data = JSON.parse(json)
    return false if item_data.nil? || item_data.empty?
    item_data['thumbnail']
  end

end

