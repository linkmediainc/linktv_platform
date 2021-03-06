require 'net/scp'
require 'net/ssh'
require 'RMagick'

class Admin::ImagesController < Admin::AdminController

  # Similar to the list in the application's app/models/mobile/summary.rb,
  # but contains web image sizes and the numbers are floating point, not
  # integers.
  IMAGE_DIMENSIONS    = {
    :my_link_story        => {:width => 288.0, :height => 162.0},
    :small_or_related     => {:width => 324.0, :height => 212.0},
    :sidebar_or_doc       => {:width => 324.0, :height => 202.0},
    :medium               => {:width => 324.0, :height => 303.0},
    :x_large              => {:width => 654.0, :height => 443.0},
    :story_video          => {:width => 655.0, :height => 368.0},
    :story_video_list     => {:width => 82.0,  :height => 47.0},
    :story_video_timeline => {:width => 183.0, :height => 103.0},
    :web_x_small          => {:width => 88.0,  :height => 50.0},
    :web_small            => {:width => 192.0, :height => 108.0},
    :web_medium           => {:width => 304.0, :height => 171.0},
    :web_large            => {:width => 624.0, :height => 351.0},
    :web_x_large          => {:width => 640.0, :height => 360.0},
  }
  
  IMAGE_GROUPS = {
    'square'    => {"Home Screen Medium"   => IMAGE_DIMENSIONS[:medium]},
    'landscape' => {"Small/Related Video"  => IMAGE_DIMENSIONS[:small_or_related],
                    "Sidebar/Documentary"  => IMAGE_DIMENSIONS[:sidebar_or_doc],
                    "Lead Story"           => IMAGE_DIMENSIONS[:x_large]},
    '16x9'      => {"Story Video"          => IMAGE_DIMENSIONS[:story_video],
                    "Story Video List"     => IMAGE_DIMENSIONS[:story_video_list],
                    "Story Video Timeline" => IMAGE_DIMENSIONS[:story_video_timeline],
                    "My Link Story"        => IMAGE_DIMENSIONS[:my_link_story],
                    "Web Extra Small"      => IMAGE_DIMENSIONS[:web_x_small],
                    "Web Small"            => IMAGE_DIMENSIONS[:web_small],
                    "Web Medium"           => IMAGE_DIMENSIONS[:web_medium],
                    "Web Large"            => IMAGE_DIMENSIONS[:web_large],
                    "Web Extra Large"      => IMAGE_DIMENSIONS[:web_x_large],
                    }
  }
  
  IMAGE_GROUP_PREFERRED_ASPECT_RATIOS = {'square'    => 324.0 / 303.0,
                                         'landscape' => 654.0 / 443.0,
                                         '16x9'      => 16.0 / 9.0}
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
    # ensure the existence of the cache directory. Normalize the
    # suffix for JPEG images. Sometimes imported filenames have a
    # .jpeg suffix, but the website frequently uses its default,
    # which is .jpg.
    match_data = /(\.[^.]*)$/.match(image.pathname)
    suffix     = match_data[1]
    suffix = '.jpg' if (suffix == '.jpeg')
    
    FileUtils.mkdir_p image.cache_dir unless File.exist?(image.cache_dir)

    
    local_hostname = Socket.gethostname
    remote_server  = nil
    remote_user    = nil
    local_id       = nil

    uris = self.class.create_images(cropped, params[:group],
                                    image.cache_dir, image.cache_path,
                                    suffix, remote_server, remote_user, local_id)

    # "uris" is an array of hashes, which isn't handled correctly by
    #  the "render :json => <something>" construct used in other contexts.
   render :text => uris.to_json

  end

  def show_crops
    @crops = []

    @image_id = params[:id]

    unless @image_id.nil?
      thumbnail = Image.find(@image_id)
      unless thumbnail.nil?
        [['square',    'Home Screen Medium'],
         ['landscape', 'Lead Story'],
         ['16x9',      'Web Extra Large']].each do |x|
          group = x[0]
          size  = x[1]
          dim = IMAGE_GROUPS[group][size]
          filename_glob = filename_for_image_in_group(size, dim[:width], dim[:height], '.*')
          pathglob = Dir.glob("#{thumbnail.cache_dir}#{filename_glob}")
          if pathglob.empty?
            url  = ""
            path = ""
          else
            filename = File.basename pathglob[0]
            url  = "#{thumbnail.cache_path}/#{filename}"
            path = "#{thumbnail.cache_dir}/#{filename}"
          end
          @crops << {:group => group, :url => url, :path => path}
        end
      end
    end

    respond_to do |format|
      format.html { render :layout => 'show_crops'}
    end

  end

  private
  
  def self.make_remote_path(orig)
  
    # Make sure the destination path is in the newspro user's directory. During
    # testing, the copy is is going to be from newsdev to newspro. In live
    # production, the servers have a common user name so this transformation is
    # not needed.
    dst = orig.gsub(/newsdev/, 'newspro')

    # And another transformation to take into account that the servers may not be
    # running out of the same deployment directory. Transform the path component
    # that names a specific directory into the generic symlink.
    dst.gsub!(/releases\/\d+\//, 'live_production/')

    dst
  end  

  def filename_for_image_in_group(size, w, h, suffix)

        extra_args = (size =~ /^Web/) ? ',grow=1,crop=center' : ''
        cropped_filename = "/thumbnail.width=#{w.to_i},height=#{h.to_i}#{extra_args}#{suffix}"
  end

  def self.copy_to_remote(remote_server, remote_user, local_id, src)
    
    return if (remote_server.nil? || remote_user.nil? || local_id.nil?)
    begin
      dst = Admin::ImagesController.make_remote_path(src)
      Net::SCP.start(remote_server, remote_user, :keys => [local_id]) do |scp|
          logger.error "src: #{src}\ndst: #{dst}"
          scp.upload!(src, dst)
      end
    rescue Net::SCP::Error => error
      logger.error "#{error}\nserver: #{remote_server}\nuser: #{remote_user}\nsrc: #{src}\ndst: #{dst}"
    rescue Errno => error
      logger.error "#{error}"
    end
      
  end

  def self.create_images(cropped, group_name, cache_dir, cache_path, suffix, remote_server, remote_user, local_id)

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
        # The to_i is important, because the dimensions in the image URIs
        # (generated by the mobile models are always integers)
        
        # We want web image URLs to match the URLs already sent by the server.
        # This allows images to have the same URL whether they were cropped
        # administratively or have a default cropping and requires no change
        # to the existing web code. For the app, the same flexibility would have
        # been nice, but the aspect ratios are numerous and non-standard. Attempts
        # at getting a good default crop out of the existing ThumbnailGenerator
        # mechanism were unsuccessful.
        #
        # Another note, the order for the arguments in images for the web is
        # is defined in linktv_platform/app/helpers/images_helper.rb (in the
        # thumbnail_url method). The order specified here is the same, so that
        # administratively cropped images can replace auto-generated ones, or
        # prevent their creation.
        extra_args = (size =~ /^Web/) ? ',grow=1,crop=center' : ''
        cropped_filename = "/thumbnail.width=#{sized_w.to_i},height=#{sized_h.to_i}#{extra_args}#{suffix}"
        uris << {:size => size, :uri => cache_path + cropped_filename}

        cur_aspect_ratio = (sized_w / sized_h)

        if cur_aspect_ratio < group_aspect_ratio

          # The current is taller than the preferred aspect ratio.
          # Resize to slightly wider than current (preserving aspect
          # ratio), then cut off excess from sides.
          resized = cropped.change_geometry("x#{sized_h}") do |cols, rows, img|
            img.resize(cols, rows)
          end

          # Need to write out the intermediate result, because
          # RMagick performs the second crop incorrectly.
          tmp_filename = cache_dir + "tmp.jpg" 
          resized.write(tmp_filename)
          t = Magick::ImageList.new(tmp_filename)
          t.crop!(Magick::NorthGravity, sized_w, t.rows)
          cropped_path = cache_dir + cropped_filename
          t.write(cropped_path)

        elsif cur_aspect_ratio > group_aspect_ratio

          # The current is wider than the preferred aspect ratio.
          # Resize to slightly taller than current (preserving aspect
          # ratio), then cut off excess from top and bottom.
          resized = cropped.change_geometry("#{sized_w}x") do |cols, rows, img|
            img.resize(cols, rows)
          end

          # Need to write out the intermediate result, because
          # RMagick performs the second crop incorrectly.
          tmp_filename = cache_dir + "tmp.jpg" 
          resized.write(tmp_filename)
          t = Magick::ImageList.new(tmp_filename)
          t.crop!(Magick::NorthGravity, t.columns, sized_h)

          cropped_path = cache_dir + cropped_filename
          t.write(cropped_path)

        else 
          # The aspect ratio is the preferred one. A simple resize
          # suffices in this case.
          cropped_and_sized = cropped.resize(sized_w, sized_h)
          cropped_path = cache_dir + cropped_filename
          cropped_and_sized.write(cropped_path)

        end

      end
    else
      # No group, so simply create the image with the requested crop and
      # store that. The dimensions are already integers, via to_i. Note that
      # this path is only for testing: it does not add in any of the cropping
      # parameters that will be sent by the app or the web.
      cropped_filename = "/thumbnail.width=#{w},height=#{h}#{suffix}"
      cropped_path = cache_dir + cropped_filename
      cropped.write(cropped_path)

      uri = cache_path + cropped_filename
      sig = md5_signature(uri)
      uris << {:size => 'user-specified', :uri => "#{uri}?sig=#{sig}"}
    end

  uris
  end

end
