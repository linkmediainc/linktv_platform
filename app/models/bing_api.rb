class BingApi < SemanticApi

  def query args
    begin
      # Defaults
      params = {
        "Appid" => APP_CONFIG[:apis][:bing][:appid],
        "Version" => '2.2',
        "Market" => 'en-US',
        "Sources" => 'Video',
        'Video.SortBy' => 'Date',
        'Video.Count' => APP_CONFIG[:apis][:bing][:limit] || 10
      }

      # Apply DB overrides
      db_params = self.query_params.nil? ? {} : JSON.parse(self.query_params)
      params.merge! db_params

      args[:omit_identifiers] ||= {}

      and_keywords = []
      not_keywords = []
      or_keywords = []
      args[:topics_data].each do |topic_data|
        score = topic_data['score'].to_i
        or_keywords << "\"#{topic_data['name'].gsub(/"/, '\"')}\"" if score > 0
        not_keywords << "-\"#{topic_data['name'].gsub(/"/, '\"')}\"" if score == -1

        # Require keywords with weights >= threshold
        if score >= APP_CONFIG[:apis][:config][:emphasis_threshold]
          and_keywords << "+\"#{topic_data['name'].gsub(/"/, '\"')}\"" unless score == 0
        end
      end

      if and_keywords.empty? && or_keywords.empty?
        return {
          :status => "error",
          :message => "No keywords selected"
        }
      end

      params['Query'] = "(#{and_keywords.join(' ')} #{not_keywords.join(' ')}) AND (#{or_keywords.join(' OR ')})"
      params['Video.count'] = args[:limit] if args[:limit].present?

      uri = URI.parse(self.url)
      response = Net::HTTP.get_response uri.host, uri.path.concat(query_string(params))
      unless PRODUCTION_MODE
        logger.info 'BingApi::query ' + params.inspect
        logger.info 'BingApi::query response code ' + response.code
        logger.info 'BingApi::query response body ' + response.body
      end

      body = JSON.parse response.body

      if response.code != '200'
        return {
          :status => "error",
          :response_code => response.code,
          :message => body
        }
      end

      result = {
        :status => nil
      }

      # This API really only accepts the one content type, vidoe
      content_type = self.content_types[0]
      result[:content_types] ||= {}
      result[:content_types][content_type.id] = []

      results_by_identifier = {}
      videos = (body['SearchResponse']['Video']['Results'] rescue [])
      videos.each do |item|
        # These are provision records only, and will only be saved if they are submitted by the client.
        # Since we're using a non-URL for the identifier, we add the semantic API id for scoping purposes.
        identifier = "#{self.id}:#{item['PlayUrl']}"
        next if results_by_identifier[identifier] || nil
        results_by_identifier[identifier] = true;

        require 'uri'
        uri = URI.parse(item['PlayUrl'])
        source_url = "#{uri.scheme}://#{uri.host}"

        content_source = ContentSource.find_or_create_by_url(source_url, :name => item['SourceTitle'])

        result[:content_types][content_type.id] << ExternalContent.new({
          :data => item.to_json,
          :name => item['Title'] || nil,
          :description => nil,
          :url => item['PlayUrl'] || nil,
          :identifier => item['PlayUrl'] || nil,
          :duration => item['RunTime'] || nil,
          :published_at => item['dateProduced'] || nil,
          :content_source => content_source,
          :score => 1.0,
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

  # Extract the thumbnail URL from item data
  def self.thumbnail_url json
    item_data = JSON.parse(json)
    return false if item_data.nil? || item_data.empty?
    item_data['StaticThumbnail']['Url'] rescue nil
  end

end

=begin
Sample response

http://msdn.microsoft.com/en-us/library/dd250846.aspx

{
   "SearchResponse":{
      "Version":"2.2",
      "Query":{
         "SearchTerms":"testign"
      },
      "Spell":{
         "Total":1,
         "Results":[
            {
               "Value":"testing"
            }
         ]
      },
      "Web":{
         "Total":5100,
         "Offset":0,
         "Results":[
            {
               "Title":"Testign part 2 - Tiernan OTooles Programming Blog",
               "Description":"If this works, it means nothing really, but i have managed to build a .TEXT blog posting app. could be handy if i move my main blog to .TEXT, which i am thinking about..",
               "Url":"http:\/\/weblogs.asp.net\/tiernanotoole\/archive\/2004\/09\/24\/233830.aspx",
               "DisplayUrl":"http:\/\/weblogs.asp.net\/tiernanotoole\/archive\/2004\/09\/24\/233830.aspx",
               "DateTime":"2008-10-21T05:08:05Z"
            }
         ]
      }
   }
}

=end


# == Schema Information
#
# Table name: semantic_apis
#
#  id           :integer(4)      not null, primary key
#  type         :string(255)
#  name         :string(255)
#  url          :string(1024)
#  query_params :string(1024)
#  quota_config :string(1024)
#  active       :boolean(1)      default(FALSE), not null
#  deleted      :boolean(1)      default(FALSE), not null
#  lifetime     :integer(4)
#  created_at   :datetime
#  updated_at   :datetime
#

