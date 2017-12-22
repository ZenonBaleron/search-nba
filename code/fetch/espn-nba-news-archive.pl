#!/usr/bin/env perl
#----------------------------------------------------------------------------
## Parser for NBA articles aggregated at espn.com
#----------------------------------------------------------------------------
# Takes two arguments: --year and --month
# If arguments are absent, then current year and month is used.
# Fetches all documents listed for the given month/year combination, parses
# them, and produces a file corpus out of that month's articles.
#----------------------------------------------------------------------------

use strict;
use warnings;
use feature qw(say);

use Carp;
use Cwd 'abs_path';
use Digest::MD5 'md5_hex';
use Getopt::Long;
use Fcntl qw(O_RDWR O_CREAT);
use File::Basename;
use File::Path qw(make_path remove_tree);
use File::Spec;
use LWP::Simple;
use LWP::UserAgent;
use POSIX;
use Tie::File;
use Time::Piece;
use XML::LibXML;

$| = 1;

### get the absolute path of this script, so relative paths can be formed to other resources
my $ScriptDir = dirname(__FILE__);
### Corpus Metadata file
my $DateTime = strftime("%Y%m%d%H%M%S", gmtime(time));
my $CorpusTag = 'espn-nba-news-archive';
my $CorpusDir = abs_path("$ScriptDir/../../data/corpus/${CorpusTag}.$DateTime");
my $CorpusDAT = "$CorpusDir/metadata.dat";
my $FileList  = "$CorpusDir/nba-full-corpus.txt";

### Command-line options
my ($Month,$Year,$Limit);
GetOptions(
  # year and month dictate the entry-point URL that lists article links for that month
  "year=i"  => \$Year,
  "month=i" => \$Month,
  "limit=i" => \$Limit,
) or die("Error in command line arguments\n");
$Month = $Month ? --$Month : (localtime)[4];
$Year  = $Year  ?   $Year  : (localtime)[5]+1900;
$Limit = $Limit ?   $Limit : 0;

my %daylight_lookup = (
  2003 => [ 3,  6,  9, 26 ],
  2004 => [ 3,  4,  9, 31 ],
  2005 => [ 3,  3,  9, 30 ],
  2006 => [ 3,  2,  9, 29 ],
  2007 => [ 2, 11, 10,  4 ],
  2008 => [ 2,  9, 10,  2 ],
  2009 => [ 2,  8, 10,  1 ],
  2010 => [ 2, 14, 10,  7 ],
  2011 => [ 2, 13, 10,  6 ],
  2012 => [ 2, 11, 10,  4 ],
  2013 => [ 2, 10, 10,  3 ],
  2014 => [ 2,  9, 10,  2 ],
  2015 => [ 2,  8, 10,  1 ],
  2016 => [ 2, 13, 10,  6 ],
  2017 => [ 2, 12, 10,  5 ],
  2018 => [ 2, 11, 10,  4 ],
  2019 => [ 2, 10, 10,  3 ],
  2020 => [ 2,  8, 10,  1 ],
);


### These variables can be reused for every page visited below
my ($URL,$Content,$DOM);

### Form the URL, get the page, parse the article links
my @MonthNames = qw(january february march april may june july august september october november december);
my $MonthName = $MonthNames[$Month];
$URL = "http://www.espn.com/nba/news/archive/_/month/$MonthName/year/$Year";
say "Processing URL: $URL";
$Content = get_retry_wait($URL,1000,60);
$DOM = XML::LibXML->load_html(string => $Content, recover => 2);

my %DOC;
my $doc_url;
foreach my $elem ($DOM->findnodes('//div[contains(@class,"article")]//ul/li')) {
  my $text = $elem->to_literal();
  my $a    = $elem->getChildrenByTagName('a');
  $doc_url = $a->[0]->getAttribute('href');
  parse_article_reference($text);
}
say "Article references found: " . scalar(keys(%DOC));

make_path($CorpusDir) unless -d $CorpusDir;

open(my $metadata , '>' , $CorpusDAT) or croak "Unable to open $CorpusDAT";
open(my $filelist , '>' , $FileList)  or croak "Unable to open $FileList";

