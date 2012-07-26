jQuery(function($) {

  const MIN_NONE      = [0, 0]

  const RATIO_SQUARE    = (324 / 303) // strictly speaking, not really.
  const MIN_SQUARE      = [324, 303]
  const RATIO_4x3       = (4 / 3)
  const MIN_4x3         = MIN_NONE   // Might change if 4x3 gets used.
  const RATIO_LANDSCAPE = (654 / 443)
  const MIN_LANDSCAPE   = [654/2, 443/2]
  const RATIO_16x9      = (16 / 9)
  const MIN_16x9        = [655/2, 368/2]
  const MAX_W_IN_TOOL   = 1024

  var jcrop_api, x, y, w, h, group, cur_aspect_ratio, cur_min_size;

  getConstraintsForCurCrop()
   
  // This is the image that JCrop will operate on.
  $('#original').Jcrop({
	// The initial option settings.
    onSelect: updateCropDimensions,
    onRelease: disableCropButton,
    onDblClick: performCrop,
    aspectRatio: cur_aspect_ratio,
    minSize: cur_min_size,
	boxWidth: MAX_W_IN_TOOL
  }, function() {
    // This is the "ready" callback for JCrop.
    jcrop_api = this;
  });

  // Used in two different scenarios: setting up the initial
  // constraints, and whenever the user selects a different
  // crop setting.
  function getConstraintsForCurCrop()
  {
	  cropId = $('input:radio[name=group]:checked').attr('id')

     // This is by convention. The button IDs must match 
     // the "groups" defined in the server.
      group = cropId

      switch (cropId)
      {
      case '4x3':
          // Not used by News app
          cur_aspect_ratio = RATIO_4x3;
          cur_min_size     = MIN_4x3;
          break;

      case 'square':
          cur_aspect_ratio = RATIO_SQUARE;
          cur_min_size     = MIN_SQUARE;
          break;

      case 'landscape':
          cur_aspect_ratio = RATIO_LANDSCAPE;
          cur_min_size     = MIN_LANDSCAPE;
          break;

      case '16x9':
          cur_aspect_ratio = RATIO_16x9;
          cur_min_size     = MIN_16x9;
	      break;
	
      default:
          cur_aspect_ratio = 0;
          cur_min_size     = MIN_NONE;
      }

  }

  function updateCropDimensions (c)
  {
	
    if (parseInt(c.w) > 0)
    {
        x = c.x;
	    y = c.y;
	    w = c.w;
	    h = c.h;
	   $('#crop').removeAttr('disabled')
    }

  };

  function disableCropButton()
  {
       $('#crop').attr('disabled', 'true')
  }

  function performCrop() {
	console.log(w + " " + h + " " + group)

    jQuery.post("/admin/images/" + $('#crop').attr('image_id') + "/crop",
     { x: x, y: y, w: w, h: h, group: group},
     function (data, textStatus, jqXHR)
     {
		$('#results').html('')
	      div_text = ""
		  images = JSON.parse(data)
		  for (i = 0; i < images.length; i++)
		  {
			div_text += ("<h3 class=\"top-margin\">" + images[i].size + "</h3>" +
			            "<img src=\"" + images[i].uri + "\"/><br>" +
						images[i].uri + "<br>")
        }
        $('#results').html(div_text)
     });

	jcrop_api.release()

  }

  $('#square').click(
	function() {
		
		// The dimensions below are the exact size of the
		// related video image in the mobile app. It's
		// expressed as an aspect ratio for flexibility.
		jcrop_api.release();
		getConstraintsForCurCrop()
		jcrop_api.setOptions({aspectRatio: cur_aspect_ratio,
			                  minSize: cur_min_size});
  
    });

  $('#landscape').click(
	function() {
		// This ratio is used at several sizes.
		jcrop_api.release();
		getConstraintsForCurCrop()
		jcrop_api.setOptions({aspectRatio: cur_aspect_ratio,
			                  minSize: cur_min_size});
    
    });

  $('#16x9').click(
	function() {
		// This ratio is used at several sizes.
		jcrop_api.release();
		getConstraintsForCurCrop()
		jcrop_api.setOptions({aspectRatio: cur_aspect_ratio,
			                  minSize: cur_min_size});

    });

  $('#crop').click(performCrop);

});
