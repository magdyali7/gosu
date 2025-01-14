#!/usr/bin/env ruby

if RUBY_PLATFORM =~ /mswin$|mingw32|mingw64|win32\-|\-win32/ then
  platform = (RUBY_PLATFORM =~ /^x64-/ ? 'x64-mingw32' : 'i386-mingw32')
  
  puts "This gem is not meant to be installed on Windows. Instead, please use:"
  puts "gem install gosu --platform=#{platform}"
  exit 1
end

puts 'The Gosu gem requires some libraries to be installed system-wide.'
puts 'See the following site for a list:'
if `uname`.chomp == "Darwin" then
  puts 'https://github.com/jlnr/gosu/wiki/Getting-Started-on-OS-X'
else
  puts 'https://github.com/jlnr/gosu/wiki/Getting-Started-on-Linux'
end
puts

BASE_FILES = %w(
  Bitmap/Bitmap.cpp
  Bitmap/BitmapIO.cpp
  DirectoriesUnix.cpp
  FileUnix.cpp
  Graphics/BlockAllocator.cpp
  Graphics/Color.cpp
  Graphics/Graphics.cpp
  Graphics/Image.cpp
  Graphics/LargeImageData.cpp
  Graphics/Macro.cpp
  Graphics/Resolution.cpp
  Graphics/TexChunk.cpp
  Graphics/Texture.cpp
  Graphics/Transform.cpp
  Input/Input.cpp
  Input/TextInput.cpp
  Inspection.cpp
  IO.cpp
  Math.cpp
  Text/Font.cpp
  Text/Text.cpp
  Utility.cpp
  Window.cpp
  
  stb_vorbis.c
)

MAC_FILES = %w(
  Audio/Audio.mm
  Graphics/ResolutionApple.mm
  Text/TextApple.mm
  TimingApple.cpp
  UtilityApple.mm
)

LINUX_FILES = %w(
  Audio/Audio.cpp
  Text/TextUnix.cpp
  TimingUnix.cpp
)

require 'mkmf'
require 'fileutils'

# Silence internal deprecation warnings in Gosu
$CFLAGS << " -DGOSU_DEPRECATED="
$CXXFLAGS ||= ''

$INCFLAGS << " -I../.. -I../../src"

if `uname`.chomp == 'Darwin' then
  HOMEBREW_DEPENDENCIES = %w(SDL2)
  FRAMEWORKS = %w(AppKit ApplicationServices AudioToolbox Carbon ForceFeedback Foundation IOKit OpenAL OpenGL)

  SOURCE_FILES = BASE_FILES + MAC_FILES
  
  # To make everything work with the Objective C runtime
  $CFLAGS    << " -x objective-c -DNDEBUG"
  # Compile all C++ files as Objective C++ on OS X since mkmf does not support .mm
  # files.
  # Also undefine two debug flags that cause exceptions to randomly crash, see:
  # https://trac.macports.org/ticket/27237#comment:21
  # http://newartisans.com/2009/10/a-c-gotcha-on-snow-leopard/#comment-893
  $CXXFLAGS << " -x objective-c++ -U_GLIBCXX_DEBUG -U_GLIBCXX_DEBUG_PEDANTIC"

  # Enable C++ 11 on Mavericks and above.
  if `uname -r`.to_i >= 13 then
    $CXXFLAGS << " -std=gnu++11"
    
    # rvm-specific fix:
    # Explicitly set libc++ as the C++ standard library. Otherwise the gem will
    # end up being compiled against libstdc++, but linked against libc++, and
    # fail to load, see: https://github.com/shawn42/gamebox/issues/96
    $CXXFLAGS << " -stdlib=libc++"
  end
  
  # Dependencies...
  $CXXFLAGS << " #{`sdl2-config --cflags`.chomp}"
  $LDFLAGS  << " -liconv"
  
  if enable_config('static-homebrew-dependencies') then
    # TODO: For some reason this only works after deleting both SDL2 dylib files from /usr/local/lib.
    # Otherwise, the resulting gosu.bundle is still dependent on libSDL2-2.0.0.dylib, see `otool -L gosu.bundle`
    $LDFLAGS << HOMEBREW_DEPENDENCIES.map { |lib| " /usr/local/lib/lib#{lib}.a" }.join
  else
    $LDFLAGS << " #{`sdl2-config --libs`.chomp}"
  end

  $LDFLAGS << FRAMEWORKS.map { |f| " -framework #{f}" }.join
else
  SOURCE_FILES = BASE_FILES + LINUX_FILES

  if /Raspbian/ =~ `cat /etc/issue` or /BCM2708/ =~ `cat /proc/cpuinfo` then
    $INCFLAGS << " -I/opt/vc/include/GLES"
    $INCFLAGS << " -I/opt/vc/include"
    $LDFLAGS  << " -L/opt/vc/lib"
    $LDFLAGS  << " -lGLESv1_CM"
  else
    pkg_config 'gl'
  end

  pkg_config 'sdl2'
  pkg_config 'pangoft2'
  pkg_config 'vorbisfile'
  pkg_config 'openal'
  pkg_config 'sndfile'
  
  have_header 'SDL_ttf.h'   if have_library('SDL2_ttf', 'TTF_RenderUTF8_Blended')
  have_header 'AL/al.h'     if have_library('openal')
end

# And now it gets ridiculous (or I am overcomplicating things...):
# mkmf will compile all .c/.cpp files in this directory, but if they are nested
# inside folders, it will not find the resulting .o files during linking.
# So we create a shim .c/.cpp file for each file that we want to compile, ensuring
# that all .o files are built into the current directory, without any nesting.
# TODO - would be nicer if the Rakefile would just create these shim files and
# ship them along with the gem
SOURCE_FILES.each do |file|
  shim_name = file.gsub('/', '-').sub(/\.mm$/, '.cpp')
  File.open(shim_name, "w") do |shim|
    shim.puts "#include \"../../src/#{file}\""
  end
end

if RUBY_VERSION >= '2.0.0' then
  # In some versions of Ruby 2.x, the $CXXFLAGS variable is ignored, and $CLAGS
  # are not being inherited into it either. In these versions of Ruby we can
  # modify CONFIG instead, and our changes will end up in the Makefile.
  # See http://bugs.ruby-lang.org/issues/8315
  CONFIG['CXXFLAGS'] = "#$CFLAGS #$CXXFLAGS"
end

create_makefile 'gosu'
