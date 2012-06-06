require 'RMagick'

class Admin::ImagesController < Admin::AdminController

  # Not DRY: copied from the applications app/models/mobile/summary.rb,
  # but should be defined in the plugin, somewhere.
  IMAGE_DIMENSIONS    = {
    :small_or_related     => {:width =>324.0, :height =>212.0},
    :sidebar_or_doc       => {:width =>324.0, :height =>202.0},
    :medium               => {:width =>324.0, :height =>303.0},
    :x_large              => {:width =>654.0, :height =>443.0},
    :story_video          => {:width =>655.0, :height =>368.0},
    :story_video_list     => {:width =>82.0,  :height =>47.0},
    :story_video_timeline => {:width =>183.0, :height =>103.0},
  }
  
  IMAGE_GROUPS = {
    'square'    => {"Home Screen Medium"   => IMAGE_DIMENSIONS[:medium]},
    'landscape' => {"Small/Related Video"  => IMAGE_DIMENSIONS[:small_or_related],
                    "Sidebar/Documentary"  => IMAGE_DIMENSIONS[:sidebar_or_doc],
                    "Lead Story"           => IMAGE_DIMENSIONS[:x_large]},
    '16x9'      => {"Story Video"          => IMAGE_DIMENSIONS[:story_video],
                    "Story Video List"     => IMAGE_DIMENSIONS[:story_video_list],
                    "Story Video Timeline" => IMAGE_DIMENSIONS[:story_video_timeline]}
  }
  
  IMAGE_GROUP_PREFERRED_ASPECT_RATIOS = {'square' => 324.0 / 303.0,
                                         'landscape' => 654.0 / 443.0,
                                         '16x9'        => 16.0 / 9.0}
  RATIO_LEAD_STORY = 654.0 / 443.0
  RATIO_16x9       = 16.0 / 9.0 
  
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
    
    uris = self.class.create_images(cropped, params[:group],
                                    image.cache_dir, image.cache_path,
                                    suffix)
  
    # "uris" is an array of hashes, which isn't handled correctly by
    #  the "render :json => <something>" construct used in other contexts.
   render :text => uris.to_json
   
  end

  private

  def self.create_images(cropped, group_name, cache_dir, cache_path, suffix)

    # The list of created images are returned as a JSON-encoded list.
    uris  = []

    group              = IMAGE_GROUPS[group_name]
    group_aspect_ratio = IMAGE_GROUP_PREFERRED_ASPECT_RATIOS[group_name]
    if group
      # If the user specified a "group"--an access ratio that should exist at
      # one or more fixed sizes, create those images.
      puts ">>>group #{group_name}"
      group.each_key do |size|
        # Get the eventual sizes used in the layout and save the
        # URI. Fitting the user's crop into these dimensions will
        # be done in two steps below.
        dim = group[size]
        sized_w = dim[:width]
        sized_h = dim[:height]
        cropped_filename = "/thumbnail.width=#{sized_w},height=#{sized_h}#{suffix}"
        uris << {:size => size, :uri => cache_path + cropped_filename}

        cur_aspect_ratio = (sized_w / sized_h)

        if cur_aspect_ratio < group_aspect_ratio

          # The current is taller than the preferred aspect ratio.
          # Resize to slightly wider than current (preserving aspect
          # ratio), then cut off excess from sides.
          resized = cropped.change_geometry("x#{sized_h}") do |cols, rows, img|
            img.resize!(cols, rows)
          end

          # Need to write out the intermediate result, because
          # RMagick performs the second crop incorrectly.
          tmp_filename = cache_dir + "tmp.jpg" 
          resized.write(tmp_filename)
          t = Magick::ImageList.new(tmp_filename)
          t.crop!(Magick::NorthGravity, sized_w, t.rows)
          t.write(cache_dir + cropped_filename)

        elsif cur_aspect_ratio > group_aspect_ratio

          # The current is wider than the preferred aspect ratio.
          # Resize to slightly taller than current (preserving aspect
          # ratio), then cut off excess from top and bottom.
          resized = cropped.change_geometry("#{sized_w}x") do |cols, rows, img|
            img.resize!(cols, rows)
          end

          # Need to write out the intermediate result, because
          # RMagick performs the second crop incorrectly.
          tmp_filename = cache_dir + "tmp.jpg" 
          resized.write(tmp_filename)
          t = Magick::ImageList.new(tmp_filename)
          t.crop!(Magick::NorthGravity, t.columns, sized_h)
          t.write(cache_dir + cropped_filename)

        else 
          # The aspect ratio is the preferred one. A simple resize
          # suffices in this case.
          cropped_and_sized = cropped.resize(sized_w, sized_h)
          cropped_and_sized.write(cache_dir + cropped_filename)
        end

      end
    else
      # No group, so simply create the image with the requested crop and
      # store that.
      cropped_filename = "/thumbnail.width=#{w},height=#{h}#{suffix}"
      cropped.write(cache_dir + cropped_filename)
      uri = cache_path + cropped_filename
      sig = md5_signature(uri)
      uris << {:size => 'user-specified', :uri => "#{uri}?sig=#{sig}"}
    end

  uris
  end

end
