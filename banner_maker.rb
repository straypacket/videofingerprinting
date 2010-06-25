#!/usr/bin/env ruby
###
# Usage: ./banner_maker.rb [WIDTHxHEIGHT] [originalImage.jpg] [text] {overlay-logo.jpg}
###
require 'rubygems'
require 'RMagick'

module Magick
	# Shamefully stolen from http://rmagick.rubyforge.org/web2/web2-4.html
    class Draw
        def star(sides, inner_radius, outer_radius)
            theta = 0.0
            incr = Math::PI * 2.0 / sides
            half_incr = incr / 2.0
            points = []
            sides.times do
                points << outer_radius * Math::cos(theta)
                points << outer_radius * Math::sin(theta)
                points << inner_radius * Math::cos(theta + half_incr)
                points << inner_radius * Math::sin(theta + half_incr)
                theta += incr
            end
            polygon *points
        end
    end

    class Image
        def star(sides, inner_radius, outer_radius, stroke, fill)
            gc = Draw.new
            gc.translate columns/2.0, rows/2.0
            gc.fill fill
            gc.stroke stroke
            gc.star sides, inner_radius, outer_radius
            gc.draw self
        end
    end
end


# Parse arguments
size = ARGV[0].split('x')
bground = ARGV[1]
text = ARGV[2]
logo = ARGV[ARGV.size-1] if ARGV.size == 4
	
size[0] = size[0].to_i
size[1] = size[1].to_i

# Variables
do_reflection = true
do_shadows = false
do_stamp = true
do_logo = false
do_logo = true if ARGV.size == 4
results = Magick::ImageList.new
img = Magick::ImageList.new(bground).resize_to_fill(size[0],size[1],Magick::CenterGravity)
logoImg = Magick::ImageList.new(logo) if do_logo

# Make transparent borders on logo
if do_logo
  # Thresh range [1.0,oo[
  thresh = 1.5
  
  # Pixel 0,0 might not be the best bet, due to logo having a frame
  # Also , if logo is small, too many pixels inside will bring undesirable effects
  # So we will measure the pixel at 5% inside the image top-left corner
  color = logoImg[0].pixel_color((logoImg[0].columns*0.05).to_i, (logoImg[0].rows*0.05).to_i)
  
  high_thresh = [(color.red*thresh).to_i, (color.green*thresh).to_i, (color.blue*thresh).to_i]
  low_thresh = [(color.red/thresh).to_i, (color.green/thresh).to_i, (color.blue/thresh).to_i]

  (0..2).each do |c| 
    high_thresh[c]=65535 if high_thresh[c] > 65535
	high_thresh[c]=0 if high_thresh[c] < 0
	low_thresh[c]=65535 if low_thresh[c] > 65535
	low_thresh[c]=0 if low_thresh[c] < 0
  end
  
  p_low = Magick::Pixel.new(low_thresh[0], low_thresh[1], low_thresh[2])
  p_high = Magick::Pixel.new(high_thresh[0], high_thresh[1], high_thresh[2])
  logoImg[0] = logoImg[0].transparent_chroma(p_low,p_high,Magick::TransparentOpacity)
  
  # resize logo to proper banner size
  reflection = img.wet_floor(0.25) if do_reflection
  logoImg[0] = logoImg[0].resize_to_fit(size[0], size[1]-reflection.rows) if do_reflection
  logoImg[0] = logoImg[0].resize_to_fit(size[0], size[1]) if !do_reflection
  
  border =1
  ##### 1
  ## Logo background + gradient
  fill = Magick::GradientFill.new(logoImg[0].columns, 0, logoImg[0].rows, 0, "gray", "light gray")
  logoImg.new_image((logoImg[0].columns)-(border*2),logoImg[0].rows, fill)
  #####
  
  ##### 2
  stripes = Magick::ImageList.new

  top_grad = Magick::GradientFill.new(logoImg[0].columns, 0, (logoImg[0].rows/2).to_i, 0, "#dddddd", "#888888")
  stripes << Magick::Image.new((logoImg[0].columns)-(border*2),(logoImg[0].rows/2).to_i, top_grad)

  bottom_grad = Magick::GradientFill.new(logoImg[0].columns, 0, (logoImg[0].rows/2).to_i, 0, "#757575", "#555555")
  stripes << Magick::Image.new((logoImg[0].columns)-(border*2),(logoImg[0].rows/2).to_i, bottom_grad)
  
  logoImg[1] = stripes.append(true)
  #####
  
  # Make tint
  color = Magick::Image.new(logoImg[1].columns, logoImg[1].rows) do
         self.background_color = "#87a5ff"
  end
  logoImg[1] = logoImg[1].composite(color, Magick::CenterGravity, Magick::ColorizeCompositeOp)

  # Add borders
  logoImg[1] = logoImg[1].border(border, 0, 'black')
  
