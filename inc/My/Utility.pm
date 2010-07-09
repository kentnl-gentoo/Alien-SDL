package My::Utility;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(check_config_script check_prebuilt_binaries check_prereqs_libs check_src_build find_SDL_dir find_file check_header sed_inplace get_dlext);
use Config;
use ExtUtils::CBuilder;
use File::Spec::Functions qw(splitdir catdir splitpath catpath rel2abs);
use File::Find qw(find);
use File::Copy qw(cp);
use Cwd qw(realpath);

#### packs with prebuilt binaries
# - all regexps has to match: arch_re ~ $Config{archname}, cc_re ~ $Config{cc}, os_re ~ $^O
# - the order matters, we offer binaries to user in the same order (1st = preffered)
my $prebuilt_binaries = [
    {
      title    => "Binaries Win/32bit SDL-1.2.14 (extended, 20100704) RECOMMENDED\n" .
                  "\t(gfx, image, mixer, net, smpeg, ttf, sound, svg, rtf, Pango)",
      url      => [
        'http://strawberryperl.com/package/kmx/sdl/Win32_SDL-1.2.14-extended-bin_20100704.zip',
        'http://froggs.de/libsdl/Win32_SDL-1.2.14-extended-bin_20100704.zip',
      ],
      sha1sum  => '98409ddeb649024a9cc1ab8ccb2ca7e8fe804fd8',
      arch_re  => qr/^MSWin32-x86-multi-thread$/,
      os_re    => qr/^MSWin32$/,
      cc_re    => qr/gcc/,
    },
    {
      title    => "Binaries Win/32bit SDL-1.2.14 (20090831)\n" .
                  "\t(gfx, image, mixer, net, smpeg, ttf)",
      url      => [
        'http://strawberryperl.com/package/kmx/sdl/lib-SDL-bin_win32_v2.zip',
        'http://froggs.de/libsdl/lib-SDL-bin_win32_v2.zip',
      ],
      sha1sum  => 'eaeeb96b0115462f6736de568de8ec233a2397a5',
      arch_re  => qr/^MSWin32-x86-multi-thread$/,
      os_re    => qr/^MSWin32$/,
      cc_re    => qr/gcc/,
    },
    {
      title    => "Binaries Win/64bit SDL-1.2.14 (extended, 20100704) RECOMMENDED\n" .
                  "\t(gfx, image, mixer, net, smpeg, ttf, sound, svg, rtf, Pango)",
      url      => [
        'http://strawberryperl.com/package/kmx/sdl/Win64_SDL-1.2.14-extended-bin_20100704.zip',	
        'http://froggs.de/libsdl/Win64_SDL-1.2.14-extended-bin_20100704.zip',
      ],
      sha1sum  => 'f23a189867865729756b9e882b3dd32b628819c9',
      arch_re  => qr/^MSWin32-x64-multi-thread$/,
      os_re    => qr/^MSWin32$/,
      cc_re    => qr/gcc/,
    },
 ];

