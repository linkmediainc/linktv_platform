require 'geocoder'

class Location < ActiveRecord::Base
  
  class << self
    
    # Attempts to create a new location record based on the given name - returns nil if 
    # an error occurs in the lookup. This method will try to avoid creating duplicates - if a
    # matching record is found, that record is returned
    def create_from_location_name(location_name)
      begin
        result = Geocoder.search(location_name)
        return nil unless result && !result.empty?
        loc = result.first
        return Location.find_or_create_by_name_and_latitude_and_longitude(
          :name => loc.address, 
          :latitude => loc.latitude,
          :longitude => loc.longitude
        )
      rescue Exception => e
        logger.error("Unable to get location for #{location_name}: #{e.to_s}")
        return nil
      end
    end
    
  end
  
end