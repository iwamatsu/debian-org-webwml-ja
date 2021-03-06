#!/usr/bin/perl -w
#
# mirror_list.pl -- generate various Debian mirror lists
# Copyright (C) 1998 James Treacy
# Copyright (C) 2000-2002, 2007-2008 Josip Rodin
# Copyright (C) 2005 Joey Hess
# Copyright (C) 2016 Peter Palfrader

use strict;
use English;
use HTML::Entities;
binmode(STDOUT => ':utf8');
require 5.001;

my @filter_arches=qw(); # Architectures not to list.

my $officialsiteregex = q{^ftp\d?(?:\.wa)?\...\.debian\.org$};
my $internalsiteregex = q{^((ftp|security)-master|ftp)\.debian\.org$};

my $encode = '<>&"\'';

use Getopt::Long;
my ($mirror_source, $output_type, $help);
my %opthash = (
  "mirror|m=s" => \$mirror_source,
  "type|t=s" => \$output_type,
  "help|h!" => \$help,
  );
Getopt::Long::config('no_getopt_compat', 'no_auto_abbrev');
GetOptions(%opthash) or die "error parsing options";

$output_type = 'html' if (! defined $output_type);
$mirror_source = 'Mirrors.masterlist' if (! defined $mirror_source);

my $last_modify = gmtime((stat($mirror_source))[9]);

my (@mirror, %countries, %countries_sorted, %countries_sponsors, %longest);
my ($count, $cdimagecount);
my (%code_of_country, %plain_name_of_country);
my %includedsites;

my $globalsite;

sub process_line {
  my ($lno, $line) = @_;
  my $field = '';

  if ($line =~ /^Site:\s*(.+)\s*$/i) {
    my $site = $1;
    $globalsite = $site;
    $count++;
    unless ($site =~ /$internalsiteregex/) {
      if (!defined($longest{site}) || length($site)+1 > $longest{site}) {
        $longest{site} = length($site)+1;
#        warn "increasing longest site to " . length($site) . " because of " . $site . "\n";
      }
    }
    $mirror[$count-1]{site} = $site;
    $mirror[$count-1]{_lno} = $lno;
    return;
  }
  elsif ($line =~ /^Alias(?:es)?:\s*(.+)\s*$/is) {
    push @{ $mirror[$count-1]{aliases} }, $_ foreach (split("\n", $1));
  }
  elsif ($line =~ /^(\w+)-architecture:\s*(.+)\s*$/i && length $2) { 
    my $key = "$1"."-architecture";
    my @arches=split(' ', $2);
    foreach my $f (@filter_arches) {
      @arches=grep { ! /^$f$/ } @arches;
    }
    if (! @arches) {
      # Mirror only carries filtered architectures.
      $mirror[$count-1]{filtered}=1;
    }
    foreach my $f (@filter_arches) {
      @arches=grep { ! /^\!$f$/ } @arches;
    }
    if (@arches) {
      $mirror[$count-1]{$key}=\@arches;
    }
  }
  elsif ($line=~ /^((Archive|Security|CDimage|Jigdo|Old)-(\w*)):\s*(.*)\s*$/i) {
    my $type = lc $1;
    my $value = $4;
    $mirror[$count-1]{method}{$type} = $value;
    if (!defined($longest{$type}) || length($value)+1 > $longest{$type}) {
      $longest{$type} = length($value)+1;
#      warn "increasing longest $type to " . length($value) . " because of " . $value . " at " . $globalsite . "\n" if (defined($type) && $type =~ /archive-(f|ht)tp/);
    }
  }
  elsif ($line =~ /^Includes:\s*(.+)\s*$/i) {
    push @{ $mirror[$count-1]{includes} }, $_ foreach (split(" ", $1));
  }
  elsif ($line =~ /^Sponsor:\s*(.+)\s*$/i) {
    push @{ $mirror[$count-1]{sponsor} }, $1;
  }
  elsif ($line =~ /^([\w-]+):\s*(.+)\s*$/s) {
    $field = lc $1;
    my $value = $2;
    # no need for all private data in the %mirror hash
    # XXX modified to include x-archive-architecture because
    # the nsupdate thingy needs it for included-in sites - another
    # possible solution would be to convert those particular ones to
    # e.g. <somethingelse>-archive-architecture?
    if ($field !~ /^x-/ || $field =~ /^x-archive-architecture/) {
      $mirror[$count-1]{$field} = $value;
    }
    if ($field eq 'country') {
      if ($value =~ /^(\w\w) (.+)$/) {
        $code_of_country{$value} = $1;
        $plain_name_of_country{$value} = $2;
      } else {
        die "strangely formatted Country field value: $value";
      }
    }
  }
  else {
    die "Error: incorrect line format\n\"$line\"\n";
  }
}


sub aptlines {
  foreach my $country (sort keys %countries) {
    print "\n$country\n";
    print "-" x length($country); # underline
    print "\n";
    foreach my $id (@{ $countries{$country} }) {
      my $archcomm="";
      if ($mirror[$id]{'Archive-architecture'}) {
        $archcomm=" # ".join(" ", sort @{$mirror[$id]{'Archive-architecture'}})."\n";
      }
      if (defined $mirror[$id]{method}{'archive-http'}) {
        print "deb http://$mirror[$id]{site}$mirror[$id]{method}{'archive-http'} stable main contrib non-free$archcomm\n";
      }
      print "\n";
    }
  }
}