#### tarballs with source codes
my $source_packs = [
## the first set for source code build will be a default option
  {
    title   => "Source code build: SDL-1.2.14 & co. (RECOMMENDED)\n" .
               "\tbuilds: SDL, SDL_(image|mixer|ttf|net|gfx|Pango)\n" .
               "\tneeds preinstalled: (freetype2|pango)-devel\n" .
               "\tNOTE: uses unofficial SDL_ttf-2.0.10!!!",
    prereqs => {
        libs => [
          'pthread', # SDL
          'pangoft2', 'pango', 'gobject', 'gmodule', 'glib', 'fontconfig', 'freetype', 'expat', # SDL_Pango
        ]
    },
    members     => [
      {
        pack => 'zlib',
        dirname => 'zlib-1.2.5',
        url => [
          'http://zlib.net/zlib-1.2.5.tar.gz',
          'http://froggs.de/libz/zlib-1.2.5.tar.gz',
        ],
        sha1sum  => '8e8b93fa5eb80df1afe5422309dca42964562d7e',
      },
      {
        pack => 'SDL',
        dirname => 'SDL-1.2.14',
        url => [
          'http://www.libsdl.org/release/SDL-1.2.14.tar.gz',
          'http://froggs.de/libsdl/SDL-1.2.14.tar.gz',
        ],
        sha1sum  => 'ba625b4b404589b97e92d7acd165992debe576dd',
        patches => [
          'test1.patch',
        ],
      },
      {
        pack => 'jpeg',
        dirname => 'jpeg-8a',
        url => [
          'http://www.ijg.org/files/jpegsrc.v8a.tar.gz',
          'http://froggs.de/libjpeg/jpegsrc.v8a.tar.gz',
        ],
        sha1sum  => '78077fb22f0b526a506c21199fbca941d5c671a9',
        patches => [ 'jpeg-8a_cygwin.patch' ],
      },
      {
        pack => 'tiff',
        dirname => 'tiff-3.9.1',
        url => [
          'http://froggs.de/libtiff/tiff-3.9.1.tar.gz',
          'ftp://ftp.remotesensing.org/pub/libtiff/tiff-3.9.1.tar.gz',
        ],
        sha1sum  => '675ad1977023a89201b80cd5cd4abadea7ba0897',
        patches => [ ],
      },
      {
        pack => 'png',
        dirname => 'libpng-1.4.1',
        url => [
          'http://downloads.sourceforge.net/libpng/libpng-1.4.1.tar.gz',
          'http://froggs.de/libpng/libpng-1.4.1.tar.gz',
        ],
        sha1sum  => '7a3488f5844068d67074f2507dd8a7ed9c69ff04',
      },
      {
        pack => 'SDL_image',
        dirname => 'SDL_image-1.2.10',
        url => [
          'http://www.libsdl.org/projects/SDL_image/release/SDL_image-1.2.10.tar.gz',
          'http://froggs.de/libsdl/SDL_image-1.2.10.tar.gz',
        ],
        sha1sum  => '6bae71fdfd795c3dbf39f6c7c0cf8b212914ef97',
        patches => [ ],
      },
      {
        pack => 'SDL_mixer',
        dirname => 'SDL_mixer-1.2.11',
        url => [
          'http://www.libsdl.org/projects/SDL_mixer/release/SDL_mixer-1.2.11.tar.gz',
          'http://froggs.de/libsdl/SDL_mixer-1.2.11.tar.gz',
        ],
        sha1sum  => 'ef5d45160babeb51eafa7e4019cec38324ee1a5d',
        patches => [ ],
      },
      {
        pack => 'SDL_ttf',
        dirname => 'SDL_ttf-2.0.10',
        url => [
          'http://www.libsdl.org/tmp/SDL_ttf/release/SDL_ttf-2.0.10.tar.gz',
          'http://froggs.de/libsdl/SDL_ttf-2.0.10.tar.gz',
        ],
        sha1sum  => '98f6518ec71d94b8ad303a197445e0991850b887',
        patches => [ ],
      },
      {
        pack => 'SDL_net',
        dirname => 'SDL_net-1.2.7',
        url => [
          'http://www.libsdl.org/projects/SDL_net/release/SDL_net-1.2.7.tar.gz',
          'http://froggs.de/libsdl/SDL_net-1.2.7.tar.gz',
        ],
        sha1sum  => 'b46c7e3221621cc34fec1238f1b5f0ce8972274d',
        patches => [ ],
      },
      {
        pack => 'SDL_gfx',
        dirname => 'SDL_gfx-2.0.20',
        url => [
          'http://www.ferzkopp.net/Software/SDL_gfx-2.0/SDL_gfx-2.0.20.tar.gz',
          'http://froggs.de/libsdl/SDL_gfx-2.0.20.tar.gz',
        ],
        sha1sum  => '077f7e64376c50a424ef11a27de2aea83bda3f78',
        patches => [ ],
      },
      {
        pack => 'SDL_Pango',
        dirname => 'SDL_Pango-0.1.2',
        url => [
          'http://downloads.sourceforge.net/sdlpango/SDL_Pango-0.1.2.tar.gz',
          'http://froggs.de/libsdl/SDL_Pango-0.1.2.tar.gz',
        ],
        sha1sum  => 'c30f2941d476d9362850a150d29cb4a93730af68',
        patches => [
          'SDL_Pango-0.1.2-API-adds.1.patch',
          'SDL_Pango-0.1.2-API-adds.2.patch',
        ],
      },
    ],
  },
## another src build set (without PANGO SUPPORT)
  {
    title   => "Source code build: SDL-1.2.14 & co. (no PANGO, but TTF)\n" .
               "\tbuilds: SDL, SDL_(image|mixer|ttf|net|gfx)\n" .
               "\tneeds preinstalled: freetype2-devel",
    prereqs => {
        libs => [
          'pthread',  # SDL
          'freetype', # SDL_ttf
        ]
    },
    members     => [
      {
        pack => 'SDL',
        dirname => 'SDL-1.2.14',
        url => [
          'http://www.libsdl.org/release/SDL-1.2.14.tar.gz',
          'http://froggs.de/libsdl/SDL-1.2.14.tar.gz',
        ],
        sha1sum  => 'ba625b4b404589b97e92d7acd165992debe576dd',
        patches => [
          'test1.patch',
        ],
      },
      {
        pack => 'zlib',
        dirname => 'zlib-1.2.5',
        url => [
          'http://zlib.net/zlib-1.2.5.tar.gz',
          'http://froggs.de/libz/zlib-1.2.5.tar.gz',
        ],
        sha1sum  => '8e8b93fa5eb80df1afe5422309dca42964562d7e',
      },
      {
        pack => 'jpeg',
        dirname => 'jpeg-8a',
        url => [
          'http://www.ijg.org/files/jpegsrc.v8a.tar.gz',
          'http://froggs.de/libjpeg/jpegsrc.v8a.tar.gz',
        ],
        sha1sum  => '78077fb22f0b526a506c21199fbca941d5c671a9',
        patches => [ 'jpeg-8a_cygwin.patch' ],
      },
      {
        pack => 'tiff',
        dirname => 'tiff-3.9.1',
        url => [
          'http://froggs.de/libtiff/tiff-3.9.1.tar.gz',
          'ftp://ftp.remotesensing.org/pub/libtiff/tiff-3.9.1.tar.gz',
        ],
        sha1sum  => '675ad1977023a89201b80cd5cd4abadea7ba0897',
        patches => [ ],
      },
      {
        pack => 'png',
        dirname => 'libpng-1.4.1',
        url => [
          'http://downloads.sourceforge.net/libpng/libpng-1.4.1.tar.gz',
          'http://froggs.de/libpng/libpng-1.4.1.tar.gz',
        ],
        sha1sum  => '7a3488f5844068d67074f2507dd8a7ed9c69ff04',
      },
      {
        pack => 'SDL_image',
        dirname => 'SDL_image-1.2.10',
        url => [
          'http://www.libsdl.org/projects/SDL_image/release/SDL_image-1.2.10.tar.gz',
          'http://froggs.de/libsdl/SDL_image-1.2.10.tar.gz',
        ],
        sha1sum  => '6bae71fdfd795c3dbf39f6c7c0cf8b212914ef97',
        patches => [ ],
      },
      {
        pack => 'SDL_mixer',
        dirname => 'SDL_mixer-1.2.11',
        url => [
          'http://www.libsdl.org/projects/SDL_mixer/release/SDL_mixer-1.2.11.tar.gz',
          'http://froggs.de/libsdl/SDL_mixer-1.2.11.tar.gz',
        ],
        sha1sum  => 'ef5d45160babeb51eafa7e4019cec38324ee1a5d',
        patches => [ ],
      },
      {
        pack => 'SDL_ttf',
        dirname => 'SDL_ttf-2.0.9',
        url => [
          'http://www.libsdl.org/projects/SDL_ttf/release/SDL_ttf-2.0.9.tar.gz',
          'http://froggs.de/libsdl/SDL_ttf-2.0.9.tar.gz',
        ],
        sha1sum  => '6bc3618b08ddbbf565fe8f63f624782c15e1cef2',
        patches => [ ],
      },
      {
        pack => 'SDL_net',
        dirname => 'SDL_net-1.2.7',
        url => [
          'http://www.libsdl.org/projects/SDL_net/release/SDL_net-1.2.7.tar.gz',
          'http://froggs.de/libsdl/SDL_net-1.2.7.tar.gz',
        ],
        sha1sum  => 'b46c7e3221621cc34fec1238f1b5f0ce8972274d',
        patches => [ ],
      },
      {
        pack => 'SDL_gfx',
        dirname => 'SDL_gfx-2.0.20',
        url => [
          'http://www.ferzkopp.net/Software/SDL_gfx-2.0/SDL_gfx-2.0.20.tar.gz',
          'http://froggs.de/libsdl/SDL_gfx-2.0.20.tar.gz',
        ],
        sha1sum  => '077f7e64376c50a424ef11a27de2aea83bda3f78',
        patches => [ ],
      },
    ],
  },
## another src build set (without PANGO/TTF SUPPORT)
  {
    title   => "Source code build: SDL-1.2.14 & co. (no PANGO, no TTF)\n" .
               "\tbuilds: SDL, SDL_(image|mixer|net|gfx)",
    prereqs => {
        libs => [
          'pthread',  # SDL
        ]
    },
    members     => [
      {
        pack => 'SDL',
        dirname => 'SDL-1.2.14',
        url => [
          'http://www.libsdl.org/release/SDL-1.2.14.tar.gz',
          'http://froggs.de/libsdl/SDL-1.2.14.tar.gz',
        ],
        sha1sum  => 'ba625b4b404589b97e92d7acd165992debe576dd',
        patches => [
          'test1.patch',
        ],
      },
      {
        pack => 'zlib',
        dirname => 'zlib-1.2.5',
        url => [
          'http://zlib.net/zlib-1.2.5.tar.gz',
          'http://froggs.de/libz/zlib-1.2.5.tar.gz',
        ],
        sha1sum  => '8e8b93fa5eb80df1afe5422309dca42964562d7e',
      },
      {
        pack => 'jpeg',
        dirname => 'jpeg-8a',
        url => [
          'http://www.ijg.org/files/jpegsrc.v8a.tar.gz',
          'http://froggs.de/libjpeg/jpegsrc.v8a.tar.gz',
        ],
        sha1sum  => '78077fb22f0b526a506c21199fbca941d5c671a9',
        patches => [ 'jpeg-8a_cygwin.patch' ],
      },
      {
        pack => 'tiff',
        dirname => 'tiff-3.9.1',
        url => [
          'http://froggs.de/libtiff/tiff-3.9.1.tar.gz',
          'ftp://ftp.remotesensing.org/pub/libtiff/tiff-3.9.1.tar.gz',
        ],
        sha1sum  => '675ad1977023a89201b80cd5cd4abadea7ba0897',
        patches => [ ],
      },
      {
        pack => 'png',
        dirname => 'libpng-1.4.1',
        url => [
          'http://downloads.sourceforge.net/libpng/libpng-1.4.1.tar.gz',
          'http://froggs.de/libpng/libpng-1.4.1.tar.gz',
        ],
        sha1sum  => '7a3488f5844068d67074f2507dd8a7ed9c69ff04',
      },
      {
        pack => 'SDL_image',
        dirname => 'SDL_image-1.2.10',
        url => [
          'http://www.libsdl.org/projects/SDL_image/release/SDL_image-1.2.10.tar.gz',
          'http://froggs.de/libsdl/SDL_image-1.2.10.tar.gz',
        ],
        sha1sum  => '6bae71fdfd795c3dbf39f6c7c0cf8b212914ef97',
        patches => [ ],
      },
      {
        pack => 'SDL_mixer',
        dirname => 'SDL_mixer-1.2.11',
        url => [
          'http://www.libsdl.org/projects/SDL_mixer/release/SDL_mixer-1.2.11.tar.gz',
          'http://froggs.de/libsdl/SDL_mixer-1.2.11.tar.gz',
        ],
        sha1sum  => 'ef5d45160babeb51eafa7e4019cec38324ee1a5d',
        patches => [ ],
      },
      {
        pack => 'SDL_net',
        dirname => 'SDL_net-1.2.7',
        url => [
          'http://www.libsdl.org/projects/SDL_net/release/SDL_net-1.2.7.tar.gz',
          'http://froggs.de/libsdl/SDL_net-1.2.7.tar.gz',
        ],
        sha1sum  => 'b46c7e3221621cc34fec1238f1b5f0ce8972274d',
        patches => [ ],
      },
      {
        pack => 'SDL_gfx',
        dirname => 'SDL_gfx-2.0.20',
        url => [
          'http://www.ferzkopp.net/Software/SDL_gfx-2.0/SDL_gfx-2.0.20.tar.gz',
          'http://froggs.de/libsdl/SDL_gfx-2.0.20.tar.gz',
        ],
        sha1sum  => '077f7e64376c50a424ef11a27de2aea83bda3f78',
        patches => [ ],
      },
    ],
  },
## another src build set (all from sources)
  {
    title   => "Source code build: SDL-1.2.14 & co. + all prereq. libraries\n" .
               "\tbuilds: zlib, jpeg, tiff, png, freetype, SDL, SDL_(image|mixer|ttf|net|gfx)",
    prereqs => {
        libs => [
          'pthread', # SDL
        ]
    },
    members     => [
      {
        pack => 'zlib',
        dirname => 'zlib-1.2.5',
        url => [
          'http://zlib.net/zlib-1.2.5.tar.gz',
          'http://froggs.de/libz/zlib-1.2.5.tar.gz',
        ],
        sha1sum  => '8e8b93fa5eb80df1afe5422309dca42964562d7e',
      },
      {
        pack => 'jpeg',
        dirname => 'jpeg-8a',
        url => [
          'http://www.ijg.org/files/jpegsrc.v8a.tar.gz',
          'http://froggs.de/libjpeg/jpegsrc.v8a.tar.gz',
        ],
        sha1sum  => '78077fb22f0b526a506c21199fbca941d5c671a9',
        patches => [ 'jpeg-8a_cygwin.patch' ],
      },
      {
        pack => 'tiff',
        dirname => 'tiff-3.9.1',
        url => [
          'http://froggs.de/libtiff/tiff-3.9.1.tar.gz',
          'ftp://ftp.remotesensing.org/pub/libtiff/tiff-3.9.1.tar.gz',
        ],
        sha1sum  => '675ad1977023a89201b80cd5cd4abadea7ba0897',
        patches => [ ],
      },
      {
        pack => 'png',
        dirname => 'libpng-1.4.1',
        url => [
          'http://downloads.sourceforge.net/libpng/libpng-1.4.1.tar.gz',
          'http://froggs.de/libpng/libpng-1.4.1.tar.gz',
        ],
        sha1sum  => '7a3488f5844068d67074f2507dd8a7ed9c69ff04',
      },
      {
        pack => 'freetype',
        dirname => 'freetype-2.3.12',
        url => [
          'http://mirror.lihnidos.org/GNU/savannah/freetype/freetype-2.3.12.tar.gz',
          'http://froggs.de/libfreetype/freetype-2.3.12.tar.gz',
        ],
        sha1sum  => '0082ec5e99fec5a1c6d89b321a7e2f201542e4b3',
      },
      {
        pack => 'SDL',
        dirname => 'SDL-1.2.14',
        url => [
          'http://www.libsdl.org/release/SDL-1.2.14.tar.gz',
          'http://froggs.de/libsdl/SDL-1.2.14.tar.gz',
        ],
        sha1sum  => 'ba625b4b404589b97e92d7acd165992debe576dd',
        patches => [
          'test1.patch',
        ],
      },
      {
        pack => 'SDL_image',
        dirname => 'SDL_image-1.2.10',
        url => [
          'http://www.libsdl.org/projects/SDL_image/release/SDL_image-1.2.10.tar.gz',
          'http://froggs.de/libsdl/SDL_image-1.2.10.tar.gz',
        ],
        sha1sum  => '6bae71fdfd795c3dbf39f6c7c0cf8b212914ef97',
        patches => [ ],
      },
      {
        pack => 'SDL_mixer',
        dirname => 'SDL_mixer-1.2.11',
        url => [
          'http://www.libsdl.org/projects/SDL_mixer/release/SDL_mixer-1.2.11.tar.gz',
          'http://froggs.de/libsdl/SDL_mixer-1.2.11.tar.gz',
        ],
        sha1sum  => 'ef5d45160babeb51eafa7e4019cec38324ee1a5d',
        patches => [ ],
      },
      {
        pack => 'SDL_ttf',
        dirname => 'SDL_ttf-2.0.9',
        url => [
          'http://www.libsdl.org/projects/SDL_ttf/release/SDL_ttf-2.0.9.tar.gz',
          'http://froggs.de/libsdl/SDL_ttf-2.0.9.tar.gz',
        ],
        sha1sum  => '6bc3618b08ddbbf565fe8f63f624782c15e1cef2',
        patches => [ ],
      },
      {
        pack => 'SDL_net',
        dirname => 'SDL_net-1.2.7',
        url => [
          'http://www.libsdl.org/projects/SDL_net/release/SDL_net-1.2.7.tar.gz',
          'http://froggs.de/libsdl/SDL_net-1.2.7.tar.gz',
        ],
        sha1sum  => 'b46c7e3221621cc34fec1238f1b5f0ce8972274d',
        patches => [ ],
      },
      {
        pack => 'SDL_gfx',
        dirname => 'SDL_gfx-2.0.20',
        url => [
          'http://www.ferzkopp.net/Software/SDL_gfx-2.0/SDL_gfx-2.0.20.tar.gz',
          'http://froggs.de/libsdl/SDL_gfx-2.0.20.tar.gz',
        ],
        sha1sum  => '077f7e64376c50a424ef11a27de2aea83bda3f78',
        patches => [ ],
      },
    ],
  },
];

