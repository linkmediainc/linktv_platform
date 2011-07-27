class SuperAdmin::ImagesController < SuperAdmin::SuperAdminController

  active_scaffold :images do |config|
    config.list.columns =
      [:id, :filename, :attribution]
    config.show.columns =
      [:id, :filename, :attribution, :created_at, :updated_at]
    config.create.columns = config.update.columns =
      [:filename, :attribution]
  end

end