sub secondary_mirrors {
  # TODO make the text version not have such long lines.
  my $format = shift;
  die "must get format for secondary_mirrors()" unless $format;
  my $html = 1 if ($format eq 'html');
  my $text = 1 if ($format eq 'text');
  my $wml = 1 if ($format eq 'wml');

  my $formatstring;
  
  if ($html || $text) {
    print "<h2 align=\"center\">" if $html;
    print "\n\n                   " if $text;
    print "Secondary mirrors of the Debian archive";
    print "\n                   ---------------------------------------\n\n" if $text;
    print "</h2>\n\n" if $html;
    if ($html) {
      print <<END;
<table border="0" class="center">
<tr>
  <th>Host name</th>
  <th>HTTP</th>
  <th>Architectures</th>
</tr>
END
    } else {
      my $formatstring = "%-$longest{site}s %-$longest{'archive-http'}s%s\n";
      printf $formatstring, "HOST NAME", "HTTP", "ARCHITECTURES";
      printf $formatstring, "---------", "----", "-------------";
    }
  } elsif ($wml) {
    print "<perl>\n";
  }
  foreach my $country (sort keys %countries) {
    my $countryplain = $plain_name_of_country{$country};
    my $countrycode = $code_of_country{$country};
    my %our_mirrors;
    foreach my $id (@{ $countries{$country} }) {
      if (defined $mirror[$id]{method}{'archive-http'}) {
        $our_mirrors{$id} = 1;
      }
    }
    next unless (keys %our_mirrors);
    print "\n";
    if ($html) {
      print "<tr><td colspan=4><hr size=1></td></tr>\n";
      print "<tr><td colspan=4><big><strong>$country</strong></big></td></tr>\n";
    } elsif ($text) {
      print "$country";
    }
    print "\n";
    if ($text) {
      print "-" x length($country); # underline
      print "\n";
    }
    foreach my $id (@{ $countries_sorted{$country} }) {
      next unless defined $mirror[$id]{method}{'archive-http'};
      my $aliaslist;
      if (exists $mirror[$id]{'aliases'}) {
        if (!exists $mirror[$id]{includes}) {
          # we want to display aliases in the main list for official mirrors
          # but for others, it's just clutter, so skip them
          if ($mirror[$id]{site} =~ /$officialsiteregex/) {
            my $truename = @{$mirror[$id]{'aliases'}}[0];
            if ($truename =~ /^ftp.+\.debian\.org$/) {
              $truename = @{$mirror[$id]{'aliases'}}[1];
            }
            $aliaslist .= "  (" . $truename . ")";
          }
        }
      }
      if (exists $mirror[$id]{includes}) {
	$aliaslist .= "  (";
	my @tmparray = @{$mirror[$id]{includes}};
	my $notalldone = $#tmparray + 1;
SUBSITE:  foreach my $subsite (@{ $mirror[$id]{includes} }) {
	  # this is basically a sanity check
	  my $subsite_id;
SUBSITEID:  foreach my $mid (0 .. $#mirror) {
	    if ($mirror[$mid]{site} eq $subsite) {
	      $subsite_id = $mid;
	      last SUBSITEID;
	    }
	  }
	  die $subsite ." included in " . $mirror[$id]{site} . " does not exist\n" unless defined $subsite_id; # must be an error
	  # this prints the canonical name of the included site rather than its reference - should be in sync, but might actually vary
	  $aliaslist .= $mirror[$subsite_id]{site};
	  $notalldone--;
	  $aliaslist .= ", " if ($notalldone);
	}
	$aliaslist .= ")";
      }
      if ($html) {
        print "<tr>\n";
        print "<td valign=top>$mirror[$id]{site}";
        print "<br>$aliaslist" if ($aliaslist);
        print "</td>\n";
      } elsif ($text) {
        my $formatstring = "%-$longest{site}s ";
        printf $formatstring, $mirror[$id]{site};
      }
      if (defined $mirror[$id]{method}{'archive-http'}) {
        my $rest = $longest{'archive-http'} - length($mirror[$id]{method}{'archive-http'});
        if ($html) {
          print <<END;
<td valign=top><a rel="nofollow" href="http://$mirror[$id]{site}$mirror[$id]{method}{'archive-http'}">$mirror[$id]{method}{'archive-http'}</a></td>
END
        } elsif ($text) {
          my $formatstring = "%s%${rest}s";
          printf $formatstring, $mirror[$id]{method}{'archive-http'}, '';
        } elsif ($wml) {
          print <<EOF;
  push \@{ \$secondaries{"<${countrycode}c>"}{"$mirror[$id]{site}"} },
        "<a rel=\\\"nofollow\\\" href=\\\"http://$mirror[$id]{site}$mirror[$id]{method}{'archive-http'}\\\">$mirror[$id]{method}{'archive-http'}</a>";
EOF
        }
      } else {
        if ($html) {
          print "<td></td>\n";
        } elsif ($text) {
          my $formatstring = "%-$longest{'archive-http'}s";
          printf $formatstring, " ";
        } elsif ($wml) {
          print <<EOF;
  push \@{ \$secondaries{"<${countrycode}c>"}{"$mirror[$id]{site}"} },
        "";
EOF
        }
      }
      my $archlistsorted = join(" ", sort @{$mirror[$id]{'Archive-architecture'}});
      if ($html) {
        print "<td valign=top><small><small>$archlistsorted</small></small></td>\n";
      } elsif ($text) {
        print $archlistsorted;
        print "\n";
      } elsif ($wml) {
        print <<EOF;
  push \@{ \$secondaries{"<${countrycode}c>"}{"$mirror[$id]{site}"} },
        "$archlistsorted";
EOF
      }
      if ($aliaslist) {
        if ($text) {
          print $aliaslist . "\n";
        } elsif ($wml) {
          print <<EOF;
  push \@{ \$secondaries{"<${countrycode}c>"}{"$mirror[$id]{site}"} },
        "$aliaslist";
EOF
        }
      }
      if ($html) {
        print "</tr>\n";
      }
    }
  }
  if ($wml) {
    # in our WML templates there is a langcmp comparison method,
    # which sorts alphabetically depending on the language
    print <<EOF;
my \%sawcountry = {};
foreach my \$country (sort langcmp keys \%secondaries) {
  unless (\$sawcountry{\$country}) {
    print <<EOM;
<tr><td colspan="4"><hr style="height:1"></td></tr>
<tr><td colspan="4"><big><strong>\$country</strong></big></td></tr>
EOM
  }
  \$sawcountry{\$country} = 1;
  sub officialfirst {
    (\$b =~ /^ftp\\d?(?:\\.wa)?\\...\\.debian\\.org\$/) <=> (\$a =~ /^ftp\\d?(?:\\.wa)?\\...\\.debian\\.org\$/)
    ||
    \$a cmp \$b;
  }
  foreach my \$countrysite (sort officialfirst keys \%{\$secondaries{\$country}}) {
    my \@elems = \@{\$secondaries{\$country}{\$countrysite}};
    print <<EOM;
<tr>
  <td valign="top">\$countrysite
EOM
    if (\$elems[3]) {
      my \$extraname = \$elems[3];
      \$extraname =~ s%  %\&nbsp\;\&nbsp\;%;
      print <<EOM;
<br>
\$extraname
EOM
    }
    print <<EOM;
  </td>
  <td valign="top">\$elems[0]</td>
  <td valign="top">\$elems[1]</td>
</tr>
EOM
  }
}
</perl>
EOF
  }
  print "</table>\n" if ($html);
}