sub check_config_script
{
  my $script = shift || 'sdl-config';
  print "Gonna check config script...\n";
  print "(scriptname=$script)\n";
  my $devnull = File::Spec->devnull();
  my $version = `$script --version 2>$devnull`;
  return if($? >> 8);
  my $prefix = `$script --prefix 2>$devnull`;
  return if($? >> 8);
  $version =~ s/[\r\n]*$//;
  $prefix =~ s/[\r\n]*$//;
  #returning HASHREF
  return {
    title     => "Already installed SDL ver=$version path=$prefix",
    buildtype => 'use_config_script',
    script    => $script,
    prefix    => $prefix,
  };
}

sub check_prebuilt_binaries
{
  print "Gonna check availability of prebuilt binaries ...\n";
  print "(os=$^O cc=$Config{cc} archname=$Config{archname})\n";
  my @good = ();
  foreach my $b (@{$prebuilt_binaries}) {
    if ( ($^O =~ $b->{os_re}) &&
         ($Config{archname} =~ $b->{arch_re}) &&
         ($Config{cc} =~ $b->{cc_re}) ) {
      $b->{buildtype} = 'use_prebuilt_binaries';
      push @good, $b;
    }
  }
  #returning ARRAY of HASHREFs (sometimes more than one value)
  return \@good;
}