my $flag_get_success;
my $count_articles_parsed = 0;
foreach my $doc_url (sort keys %DOC) {
  next if $doc_url =~ m|insider|;

  # say localtime . " [$Year $MonthName] $doc_url";

  my @p = parse_article($doc_url);
  next unless $flag_get_success;

  $DOC{$doc_url}{md5_url} = md5_hex($doc_url);

  # Entry in the metadata.dat file
  my $MetadataText = join("\t",
    $DOC{$doc_url}{md5_url},
    $DOC{$doc_url}{date_pub},
    $DOC{$doc_url}{date_got},
    $CorpusTag,
    $doc_url,
  );
  say $metadata $MetadataText or croak "Unable to write $CorpusDAT";

  # Entry in the <list>-full-corpus.txt file
  say $filelist '[none] '.$DOC{$doc_url}{md5_url};

  # Article content file added to corpus
  my $ArticlePath = "$CorpusDir/" . $DOC{$doc_url}{md5_url};
  my $ArticleText = join("\n",@p);
  open(my $fh , '>' , $ArticlePath) or croak "Unable to open $ArticlePath";
  say $fh $ArticleText or croak "Unable to open $ArticlePath";
  close $fh;

  last if ++$count_articles_parsed == $Limit;
}
say "Total articles parsed: $count_articles_parsed";

close $metadata;
close $filelist;

say "Corpus Metadata: $CorpusDAT";

sub parse_article {
  my $doc_url = shift;
  $Content = get_retry_wait($doc_url, 5, 5);
  return () unless $flag_get_success;
  $DOM = XML::LibXML->load_html(string => $Content, recover => 2);
  my @p;
  foreach my $elem ($DOM->findnodes('//div[contains(@class,"article-body")][1]/p')) {
    last if $elem->to_literal() =~ m|---|;
    push @p, $elem->to_literal();
  }
  return @p;
}

# (December 1, 2017, 3:02 AM ET)
sub parse_article_reference {
	my $title = shift;
  $title =~ s/\n/ /;
  my $MonthRegex = '(' . join('|',map(ucfirst,@MonthNames)) . ')';
  $title =~ /^(.+)\s+\((($MonthRegex).+) ET\)/;
  my $title_text = $1;
  my $title_date = $2;
	my $title_date_tp = Time::Piece->strptime($title_date, "%B %d , %Y , %R %p");
  #say $title;
  #say $title_text;
  #say $title_date;
  #say $title_date_tp;

  my $Y = $title_date_tp->year;
  # Find boundries in currently processed year when EST starts (0) and ends (1)
  my $dt_EST0  = Time::Piece->strptime(
		"$Y-" . ($daylight_lookup{$Y}[0]+1) . "-$daylight_lookup{$Y}[1] 02:00",
		"%Y-%m-%d %R"
  );
  my $dt_EST1  = Time::Piece->strptime(
    "$Y-" . ($daylight_lookup{$Y}[2]+1) . "-$daylight_lookup{$Y}[3] 02:00",
    "%Y-%m-%d %R"
  );
  # Decide timzeone offset, based on being in EST or outside of it (i.e. in EDT)
  if( $title_date_tp >= $dt_EST0 && $title_date_tp < $dt_EST1 ) {
    $title_date .= " -0500"; #EST
  }
  else {
    $title_date .= " -0400"; #EDT
  }
  # we have decoded 'ET' into an actual offset, so now let's parse into gmt
  my $title_date_gmt_tp = gmtime(Time::Piece->strptime($title_date, "%B %d, %Y, %R %p %z"));

  $DOC{$doc_url}{title}    = $title_text;
  $DOC{$doc_url}{date_pub} = $title_date_gmt_tp->epoch;
  $DOC{$doc_url}{date_got} = time; 
}

# get url, retry a few times, with a wait period (in seconds) between each try
sub get_retry_wait {
  my $URL     = shift;
  my $retries = shift;
  my $wait    = shift;
  my $content;
  my $browser = LWP::UserAgent->new;
  $browser->timeout(180);
  for ( my $i=1; $i<=$retries; $i++ ) {
    sleep int(rand($wait));
    my $response = $browser->get($URL);
    say $response->status_line . ": $URL";
    if ($response->is_success) {
      $flag_get_success = 1;
      return $response->decoded_content if $response->decoded_content;
    }
  }
  $flag_get_success = 0;
}