sub intro {
  my $format = shift;
  die "must get format for intro()" unless $format;
  my $html = 1 if ($format eq 'html');
  my $text = 1 if ($format eq 'text');

  print "<h1 align=\"center\">" if $html;
  print "                        " if $text;
  print "Debian worldwide mirror sites";
  print "</h1>" if $html;
  print "\n                        -----------------------------\n" if $text;
  print "\n";

  print "<p>" if $html;
  print "Debian is distributed (";
  print $html ? "<em>mirrored</em>" : "mirrored";
  print ") on hundreds of servers on the Internet.\n";
  print <<END;
Using a nearby server will probably speed up your download, and also
reduce the load on our central servers and on the Internet as a whole.

END
  print "<p>" if $html;
  print <<END;
Debian mirrors can be primary and secondary. The definitions are as follows:

END
  if ($html) {
          print <<END;
  <blockquote>
  A <strong>primary mirror</strong> site has good bandwidth, is available 24 hours a day,
  and has an easy to remember name of the form ftp.&lt;country&gt;.debian.org.
  <br>
END
  } else {
    print <<END;
  A primary mirror site has good bandwidth, is available 24 hours a day,
  and has an easy to remember name of the form ftp.<country>.debian.org.
END
  }
  print <<END;
  They are all automatically updated whenever there are updates to
  the Debian archive.

END
  print "  </blockquote>\n" if $html;
  if ($html) {
          print <<END;
  <blockquote>
  A <strong>secondary mirror</strong> site may have restrictions on what they mirror (due to
END
  } else {
    print <<END;
  A secondary mirror site may have restrictions on what they mirror (due to
END
  }
  print <<END;
  space restrictions). Just because a site is secondary doesn't necessarily
  mean it'll be any slower or less up to date than a primary site.

END
  print "  </blockquote>\n" if $html;
  print "<p>" if $html;
  print <<END;
Use the site closest to you for the fastest downloads possible whether it is
END
  if ($html) {
          print "
a primary or secondary site. The program
<a href=\"https://packages.debian.org/stable/net/netselect\">
<em>netselect</em></a> can be used to\n";
  } else {
    print "a primary or secondary site. The program `netselect' can be used to\n";
  }
  print <<END;
determine the site with the least latency; use a download program such as
END
  if ($html) {
          print "
<a href=\"https://packages.debian.org/stable/web/wget\">
<em>wget</em></a> or
<a href=\"https://packages.debian.org/stable/net/rsync\">
<em>rsync</em></a> for determining the site with the most throughput.\n";
  } else {
    print "`wget' or `rsync' for determining the site with the most throughput.\n";
  }
  print <<END;
Note that geographic proximity often isn't the most important factor for
determining which machine will serve you best.

END
  print "<p>" if $html;
  print "The authoritative copy of the following list can always be found at:\n";
  print "<a href=\"https://www.debian.org/mirror/list\">" if $html;
  print "                      https://www.debian.org/mirror/list";
  print "</a>.<br>" if $html;
  print "\n";

  print <<END;
If you know of any mirrors that are missing from this list,
please have the site maintainer fill out the form at:
END
  print "<a href=\"https://www.debian.org/mirror/submit\">" if $html;
  print "                     https://www.debian.org/mirror/submit";
  print "</a>.<br>" if $html;
  print "\n";

  print <<END;
Everything else you want to know about Debian mirrors:
END
  print "<a href=\"https://www.debian.org/mirror/\">" if $html;
  print "                        https://www.debian.org/mirror/";
  print "</a>.<br>" if $html;
  print "\n";
}

sub primary_mirrors {
  my $format = shift;
  die "must get format for primary_mirrors()" unless $format;
  my $html = 1 if ($format eq 'html');
  my $text = 1 if ($format eq 'text');
  my $wml = 1 if ($format eq 'wml');

  my %primaries = ();
  if ($html) {
    print <<END;

<h2 class="center">Primary Debian mirror sites</h2>

<table border="0" class="center">
<tr>
  <th>Country</th>
  <th>Site</th>
  <th>Architectures</th>
</tr>
END
  } elsif ($text) {
    print <<END;


                         Primary Debian mirror sites
                         ---------------------------

 Country         Site                  Debian archive  Architectures
 ---------------------------------------------------------------------------
END
  } elsif ($wml) {
    print <<END;
#use wml::debian::countries
<perl>
END
  }
  foreach my $country (sort keys %countries) {
    foreach my $id (sort @{ $countries{$country} }) {
      next unless ($mirror[$id]{site} =~ /$officialsiteregex/);

      my $countryplain = $plain_name_of_country{$country};
      my $countrycode = $code_of_country{$country};

      unless (exists $mirror[$id]{method}{'archive-http'}) {
        warn "official mirror " . $mirror[$id]{site} . " does not have archive-http?!";
        next;
      }

      my $arches = join(" ", sort @{$mirror[$id]{'Archive-architecture'}});

      if ($html) {
        $countryplain =~ s/ /&nbsp;/;
        print <<END;
<tr>
  <td>$countryplain</td>
  <td><a rel="nofollow" href="http://$mirror[$id]{site}$mirror[$id]{method}{'archive-http'}">$mirror[$id]{site}$mirror[$id]{method}{'archive-http'}</a></td>
  <td><small><small>$arches</small></small></td>
</tr>
END
      } elsif ($text) {
        printf " %-14s  %-20s  %-14s  %s\n", $countryplain, $mirror[$id]{site}, $mirror[$id]{method}{'archive-http'}, $arches;
      } elsif ($wml) {
        # this creates a hash of with keys like <DEc>
        # later this gets expanded by WML into forms like
        # Germany or Deutschland
        # the next-level key is the site name, because countries
        # can have more than one site
        print <<EOF;
  push \@{ \$primaries{"<${countrycode}c>"}{"$mirror[$id]{site}"} },
    (
      "$mirror[$id]{method}{'archive-http'}",
      "$arches",
    );
EOF
      }
    }
  }
  if ($wml) {
    # in our WML templates there is a langcmp comparison method,
    # which sorts alphabetically depending on the language
    print <<EOF;
foreach my \$country (sort langcmp keys \%primaries) {
  foreach my \$countrysite (sort keys \%{\$primaries{\$country}}) {
    my \@elems = \@{\$primaries{\$country}{\$countrysite}};
    print <<EOM;
<tr>
  <td>\$country</td>
  <td><a rel="nofollow" href="http://\$countrysite\$elems[0]">\$countrysite\$elems[0]</a></td>
  <td><small><small>\$elems[1]</small></small></td>
</tr>
EOM
  }
}
</perl>
EOF
  }
  print "</table>\n" if ($html);
}

# meant to be output into a file which is then included into a .wml file
# and processed by WML
sub primary_mirror_sponsors {
  print <<END;
#use wml::debian::countries
<tr><td colspan="3"><hr></td></tr>
END
  foreach my $country (sort keys %countries) {
    foreach my $id (sort @{ $countries{$country} }) {
      next unless ($mirror[$id]{site} =~ /$officialsiteregex/);
      my $countrycode = $code_of_country{$country};
      print <<END;
<tr>
  <td><${countrycode}c></td>
  <td><a rel="nofollow" href="http://$mirror[$id]{site}$mirror[$id]{method}{'archive-http'}">$mirror[$id]{site}</a></td>
  <td>
END
      if (exists $mirror[$id]{includes}) {
        my $numsubsites = @{ $mirror[$id]{includes} };
        my $snum = 0;
        foreach my $subsite (@{ $mirror[$id]{includes} }) {
          # XXX Note this is a little bit wrong; if there is more than one id
          # for a subsite, it just takes the first one. This problem
          # could occur if a subsite begins mirroring some other arch,
          # like amd64.
          my $subsite_id;
          foreach my $mid (0..$#mirror) {
            if ($mirror[$mid]{site} eq $subsite) {
              $subsite_id=$mid;
              last;
            }
          }      
          die "can't find $subsite, wtf?!" unless defined $subsite_id; # must be an error
          die "can't find sponsor for $subsite, wtf?!" unless defined $mirror[$subsite_id]{sponsor}; # must be an error

          my $numsponsors = @{ $mirror[$subsite_id]{sponsor} };
          my $num = 0;
          my ($sponsorname, $sponsorurl);
          foreach my $sponsor (@{ $mirror[$subsite_id]{sponsor} }) {
            if ($sponsor =~ /^(.+) (https?:.*)$/) {
              $sponsorname = $1;
              $sponsorurl = $2;
            } else {
              die "can't find sponsor URL for sponsor $sponsor of $subsite";
            }
            encode_entities($sponsorname, $encode);
            print "<a href=\"$sponsorurl\">$sponsorname</a>";
            $num++;
            print ", " unless ($num >= $numsponsors);
          }
          $snum++;
          print ", " unless ($snum >= $numsubsites);
        }
      } else {
        die "$mirror[$id]{site} has no sponsor\n" unless exists $mirror[$id]{sponsor}; # must be an error
        my $numsponsors = @{ $mirror[$id]{sponsor} };
        my $num = 0;
        my ($sponsorname, $sponsorurl);
        foreach my $sponsor (@{ $mirror[$id]{sponsor} }) {
          if ($sponsor =~ /^(.+) (http:.*)$/) {
            $sponsorname = $1;
            $sponsorurl = $2;
                } else {
            die "can't find sponsor URL for sponsor $sponsor of $mirror[$id]{site}";
          }
          encode_entities($sponsorname, $encode);
          print "<a href=\"$sponsorurl\">$sponsorname</a>";
          $num++;
          print ", " unless ($num >= $numsponsors);
        }
      }
      print <<END;

  </td>
</tr>
END
    }
  }
  print "</table>\n";
}

# meant to be output into a file which is then included into a .wml file
# and processed by WML
sub mirror_sponsors {
  print <<END;
#use wml::debian::countries
<tr><td colspan="3"><hr></td></tr>
END
  foreach my $country (sort keys %countries) {
    next unless $countries_sponsors{$country};
    foreach my $id (sort @{ $countries_sponsors{$country} }) {
      # sites which have Includes don't have to have Sponsor, the included ones
      # have it; and those are looped over separately anyway, so no need to repeat
      next if (exists $mirror[$id]{includes});
      my $countrycode = $code_of_country{$country};
      print <<END;
<tr>
  <td>${countrycode} <${countrycode}c></td>
  <td>$mirror[$id]{site}
END
      if (exists $mirror[$id]{'included-in'}) {
        print "<br>(";
        print join (", ", @{ $mirror[$id]{'included-in'} });
        print ")";
      }
      print <<END;
  </td>
  <td>
END
      my $numsponsors = @{ $mirror[$id]{sponsor} };
      my $num = 0;
      my ($sponsorname, $sponsorurl);
      foreach my $sponsor (@{ $mirror[$id]{sponsor} }) {
        if ($sponsor =~ /^(.+) (https?:.*)$/) {
          $sponsorname = $1;
          $sponsorurl = $2;
        } else {
          die "can't find sponsor URL for sponsor $sponsor of $mirror[$id]{site}";
        }
        encode_entities($sponsorname, $encode);
        print "<a href=\"$sponsorurl\">$sponsorname</a>";
        $num++;
        print ",\n" unless ($num >= $numsponsors);
      }
      print "\n";
      print <<END;
  </td>
</tr>
END
    }
  }
}

# meant to be output into a file which is then included into a .wml file
# and processed by WML
sub cdimage_mirrors($) {
  my $which = shift;
  die unless $which;
  print "#use wml::debian::languages\n\n<perl>\nmy \@cdmirrors = (\n";
  foreach my $country (keys %countries) {
    foreach my $id (sort @{ $countries{$country} }) {
      my $countrycode = $code_of_country{$country};
      if ($which eq "httpftp") {
        if (defined $mirror[$id]{method}{'cdimage-ftp'} ||
            defined $mirror[$id]{method}{'cdimage-http'}) {
          print "  '<${countrycode}c>: $mirror[$id]{site}:";
          if (defined $mirror[$id]{method}{'cdimage-ftp'}) {
            print qq( <a rel="nofollow" href="ftp://$mirror[$id]{site}$mirror[$id]{method}{'cdimage-ftp'}">FTP</a>);
          }
          if (defined $mirror[$id]{method}{'cdimage-http'}) {
            print qq( <a rel="nofollow" href="http://$mirror[$id]{site}$mirror[$id]{method}{'cdimage-http'}">HTTP</a>);
          }
          print "',\n";
        }
      } elsif ($which eq "rsync") {
        if (defined $mirror[$id]{method}{'cdimage-rsync'}) {
          print qq(  '<${countrycode}c>: $mirror[$id]{site}: <span class="cdrsync">rsync $mirror[$id]{site}\:\:$mirror[$id]{method}{'cdimage-rsync'}</span>',\n);
END
        }
      }
    }
  }
  print ");\n\n";

  # Write some code to sort the list alphabetically (the ordering is
  # language-dependent)
  print <<'EOM';
print "<ul>\n";
foreach $line (sort langcmp @cdmirrors)
{
  print "<li>$line</li>\n";
}
print "</ul>\n";
</perl>
EOM
}

sub header {
  print <<END;
<html>

<head>
  <title>Debian worldwide mirror sites</title>
</head>

<body>
END
}

sub trailer {
  print "</body>\n</html>\n";
}


# this is likely obsolete
sub access_methods {
  print <<END;
<h1 class="center">Debian worldwide mirror sites</h1>

<p>This is a <strong>complete</strong> list of mirrors of Debian. For each
site, the different types of material available are listed, along with the
access method for each type.

<p>The following things are mirrored:
<dl>
<dt><strong>Packages</strong>
  <dd>The Debian package pool.
<dt><strong>CD Images</strong>
  <dd>Official Debian CD Images. See
  <a href="https://www.debian.org/CD/">https://www.debian.org/CD/</a> for details.
<dt><strong>Old releases</strong>
  <dd>The archive of old released versions of Debian.<br>
  Some of the old releases also included the so-called debian-non-US
  archive, with sections for Debian packages that could not be
  distributed in the US due to software patents or use of encryption.
  The debian-non-US updates were discontinued with Debian 3.1.
</dl>

<p>The following access methods are possible:
<dl>
<dt><strong>HTTP</strong>
  <dd>Standard web access, but it can be used for downloading files.
<dt><strong>FTP</strong>
  <dd>The file transfer protocol.
<dt><strong>rsync</strong>
  <dd>An efficient means of mirroring.
<dt><strong>NFS</strong>
  <dd>Network file system (if you don't know what it is, you don't need it).
</dl>

<p>The 'Type' entry is one of:
<dl>
<dt><strong>leaf</strong>
  <dd>These comprise the bulk of the mirrors.
<dt><strong>Push-Secondary</strong>
  <dd>These sites mirror directly from a Push-Primary site, using push
  mirroring.
<dt><strong>Push-Primary</strong>
  <dd>These sites mirror directly from the master archive site (which
  is not publicly accessible), using push mirroring.
</dl>
(See <a href="https://www.debian.org/mirror/push_mirroring">the page about push
mirroring</a> for details on that.)

<p>The authoritative copy of the following list can always be found at:
<a href="https://www.debian.org/mirror/list-full">
https://www.debian.org/mirror/list-full</a>.
<br>
Everything else you want to know about Debian mirrors:
<a href="https://www.debian.org/mirror/">https://www.debian.org/mirror/</a>.
<br>
END
}

sub full_listing {
  # TODO: fix the html mode to output actual normal HTML, rather than <pre>
  my $format = shift;
  die "must get format for full_listing()" unless $format;
  my $html = 1 if ($format eq 'html');
  my $text = 1 if ($format eq 'text');
  my $wml = 1 if ($format eq 'wml');

  if ($html) {
    print "\n<hr style=\"height:1\">\n";
    print "<p>Jump directly to a country on the list:<br>\n";
  }
  if ($html) {
    my $linelength = 0;
    foreach my $country (sort keys %countries) {
      my $countryplain = $plain_name_of_country{$country};
      my $countrycode = $code_of_country{$country};
      print " [<a href=\"#${countrycode}\">";
      print $countryplain;
      print "</a>]";
      $linelength += length($countryplain) + 3;
      if ($linelength >= 75) {
        print "<br>\n";
        $linelength = 0;
      }
    }
  } elsif ($wml) {
    # in our WML templates there is a langcmp comparison method,
    # which sorts alphabetically depending on the language
    print <<EOF;
#use wml::debian::countries
<:
my \%countrylist;
EOF
    foreach my $country (sort keys %countries) {
      my $countryplain = $plain_name_of_country{$country};
      my $countrycode = $code_of_country{$country};
      print <<EOF;
\$countrylist{"<${countrycode}c>"} = $countrycode;
EOF
    }
    print <<EOF;
my \$linelength = 0;
foreach my \$country (sort langcmp keys \%countrylist) {
  print ' [<a href="#' . \$countrylist{\$country} . '">' . "\$country</a>]";
  \$linelength += length(\$country) + 3;
  if (\$linelength >= 75) {
    print "<br>\n";
    \$linelength = 0;
  }
}
:>
EOF
  }
  if ($html || $wml) {
    print "\n<hr style=\"height:1\">\n";
  }
  print "<pre>\n" if $html;
  foreach my $country (sort keys %countries) {
    my $countryplain = $plain_name_of_country{$country};
    my $countrycode = $code_of_country{$country};
    print "\n";
    if ($html) {
      print "<strong><a name=\"$countrycode\">$country</a></strong>\n";
    } elsif ($text) {
      print "$country\n";
    } elsif ($wml) {
      print "<h3><a name=\"$countrycode\"><${countrycode}c></a></h3>\n";
    }
    if ($html || $text) {
      print "-" x length($country); # underline
    } elsif ($wml) {
      print "\n";
    }
    print "\n";
    foreach my $id (@{ $countries_sorted{$country} }) {
      next unless keys %{$mirror[$id]{'method'}};
      print "Site: ";
      print "<tt>" if $wml;
      print $mirror[$id]{site};
      if (exists $mirror[$id]{'aliases'}) {
        print ", ".join(", ", @{ $mirror[$id]{'aliases'} });
      }
      print "</tt>" if $wml;
      print "<br>" if $wml;
      print "\n";
      warn "undefined type for $mirror[$id]{site}!\n" unless defined $mirror[$id]{'type'};
      $mirror[$id]{'type'} ||= 'leaf';
      print "Type: $mirror[$id]{'type'}\n";
      print "<br>" if $wml;
      foreach my $method ( sort keys %{ $mirror[$id]{method} } ) {
        my $display = $method;
        $display =~ s/archive-/Packages /;
        $display =~ s/security-/Security updates /;
        $display =~ s/cdimage-/CD Images /;
        $display =~ s/jigdo-/Jigdo files /;
        $display =~ s/old-/Old releases /;
        $display =~ s/ftp/over FTP/;
        $display =~ s/http/over HTTP/;
        $display =~ s/nfs/over NFS/;
        $display =~ s/rsync/over rsync/;
        if ($method =~ /http/) {
          print $display.":  ";
          print "<tt>" if $wml;
          print "<a rel=\"nofollow\" href=\"http://$mirror[$id]{site}$mirror[$id]{method}{$method}\">$mirror[$id]{method}{$method}</a>\n";
          print "</tt>" if $wml;
        } elsif ($method =~ /ftp/) {
          print $display.":  ";
          print "<tt>" if $wml;
          print "<a rel=\"nofollow\" href=\"ftp://$mirror[$id]{site}$mirror[$id]{method}{$method}\">$mirror[$id]{method}{$method}</a>\n";
          print "</tt>" if $wml;
        } else {
          print $display.":  ";
          print "<tt>" if $wml;
          print $mirror[$id]{method}{$method}."\n";
          print "</tt>" if $wml;
        }
        print "<br>" if $wml;
      }
      if (exists $mirror[$id]{'Archive-architecture'}) {
        print "Includes architectures: ".join(" ", sort @{$mirror[$id]{'Archive-architecture'}})."\n";
        print "<br>" if $wml;
      }
      print "Update frequency: ";
      if ($mirror[$id]{'type'} =~ /push/i) {
        print "whenever there are updates (push-triggered)";
      } elsif (exists $mirror[$id]{'updates'} and $mirror[$id]{'updates'} =~ /^(?:once|daily)(.*)$/) {
        print "once a day";
        print " $1" if $1;
      } elsif (exists $mirror[$id]{'updates'} and $mirror[$id]{'updates'} =~ /^(?:twice)(.*)$/) {
        print "twice a day";
        print " $1" if $1;
      } elsif (exists $mirror[$id]{'updates'} and $mirror[$id]{'updates'} =~ /^(?:four)(.*)$/) {
        print "four times a day";
        print " $1" if $1;
      } elsif (exists $mirror[$id]{'updates'} and $mirror[$id]{'updates'} ne '') {
        print $mirror[$id]{'updates'};
      } else {
        print "unknown";
      }
      print "\n";
      print "<br>" if $wml;
      if (exists $mirror[$id]{'comment'}) {
        print "Comment: ";
        print "<span style=\"white-space: pre;\">" if $wml;
        print $mirror[$id]{comment};
        print "</span>" if $wml;
        print "\n";
        print "<br>" if $wml;
      }
      print "<br>" if $wml;
      print "\n";
    }
  }
  print "</pre>\n" if $html;
}

sub compact_list($$) {
  my $whichtype = shift;
  die "must get type for compact_list()" unless $whichtype;
  my $ordering = shift;
  die "must get ordering for compact_list()" unless $ordering;

  sub printhtmlftprsync($$$$) {
    my ($site, $http, $ftp, $rsync) = @_;
    print "<a rel=\"nofollow\" href=\"http://". $site . $http ."\">HTTP</a> " if (defined $http);
    print "<a rel=\"nofollow\" href=\"ftp://". $site . $ftp ."\">FTP</a> " if (defined $ftp);
    print "rsync&nbsp;". $site . "::" . $rsync if (defined $rsync);
  }

  if ($ordering eq 'countrysite') {
    foreach my $country (sort keys %countries) {
      my %our_mirrors;
      foreach my $id (@{ $countries{$country} }) {
        if ( defined($mirror[$id]{method}{$whichtype.'-ftp'}) or
             defined($mirror[$id]{method}{$whichtype.'-http'}) or
             defined($mirror[$id]{method}{$whichtype.'-rsync'}) ) {
          $our_mirrors{$id} = 1;
        }
      }
      next unless (keys %our_mirrors);
      my $countryplain = $plain_name_of_country{$country};
      my $countrycode = $code_of_country{$country};
      foreach my $id (@{ $countries_sorted{$country} }) {
        next unless (exists $our_mirrors{$id});
        print "<li><".$countrycode."c>: " . $mirror[$id]{site} . ": ";
        printhtmlftprsync($mirror[$id]{site},
                          $mirror[$id]{method}{$whichtype.'-http'},
                          $mirror[$id]{method}{$whichtype.'-ftp'},
                          $mirror[$id]{method}{$whichtype.'-rsync'});
        print "</li>\n";
      }
    }
  } elsif ($ordering eq 'sitecountry') {
    my %our_mirrors;
    foreach my $id (0..$#mirror) {
      if ( defined($mirror[$id]{method}{$whichtype.'-ftp'}) or
           defined($mirror[$id]{method}{$whichtype.'-http'}) or
           defined($mirror[$id]{method}{$whichtype.'-rsync'}) ) {
        $our_mirrors{ $mirror[$id]{site} } = $id;
      }
    }
    foreach my $site (sort keys %our_mirrors) {
      my $id = $our_mirrors{$site};
      my $countryplain = $plain_name_of_country{ $mirror[$id]{country} };
      my $countrycode = $code_of_country{ $mirror[$id]{country} };
      print "<li>" . $mirror[$id]{site};
      if ($countrycode ne ''){print " (<".$countrycode."c>)"}
      print ": ";
      printhtmlftprsync($mirror[$id]{site},
                        $mirror[$id]{method}{$whichtype.'-http'},
                        $mirror[$id]{method}{$whichtype.'-ftp'},
                        $mirror[$id]{method}{$whichtype.'-rsync'});
      print "</li>\n";
    }
  }
}

sub footer_stuff($$) {
  my $format = shift;
  die "must get format for footer_stuff()" unless $format;
  my $html = 1 if ($format eq 'html');
  my $text = 1 if ($format eq 'text');
  my $wml = 1 if ($format eq 'wml');

  my $whichcount = shift;
  die "must get count for footer_stuff()" unless $whichcount;

  if ($html || $wml) {
    print <<END;
<hr>
<table border="0" width="100%"><tr>
  <td align="left"><small>Last modified: $last_modify</small></td>
  <td align="right"><small>Number of sites listed: $whichcount</small></td>
</tr></table>
END
  } elsif ($text) {
    print "\n";
    print "-" x 79 . "\n";
# expecting $last_modify like: Mon Jan  1 00:00:00 0000 - 24 characters wide
# expecting $whichcount to be less than 1k :)
    printf "%-14s %-24s %-11s %-23s %-3d\n",
           'Last modified:', $last_modify, '', 'Number of sites listed:', $whichcount;
  }
}


# fork of secondary_mirrors
sub generate_html_matrix {
  my $archive_name = $_[0];
  my $archive_name_lc = lc($archive_name);
  print "<h2 class=\"center\">Mirrors of the Debian-".$archive_name_lc." archive</h2>\n";
  print "<table class=\"volatile\" summary=\"Mirrors sorted by Country\">\n";
  print "<colgroup span=\"5\">\n</colgroup>\n";
  print "<thead><tr><th>HOST NAME</th><th>FTP</th><th>HTTP</th><th>RSYNC</th><th>ARCHITECTURES</th></tr></thead>\n<tbody>\n";
  foreach my $country (sort keys %countries) {
    my %our_mirrors;
    foreach my $id (@{ $countries{$country} }) {
      if (defined $mirror[$id]{method}{"$archive_name_lc-ftp"} || 
          defined $mirror[$id]{method}{"$archive_name_lc-http"} || 
          defined $mirror[$id]{method}{"$archive_name_lc-rsync"}) {
            $our_mirrors{$id} = 1;
      }
    }
    next unless (keys %our_mirrors);
    print "<tr class=\"country\"><th colspan=\"5\">$country</th></tr>\n";
    foreach my $id (@{ $countries_sorted{$country} }) {
      next unless (exists $our_mirrors{$id});
      print "<tr><th>$mirror[$id]{site}</th>";
      print "<td>";
      if (defined $mirror[$id]{method}{"$archive_name_lc-ftp"}) {
        print "<a rel=\"nofollow\" href=\"ftp://$mirror[$id]{site}$mirror[$id]{method}{\"$archive_name_lc-ftp\"}\">";
        print $mirror[$id]{method}{"$archive_name_lc-ftp"};
        print "</a>\n";
      }
      print "</td>\n";
      print "<td>";
      if (defined $mirror[$id]{method}{"$archive_name_lc-http"}) {
        print "<a rel=\"nofollow\" href=\"http://$mirror[$id]{site}$mirror[$id]{method}{\"$archive_name_lc-http\"}\">";
        print $mirror[$id]{method}{"$archive_name_lc-http"};
        print "</a>\n";
      }
      print "</td>\n";
      print "<td>";
      if (defined $mirror[$id]{method}{"$archive_name_lc-rsync"}) {
        print "<a href=\"rsync://$mirror[$id]{site}/$mirror[$id]{method}{\"$archive_name_lc-rsync\"}\">";
        print $mirror[$id]{method}{"$archive_name_lc-rsync"};
        print "</a>\n";
      }
      print "</td>\n";
      print "<td>";
      if (exists $mirror[$id]{"$archive_name"}) {
        print join(" ", sort @{$mirror[$id]{$archive_name}});
      } else {
        print " all";
      }
      print "</td>\n</tr>\n";
    }
  }
  print "</tbody>\n</table>\n";
}

######### Begin main routine ###########################

if (defined $help) {
  print_help();
  exit;
}

open SRC, "<:utf8", $mirror_source or
  die "Error: problem opening mirror source file, $mirror_source\n"
     ."Use the -m option?\n";

my $current = '';
while (<SRC>) {
  chomp;
  if (/^$/ && $current eq '') {
    next;
  } elsif (/^$/) {
    process_line($INPUT_LINE_NUMBER, $current);
    $current = '';
    next;
  } elsif (/^\s+(.*)$/) { # add line to current entry
    $current .= "\n$1";
  } elsif (/^[\w-]+:\s/) {
    if ($current ne "") { # need to process previous line
      process_line($INPUT_LINE_NUMBER, $current);
    }
    $current = $_;
  } else {
    die "Error: unknown format on line $INPUT_LINE_NUMBER:\n$_\n";
  }
}
if ($current ne "") {
  process_line($INPUT_LINE_NUMBER, $current);
}

# Remove filtered mirrors.
my @filtered;
foreach my $id (0..$#mirror) {
  if ($mirror[$id]{filtered}) {
    push @filtered, $id;
  }
}
foreach my $id (reverse @filtered) { # reverse order so indexes are valid
  splice(@mirror, $id, 1);
}

# count the number of mirrors
# the masterlist parser's $count included the filtered sites
$count = @mirror;

# Create arrays of countries, with their mirrors.
foreach my $id (0..$#mirror) {
  if (exists $mirror[$id]{country}) {
    push @{ $countries{ $mirror[$id]{country} } }, $id;
    if (exists $mirror[$id]{sponsor} && keys %{$mirror[$id]{method}}) {
      push @{ $countries_sponsors{ $mirror[$id]{country} } }, $id;
    }
  } elsif ($mirror[$id]{type} =~/^(GeoDNS|RoundRobinDNS)$/i) {
    # TODO these are not currently displayed anywhere
  } else {
    warn "found a mirror without a country, wtf? " . $mirror[$id]{site} .", defined at line ". $mirror[$id]{_lno};
  }
  # we'll also use this opportunity to help create a references
  # between sites which are connected with Includes:
  if (exists $mirror[$id]{includes}) {
    foreach my $includedsite (@{ $mirror[$id]{includes} }) {
      $includedsites{$includedsite} = $mirror[$id]{site};
    }
  }
}

# Sort the country info arrays to first list the official sites,
# then the unofficial sites, but exclude special Debian sites
foreach my $country (sort keys %countries) {
  my %countries_sorted_o; my %countries_sorted_u;
  foreach my $id (@{ $countries{$country} }) {
    if ($mirror[$id]{site} =~ /$officialsiteregex/) {
      push @{ $countries_sorted_o{$country} }, $id;
    } elsif ($mirror[$id]{site} !~ /$internalsiteregex/) {
      push @{ $countries_sorted_u{$country} }, $id;
    }
    # using the opportunity to add the Included-in: back-reference
    if (exists $includedsites{ $mirror[$id]{site} }) {
      push @{ $mirror[$id]{'included-in'} }, $includedsites{ $mirror[$id]{site} };
    }
  }
  # merge the reordered lists into %countries_sorted
  # (there's got to be a cleaner way to do this, but hey)
  foreach my $id (@{ $countries_sorted_o{$country} }) {
    push @{ $countries_sorted{$country} }, $id;
  }
  undef %countries_sorted_o;
  foreach my $id (@{ $countries_sorted_u{$country} }) {
    push @{ $countries_sorted{$country} }, $id;
  }
  undef %countries_sorted_u;
}

if ($output_type eq 'html') {
  header();
  intro('html');
  primary_mirrors('html');
  secondary_mirrors('html');
  footer_stuff('html', $count);
  trailer();
} elsif ($output_type eq 'text') {
  intro('text');
  primary_mirrors('text');
  secondary_mirrors('text');
  footer_stuff('text', $count);
} elsif ($output_type eq 'wml-primary') {
  primary_mirrors('wml');
} elsif ($output_type eq 'wml-secondary') {
  secondary_mirrors('wml');
} elsif ($output_type eq 'wml-footer') {
  footer_stuff('wml', $count);
} elsif ($output_type eq 'apt') {
  header();
  print "<pre>\n";
  aptlines();
  print "</pre>\n";
  trailer();
} elsif ($output_type eq 'fullmethods') { # this is likely obsolete
  header();
  access_methods();
  full_listing('html');
  footer_stuff('html', $count);
  trailer();
} elsif ($output_type eq 'wml-full') {
  full_listing('wml');
  footer_stuff('wml', $count);
} elsif ($output_type eq 'compact-old') {
  compact_list('old', 'sitecountry');
} elsif ($output_type eq 'officialsponsors') {
  primary_mirror_sponsors();
} elsif ($output_type eq 'sponsors') {
  mirror_sponsors();
} elsif ($output_type eq 'cdimages-httpftp') {
  cdimage_mirrors("httpftp");
} elsif ($output_type eq 'cdimages-rsync') {
  cdimage_mirrors("rsync");
} else {
  die "Error: unknown output type requested, $output_type\n";
}

sub print_help {
  print <<END;
Usage: $0 [mt|--type type] [-m|--mirror mirror_list_source]

`mirror_list_source\' is usually the Mirrors.masterlist file
`type\' can be one of:
    html      (the default)
    text
    wml-primary
    wml-secondary
    wml-footer
    apt
    fullmethods
    officialsponsors
    sponsors
    cdimages-httpftp
    cdimages-rsync
    nsupdate
END
}