sub check_src_build
{
  print "Gonna check possibility for building from sources ...\n";
  print "(os=$^O cc=$Config{cc})\n";
  my @good = ();
  foreach my $p (@{$source_packs}) {
    $p->{buildtype} = 'build_from_sources';
    push @good, $p if check_prereqs($p);
  }
  return \@good;
}

sub check_prereqs_libs {
  my @libs = @_;
  my $ret  = 1;

  foreach my $lib (@libs) {
    my $found_lib          = '';
    my $found_inc          = '';
    my $inc_lib_candidates = {
      '/usr/local/include' => '/usr/local/lib',
      '/usr/include'       => '/usr/lib',
    };

    if ( -e '/usr/lib64'  && $Config{'myarchname'} =~ /64/)
    {
	$inc_lib_candidates->{'/usr/include'} = '/usr/lib64'
    }

    my $header_map         = {
      'z'    => 'zlib',
      'jpeg' => 'jpeglib',
    };
    my $header             = (defined $header_map->{$lib}) ? $header_map->{$lib} : $lib;

    my $dlext = get_dlext();
    foreach (keys %$inc_lib_candidates) {
      my $ld = $inc_lib_candidates->{$_};
      next unless -d $_ && -d $ld;
      ($found_lib) = find_file($ld, qr/[\/\\]lib\Q$lib\E[\-\d\.]*\.$dlext[\d\.]*$/);
      ($found_inc) = find_file($_,  qr/[\/\\]\Q$header\E[\-\d\.]*\.h$/);
      last if $found_lib && $found_inc;
    }

    if($found_lib && $found_inc) {
      $ret &= 1;
    }
    else {
      print "WARNING: required lib(-dev) '$lib' not found, disabling affected option\n";
      $ret = 0;
    }
  }

  return $ret;
}

