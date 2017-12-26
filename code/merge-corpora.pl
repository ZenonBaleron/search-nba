#!/usr/bin/env perl
#----------------------------------------------------------------------------
## Utility that merges two meta-toolkit file corpora.
#----------------------------------------------------------------------------
# This script takes two arguments: --major and --minor
# minor corpus will be merged into the major corpus.
# Assumed field structure of the tsv Metadata file:
# <md5 of URL> <time published> <time retrieved> <source tag> <URL>
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

### Command-line options
my ($Major,$Minor,$Overwrite);
GetOptions(
  # minor corpus will be merged into the major corpus
  "major=s"  => \$Major,
  "minor=s" => \$Minor,
  "overwrite" => \$Overwrite,
) or die("Error in command line arguments\n");

### Get the absolute path of this script, so relative paths can be formed to other resources
my $ScriptDir = dirname(__FILE__);

### Read Metadata files for both corpora
my $MinorDir = abs_path("$ScriptDir/../data/corpus/$Minor");
my $MinorMetadataFile = "$MinorDir/metadata.dat";
my $MajorDir = abs_path("$ScriptDir/../data/corpus/$Major");
my $MajorMetadataFile = "$MajorDir/metadata.dat";
my $MajorFileListFile = "$MajorDir/nba-full-corpus.txt";
my %MAJOR = read_metadata_file($MajorMetadataFile);
my %MINOR = read_metadata_file($MinorMetadataFile);

say scalar(keys(%MAJOR)) . " " . scalar(keys(%MINOR));

sub read_metadata_file {
  my $FileName = shift;
  my %Hash;
  open(FILE , '<' , $FileName) or croak "Unable to open corpus metadata file $FileName";
  foreach my $line (<FILE>) {
    chomp($line);
    my ($md5,$tpub,$tgot,$tag,$url) = split("\t",$line);
    $Hash{$md5}{md5_url} = $md5;
    $Hash{$md5}{date_pub} = $tpub;
    $Hash{$md5}{date_got} = $tgot;
    $Hash{$md5}{src_tag} = $tag;
    $Hash{$md5}{url} = $url;
  }
  close FILE;
  return %Hash;
}

### Verify consistency of each corpora
my %SuspectDocs;
verify_corpus_integrity($MinorDir, \%MINOR);
verify_corpus_integrity($MajorDir, \%MAJOR);

say "List of Suspect docs:" if scalar(keys(%SuspectDocs))

foreach my $key (sort(keys(%SuspectDocs))) {
  say "$key $SuspectDocs{$key}";
}

sub verify_corpus_integrity {
  my $dir = shift;
  my $dat = shift;
  # check that all documents listed in the metadata file are present as files
  my $keys_dat;
  foreach my $key (keys %{$dat}) {
    my $file = "$dir/$key";
    unless ( -e $file ) { $SuspectDocs{$key} = "Document does not exist: $file"; next; }
    if ( -z $file ) { $SuspectDocs{$key} = "Document is empty: $file"; next; }
    ++$keys_dat;
  }
  # check that all document files present are listed in the metadata
  my $keys_dir;
  opendir(DIR, $dir) or warn "Can't open $dir";
  while (my $file = readdir(DIR)) {
    next if $file =~ m|^\.{1,2}$|;
    next if $file =~ m|^metadata|;
    next if $file =~ m|full-corpus|;
    next if $file =~ m|toml$|;

    unless ( defined $dat->{$file}{url} ) { $SuspectDocs{$file} = "Document not described: $file"; next; }
    ++$keys_dir;
  }
  closedir(DIR);
  # compare the count of docs in the metadata file with actual count of docs in directory
  say "DAT:$keys_dat DIR:$keys_dir";
}

### Merge Minor into Major

# Make a backup of Major
system("cp -r $MajorDir $MajorDir-$$");
say "Backup: $MajorDir-$$";

# Copy documents over
my %SkippedDocs;
foreach my $key (keys %MINOR) {
  if ( defined $SuspectDocs{$key} ) {
    $SkippedDocs{$key} = "$key Suspect: $SuspectDocs{$key}";
  }
  elsif ( defined $MAJOR{$key}{url} and ! $Overwrite) {
    $SkippedDocs{$key} = "$key Overwrite";
  }
  else {
    system("cp -p '$MinorDir/$key' '$MajorDir/$key'");
    $MAJOR{$key}{md5_url}  = $MINOR{$key}{md5_url};
    $MAJOR{$key}{date_pub} = $MINOR{$key}{date_pub};
    $MAJOR{$key}{date_got} = $MINOR{$key}{date_got};
    $MAJOR{$key}{src_tag}  = $MINOR{$key}{src_tag};
    $MAJOR{$key}{url}      = $MINOR{$key}{url};
  }
}

# Overwrite metadata
system("rm $MajorMetadataFile");
system("rm $MajorFileListFile");
open(FILE_MD , '>' , $MajorMetadataFile) or croak "Unable to open corpus metadata file $MajorMetadataFile";
open(FILE_FL , '>' , $MajorFileListFile) or croak "Unable to open corpus metadata file $MajorFileListFile";
foreach my $md5 (sort(keys(%MAJOR))) {
  say FILE_MD join("\t",
    $MAJOR{$md5}{md5_url},
    $MAJOR{$md5}{date_pub},
    $MAJOR{$md5}{date_got},
    $MAJOR{$md5}{src_tag},
    $MAJOR{$md5}{url}
  );
  say FILE_FL '[none] '.$MAJOR{$md5}{md5_url};
}
close FILE_MD;
close FILE_FL;
