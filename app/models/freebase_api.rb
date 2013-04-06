class FreebaseApi < EntityDb

  def provides_data?
    true
  end

  def uri_to_identifier uri
    uri.gsub(/http:\/\/([^\.]+.)?freebase.com(\/ns)?(.+)/, '\3')
  end

  def identifier_to_uri identifier
    "http://www.freebase.com#{identifier}"
  end

  def lookup identifier, options = {}
    result = super identifier, options
    return result unless result.nil?

    require 'open-uri'
    mode = options[:xrefs] ? 'standard' : 'basic'

    # Updated Apr 2013 after the old Freebase API was deactivated. The new
    # API return much more information by default. Filters are used in the
    # query string to limit this data to the items actually needed.
    uri = "https://www.googleapis.com/freebase/v1/topic#{identifier}" +
      "?filter=/type/object/name" +
      "&filter=/common/topic/description" +
      "&filter=/common/topic/image&limit=1" +
      "&filter=/common/topic/topic_equivalent_webpage" +
      "&key=#{APP_CONFIG[:apis][:google][:browser_key]}"

    begin
      socket = open uri
      response = JSON.parse(socket.read)
      return nil unless response

      data = response['property']

      # Some of the data is optional. Topics often do not have thumbnails
      # and even limited testing finds topics that lack a description.
      # These are useless, but should not cause the admin page to break.
      # The assumption is that the name must be present.
      description = 'No description provided'
      unless data['/common/topic/description'].nil?
        description = data['/common/topic/description']['values'][0]['value']
        end

      thumbnail_uri = nil
      unless data['/common/topic/image'].nil?
        thumbnail_uri = "https://www.googleapis.com/freebase/v1/image" +
          "#{data['/common/topic/image']['values'][0]['id']}"
      end

      # Not using symbols for keys since this will be JSON-encoded and restored later
      result = {
        'entity_db_id' => self.id,
        'identifier' => identifier,
        'uri' => identifier_to_uri(identifier),
        'name' => data['/type/object/name']['values'][0]['text'],
        'description' => description,
        'thumbnail_uri' => thumbnail_uri,
        'xrefs' => []
      }

      unless (webpages = data['/common/topic/topic_equivalent_webpage']['values']).nil?
        # Add supported entity identifiers
        webpages.each do |webpage|
          entity_uri = webpage['text']
          next unless (entity_db = EntityDb.entity_db_by_uri entity_uri)
          result[:xrefs] << {
            'entity_db_id' => entity_db.id,
            'identifier' => entity_db.uri_to_identifier(entity_uri),
            'uri' => entity_uri
          }
        end
      end
    rescue OpenURI::HTTPError => e
      Rails.logger.error "freebase: OpenURI exception -- #{e}"
      Rails.logger.error "freebase: URI: #{uri}"
      result = nil

    rescue NoMethodError => e
      Rails.logger.error "freebase: NoMethodError exception -- #{e}"
      Rails.logger.error "freebase: URI: #{uri} possible empty name"
      result = nil
    end
    result
  end

end

# == Schema Information
#
# Table name: entity_dbs
#
#  id               :integer(4)      not null, primary key
#  type             :string(255)
#  name             :string(255)
#  description      :text
#  url              :string(1024)
#  icon_css_class   :string(255)
#  identifier_regex :string(255)
#  active           :boolean(1)      default(FALSE), not null
#  deleted          :boolean(1)      default(FALSE), not null
#  created_at       :datetime
#  updated_at       :datetime
#