sub check_prereqs {
  my $bp  = shift;
  my $ret = 1;

  $ret &= check_prereqs_libs(@{$bp->{prereqs}->{libs}}) if defined $bp->{prereqs}->{libs};

  return $ret;
}

sub find_file {
  my ($dir, $re) = @_;
  my @files;
  $re ||= qr/.*/;
  {
    #hide warning "Can't opendir(...): Permission denied - fix for http://rt.cpan.org/Public/Bug/Display.html?id=57232
    no warnings 'File::Find';
    find({ wanted => sub { push @files, rel2abs($_) if /$re/ }, follow => 1, no_chdir => 1 , follow_skip => 2}, $dir);
  };
  return @files;
}

sub find_SDL_dir {
  my $root = shift;
  my ($version, $prefix, $incdir, $libdir);
  return unless $root;

  # try to find SDL_version.h
  my ($found) = find_file($root, qr/SDL_version\.h$/i ); # take just the first one
  return unless $found;

  # get version info
  open(DAT, $found) || return;
  my @raw=<DAT>;
  close(DAT);
  my ($v_maj) = grep(/^#define[ \t]+SDL_MAJOR_VERSION[ \t]+[0-9]+/, @raw);
  $v_maj =~ s/^#define[ \t]+SDL_MAJOR_VERSION[ \t]+([0-9]+)[.\r\n]*$/$1/;
  my ($v_min) = grep(/^#define[ \t]+SDL_MINOR_VERSION[ \t]+[0-9]+/, @raw);
  $v_min =~ s/^#define[ \t]+SDL_MINOR_VERSION[ \t]+([0-9]+)[.\r\n]*$/$1/;
  my ($v_pat) = grep(/^#define[ \t]+SDL_PATCHLEVEL[ \t]+[0-9]+/, @raw);
  $v_pat =~ s/^#define[ \t]+SDL_PATCHLEVEL[ \t]+([0-9]+)[.\r\n]*$/$1/;
  return if (($v_maj eq '')||($v_min eq '')||($v_pat eq ''));
  $version = "$v_maj.$v_min.$v_pat";

  # get prefix dir
  my ($v, $d, $f) = splitpath($found);
  my @pp = reverse splitdir($d);
  shift(@pp) if(defined($pp[0]) && $pp[0] eq '');
  shift(@pp) if(defined($pp[0]) && $pp[0] eq 'SDL');
  if(defined($pp[0]) && $pp[0] eq 'include') {
    shift(@pp);
    @pp = reverse @pp;
    return (
      $version,
      catpath($v, catdir(@pp), ''),
      catpath($v, catdir(@pp, 'include'), ''),
      catpath($v, catdir(@pp, 'lib'), ''),
    );
  }
}

sub check_header {
  my ($cflags, @header) = @_;
  print STDERR "Testing header(s): " . join(', ', @header) . "\n";
  my $cb = ExtUtils::CBuilder->new(quiet => 1);
  my ($fs, $src) = File::Temp->tempfile('XXXXaa', SUFFIX => '.c', UNLINK => 1);
  my $inc = '';
  $inc .= "#include <$_>\n" for @header;  
  syswrite($fs, <<MARKER); # write test source code
#if defined(_WIN32) && !defined(__CYGWIN__)
#include <stdio.h>
/* GL/gl.h on Win32 requires windows.h being included before */
#include <windows.h>
#endif
$inc
int demofunc(void) { return 0; }

MARKER
  close($fs);
  my $obj = eval { $cb->compile( source => $src, extra_compiler_flags => $cflags); };
  if($obj) {
    unlink $obj;
    return 1;
  }
  else {
    print STDERR "###TEST FAILED### for: " . join(', ', @header) . "\n";
    return 0;
  }
}

sub sed_inplace {
  # we expect to be called like this:
  # sed_inplace("filename.txt", 's/0x([0-9]*)/n=$1/g');
  my ($file, $re) = @_;
  if (-e $file) {
    cp($file, "$file.bak") or die "###ERROR### cp: $!";
    open INPF, "<", "$file.bak" or die "###ERROR### open<: $!";
    open OUTF, ">", $file or die "###ERROR### open>: $!";
    binmode OUTF; # we do not want Windows newlines
    while (<INPF>) {
     eval( "$re" );
     print OUTF $_;
    }
    close INPF;
    close OUTF;
  }
}

sub get_dlext {
  if($^O =~ /darwin/) { # there can be .dylib's on a mac even if $Config{dlext} is 'bundle'
    return 'so|dylib|bundle';
  }
  else {
    return $Config{dlext};
  }
}

1;
