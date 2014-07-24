#!/usr/local/bin/perl

# marcunread.pl

use strict;
use autodie;

sub createnewrec;
sub usage;

# handle command line parameters
my ($verbosehelp, $force, $forcemost) = (0, 0, 0);
if ($#ARGV == 0)
{
  if (uc($ARGV[0]) eq "VERBOSEHELP") {$verbosehelp = 1;}
  usage();
}
if ($#ARGV <= 0) {usage();}
my $infile  = $ARGV[0];
my $outfile = $ARGV[1];
if ($#ARGV == 2)
{
  if ((uc($ARGV[2]) eq "FORCE"))     {$force = 1;}
  if ((uc($ARGV[2]) eq "FORCEMOST")) {$forcemost = 1;}
}

my ($line, $leader, $tag, $tagsize, $tagcontents, $newrec);
my $recctr = 0;
my (@tags, @tagdata, @taglen);

my $subfdelim = chr(0x1f);
my $fdelim = chr(0x1e);
my $recdelim = chr(0x1d);


open(OUTFILE, ">", $outfile);
open(INFILE, "<", $infile);

while ($line = <INFILE>)
{
  chomp $line;
  $line =~ s/\t|\n|\f|\r//g;   # a bit of insurance
  $recctr++;

  # in marcread format; a line starting with "<<" appears
  # near the end of the file: <<N records read>>
  if (($line ne '') and ($line !~ /^<</))
  {
    # expecting leader data; ignore non-MARC information;
    # rudimentary leader validation
    if (!$forcemost)
    {
      if ($line !~ /^LDR/) {print "LeaDeR problem found at line $recctr...exiting\n\n"; exit(1);}
      $leader = substr($line, 4);
      if ($leader !~ /^\d{5}.{5}22\d{5}.{3}4500$/)
        {print "Bad leader found at line $recctr...exiting\n\n"; exit(1);}
    }

    $line = <INFILE>;
    chomp $line;
    $line =~ s/\t|\n|\f|\r//g;
    $recctr++;
  }

  # after the leader, get the rest of the record
  while (($line ne '') and ($line !~ /^<</))
  {
    if (!$forcemost)
    {
      if ($line !~ /^\d{3}/) {print "Bad tag found at line $recctr...exiting\n\n"; exit(1);}
    }
    ($tag, $tagcontents) = ($line =~ /^(\d{3}).{12}(.+)/);

    if (!$force and !$forcemost)
    {
      if (($tag eq '005') and ($tagcontents !~ /\d{14}\.\d/))
        {print "Bad 005 field found at line $recctr...exiting\n\n"; exit(1);}
      if (($tag eq '006') and (length($tagcontents)) != 35)
        {print "Bad 006 field found at line $recctr...exiting\n\n"; exit(1);}
      if (($tag eq '007') and (length($tagcontents)) != 22)
        {print "Bad 007 field found at line $recctr...exiting\n\n"; exit(1);}
      if (($tag eq '008') and (length($tagcontents)) != 40)
        {print "Bad 008 field found at line $recctr...exiting\n\n"; exit(1);}    
    }

    # undo readability formatting for subfields; also perform indicator check
    if ($tag ge '010')
    {
      $tagcontents = substr($tagcontents, 0, 2) . $subfdelim .
                     substr($tagcontents, 3, 1) . substr($tagcontents, 5);
      $tagcontents =~ s/ \|(.) /$subfdelim$1/g;

      if (!$force and !$forcemost)
      {
        if ($tagcontents !~ /^([a-z]|\d| ){2}/)
          {print "Bad indicator character found at line $recctr...exiting\n\n"; exit(1);}
      }
    }

    # check for field size exceeding MARC definition
    $tagsize = length($tagcontents) + 1;
    if ($tagsize > 9999)
      {print "Excessively long field found at line $recctr...exiting\n\n"; exit(1);}

    # accumulate this record's data
    push @tags,    $tag;
    push @tagdata, $tagcontents;
    push @taglen,  $tagsize;

    $line = <INFILE>;
    chomp $line;
    $line =~ s/\t|\n|\f|\r//g;
    $recctr++;
  }

  # at end of logical MARC record? output MARC record in that case
  if ($line eq '')
  {
    $newrec = createnewrec($leader, \@tags, \@taglen, \@tagdata);
    print OUTFILE $newrec;
    @tags = @taglen = @tagdata = ();
  }
  if ($line =~ /^<</) {last;}   # we *are* done
}
close(INFILE);
close(OUTFILE);


sub createnewrec()
{
  my ($leader, $tagid_array, $taglen_array, $tagdata_array) = @_;
  my @tagids = @$tagid_array;
  my @taglens = @$taglen_array;
  my @tagdata = @$tagdata_array;

  my @offsets;
  my $newmarcrec = '';
  my $directory = '';
  my ($baseaddress, $idx, $reclen);
  my $offset = 0;
  
  # data starts after leader and tags directory
  $baseaddress = 24 + (scalar(@tagids) * 12) + 1;

  # create the data directory, and the record; get the record length
  for ($idx=0; $idx<@tagids; $idx++)
  {
    $offset += $taglens[$idx-1] unless ($idx == 0);
    $directory .= sprintf("%3.3d%4.4d%5.5d", $tagids[$idx], $taglens[$idx], $offset);
  }
  $newmarcrec = $leader . $directory;
  for ($idx=0; $idx<@tagids; $idx++)
    {$newmarcrec .= $fdelim . $tagdata[$idx];}
  $newmarcrec .= $fdelim . $recdelim;
  $reclen = length($newmarcrec);

  # update the leader
  substr($newmarcrec, 0, 5) = sprintf("%5.5d", $reclen);
  substr($newmarcrec, 12, 5) = sprintf("%5.5d", $baseaddress);

  if ($reclen > 99999)
    {print "Excessively long MARC record \"found\" around line $recctr...exiting\n\n"; exit(1);}

  return $newmarcrec;
}


sub usage()
{
  if ($verbosehelp)
  {
    print <<ENDVERBOSE;

marcunread in detail:

Problem:
  You need to make certain miscellaneous edits to various records in
  a MARC file.

Solution:
  1. Run it through marcread to create a human-readable copy of the file:

       marcread.pl yourmarcfile > yourmarcfile.read

     (get marcread from: http://homepages.wmich.edu/~zimmer/marcindex.html)

  2. Since the marcread format file is a text file, you are free to use the
     editor of your choice to make the needed changes. Example:

       vi(m) yourmarcfile.read

  3. Then run marcunread on that file:

       marcunread.pl yourmarcfile.read yourNewmarcfile


This is a sample line from marcread output:

  300:0023:00551:  |a [1] leaf ; |c 24 cm.

Explanation:
    300 - field
   0023 - field length
  00551 - field offset
      | - the pipe character indicates a subfield follows
  The two columns after the "00551:" above are for the indicators,
    for fields that can have them; else it's all field data.
  The first, and only the first subfield in a field, consists of "|x ",
    where the 'x' here is replaced by 'a'. Note the trailing space.
  All other subfields in a field are in the format " |x ", which is
    leading space, the subfield character, x to specify the subfield,
    followed by a trailing space.

Rules:
  1. Never change the 'LDR' part that indicates a record leader.
  2. Take into account how subfields are shown. Changes you make must
     conform to "|x " (1st time) or " |x " (subsequent times) per field.
  3. You can safely make changes in the length and offset part of a
     record. marcunread ignores those columns. From the above example:

       :0023:00551:   (safe to change, as these columns are ignored)

     As marcunread converts the data, it dynamically computes the lengths,
     offsets, and leader changes for a record to correctly reconstitute
     the now changed MARC record.

CAUTION and WARNING:
marcunread performs very little MARC-related checking of what it's
converting, so be careful in what you do.

ENDVERBOSE
}

# plain old usage info
print <<ENDUSAGE;

Usage:  marcunread.pl verbosehelp

        marcunread.pl infile outfile [force | forcemost]

    Using the single parameter "verbosehelp" shows the expected usage
    scenario and details on how marcunread works.

    For routine use, you must supply an input file and output file.
    The input file (infile) is expected to be your edited
      marcread format file.
    The output file (outfile) will be the recreated MARC file that
      has your edits.

    marcunread does very rudimentary error checking. It will stop when
    encountering some MARC errors that often are tolerable.
    Using the option "force" makes marcunread go ahead anyway.
    Using the option "forcemost" will make marcunread proceed in all
    cases except when the MARC field or record length limits are
    exceeded.
    Exercise great caution when using either of these forcing options.
    They might get you beyond minor MARC errors, or they might result
    in a corrupt MARC file.
  
ENDUSAGE
  exit(0);
}
