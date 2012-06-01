require 'RMagick'

class Admin::ImagesController < Admin::AdminController

  # Not DRY: copied from the applications app/models/mobile/summary.rb,
  # but should be defined in the plugin, somewhere.
  IMAGE_DIMENSIONS    = {
    :small_or_related => {:width =>324, :height =>212},
    :sidebar_or_doc   => {:width =>324, :height =>202},
    :medium           => {:width =>324, :height =>303},
    :x_large          => {:width =>654, :height =>443}
  }
  
  IMAGE_GROUPS = {
    'square' => {"Home Screen Medium"  => IMAGE_DIMENSIONS[:medium]},
    '16x9'   => {"Small/Related Video" => IMAGE_DIMENSIONS[:small_or_related],
                 "Sidebar/Documentary" => IMAGE_DIMENSIONS[:sidebar_or_doc],
                 "Lead Story"          => IMAGE_DIMENSIONS[:x_large]}
  }
  
  before_filter :find_image, :only => [:show]
  def find_image
    @image = Image.find params[:id]
    raise Exceptions::HTTPNotFound if @image.nil?
  end
  protected :find_image

  helper :images

  def show
    file = open @image.pathname
    send_data file.read, :type => "image/png", :disposition => 'inline'
  end

  def create
    # Note: The ajaxupload.js doesn't proreply return JSON, at least in Firefox 3.6
    begin
      raise "No filename received" unless params[:filename]
      raise "No image data received" unless params[:image]
      raise "Invalid file type" unless (params[:image].content_type rescue nil) =~ /^image\/jpeg|image\/png$/

      image = Image.create! :filename => params[:filename]
      image.write params[:image].read

      respond_to do |format|
        format.xml {
          render :xml => {:status => 'success', :id => image.id, :src => @template.thumbnail_url(image)}
        }
      end
    rescue => error
      respond_to do |format|
        format.xml {
          render :xml => {:status => 'error', :message => error.to_s}, :status => :bad_request
        }
      end
    end

  end

  # GET /images/1/original
  
  # This streams the original image from the "media" directory,
  # which is not directly accessible via the webserver. Routing
  # ensures that these resources are only available to administrators.
  def original
    image = Image.find(params[:id])
    
    begin
    File.open(image.pathname, 'rb') do |f|
        send_data f.read, :type => "image/jpeg", :disposition => "inline"
      end
    rescue
    end
  end
  
  # GET /images/1
  def prepare_crop
    @image_id  = params[:id] 
    @image_uri = '/admin/images/' + @image_id + '/original' 

    respond_to do |format|
      format.html { render :layout => 'prepare_crop'} # prepare_crop.html.erb
    end
  end
  
  # POST /images/1/crop
  def crop
    
    # Find the original image and perform the user's requested crop.
    # This image may be further refined below.
    image   = Image.find(params[:id])
    w = params[:w].to_i
    h = params[:h].to_i
    orig    = Magick::ImageList.new(image.pathname)
    cropped = orig.crop(params[:x].to_i, params[:y].to_i, w, h)
    
    # Filesystem housekeeping: remember the filename suffix and
    # ensure the existence of the cache directory.
    match_data = /(\.[^.]*)$/.match(image.pathname)
    suffix     = match_data[1]
    FileUtils.mkdir_p image.cache_dir unless File.exist?(image.cache_dir)
    
    # The list of created images are returned as a JSON-encoded list.
    uris  = []
      
    group = IMAGE_GROUPS[params[:group]]
    if group
      # If the user specified a "group"--an access ratio that should exist at
      # one or more fixed sizes, create those images.
      puts ">>>group #{params[:group]}:"
      group.each_key do |size|
        dim = group[size]
        sized_w = dim[:width]
        sized_h = dim[:height]
        puts ">>>    #{size}: #{sized_w}x#{sized_h}"
        cropped_filename = "/thumbnail.width=#{sized_w},height=#{sized_h}#{suffix}"
        cropped_and_sized = cropped.resize_to_fit(sized_w, sized_h)
        cropped_and_sized.write(image.cache_dir + cropped_filename)
        uris << {:size => size, :uri => image.cache_path + cropped_filename}
      end
    else
      # No group, so simply create the image with the requested crop and
      # store that.
      cropped_filename = "/thumbnail.width=#{w},height=#{h}#{suffix}"
      cropped.write(image.cache_dir + cropped_filename)
      uri = image.cache_path + cropped_filename
      sig = md5_signature(uri)
      uris << {:size => 'user-specified', :uri => "#{uri}?sig=#{sig}"}
    end
  
  # "uris" is an array of hashes, which isn't handled correctly by
  #  the "render :json => <something>" construct used in other contexts.
  render :text => uris.to_json
  end

end
