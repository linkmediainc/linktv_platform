class Admin::LocationsController < Admin::AdminController

  def autocomplete
    if params['q'].nil? || params['q'].empty?
      render :nothing => true
      return
    end

    data = []

    records = Location.all(
      :limit => 100,
      :order => :name,
      :conditions => ['name LIKE ?', "%#{params['q']}%"])
    records.each do |record|
      data << {
        'id' => record.id,
        'name' => record.name
      }
    end

    result = {
      :status => 'success',
      :data => data
    }

    respond_to do |format|
      format.json {
        render :json => result
      }
    end

  end

end