end

if ! do_stamp
  # Write text, from left to right. Centering is an estimate to get centered in the "visible/non-reflected" area
  gc = Magick::Draw.new
  gc.annotate(img, 0, 0, (size[1]/6).to_i, (size[1]/4).to_i, text) do
      gc.fill = 'light gray'
	  #gc.stroke = '#000'
      #gc.stroke_width = 1
      gc.font_weight = Magick::BoldWeight
      gc.gravity = Magick::EastGravity
    if RUBY_PLATFORM =~ /mswin32/
      # Estimate to make the font fit in the visible area
      gc.font_family = "Georgia"
      gc.pointsize = size[1]*0.7
    else
      gc.font_family = "times"
      # Again, an estimate to make the font fit in the visible area
      gc.pointsize = size[1]*0.7
    end
  end
end

if do_logo
  logolist = Magick::ImageList.new
  logolist << img.crop(Magick::SouthGravity,img.columns,img.rows-reflection.rows, true)  << logoImg[1] << logoImg[0] if do_reflection
  logolist << img.crop(Magick::SouthGravity,img.columns,img.rows, true)  << logoImg[1] << logoImg[0] if !do_reflection

  img = logolist.flatten_images
end

# Create the reflection
reflection = img.wet_floor(0.25) if do_reflection

# Stack "layers" into an imagelist, cropping the background image to accomodate the reflection
ilist = Magick::ImageList.new
if do_reflection
  ilist << img.crop(Magick::SouthGravity,img.columns,img.rows-reflection.rows, true) if !do_logo
  ilist << img if do_logo
  ilist << reflection
else
  ilist << img
end
results << ilist.append(true)

# Finish montage with all the "layers" in the list
result = results.montage do
    self.geometry = size[0].to_s << 'x' << size[1].to_s
    self.tile = '1x1'
    self.background_color = 'black'
end

# Optional shadowing (on white background)
if do_shadows
  shadow = Magick::Image.new(result.columns+10, result.rows+10)

  gc = Magick::Draw.new
  gc.fill "gray30"
  gc.rectangle 5, 5, result.columns+5, result.rows+5
  gc.draw(shadow)
  shadow = shadow.blur_image(0, 2)
  
  result = shadow.composite(result, Magick::CenterGravity, Magick::OverCompositeOp)
end

# Optional stamp
if do_stamp
  # Estimated value for this size, varies according to image size
  black_star = Magick::Image.new(size[0]/6,size[0]/6)
  black_star.star(25, size[0]/21, size[0]/16, 'none', 'black')
  black_star.rotate!(-20)

  star_shadow = black_star.copy.blur_image(3, 2)
  shadow_mask = star_shadow.negate

  shadow_mask.matte = false
  star_shadow.matte = true
  star_shadow.composite!(shadow_mask, Magick::CenterGravity, Magick::CopyOpacityCompositeOp)
 
  grad = Magick::GradientFill.new(0, 0, black_star.columns, 0, "red", "dark red")
  green_grad = Magick::Image.new(black_star.columns, black_star.rows, grad)

  gc = Magick::Draw.new
  gc.annotate(green_grad, 0, 0, 0, 0, text) do
    gc.gravity = Magick::CenterGravity
    gc.stroke = 'none'
    gc.fill = 'yellow'
	# Estimated value for this, varies according to text
    gc.pointsize = (size[0]/25).to_i
    gc.font_weight = Magick::BoldWeight
  end
  green_grad.rotate!(-20)

  inverse_black_star = black_star.negate

  inverse_black_star.matte = false
  green_grad.matte = true
  green_star = green_grad.composite(inverse_black_star, Magick::CenterGravity, Magick::CopyOpacityCompositeOp)

  shadowed_green_star = star_shadow.composite(green_star, Magick::CenterGravity, Magick::OverCompositeOp)

  # Estimated value for these sizes, they vary according to image size
  result = result.composite(shadowed_green_star, (size[0]*0.8).to_i, -(size[1]*0.2).to_i, Magick::OverCompositeOp)
  
end

# Debug
result.display

# Save image to a file => [bground_filename]_[width]x[height].jpg
result.write(bground.split('.')[0..-2] << "_" << size[0].to_s << 'x' << size[1].to_s << ".jpg")