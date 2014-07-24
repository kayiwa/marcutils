#!/usr/local/bin/perl

# marcnth.pl

# Retrieve 1 or more records, starting at record N, from a
# MARC file, or one that is in marcread format.
# The file format is automatically detected.
# Output is in marcread format, or in MARC format if the
# 'raw' parameter is used and the input file is a MARC file.
# marcread is available from:
#    http://homepages.wmich.edu/~zimmer/marc_index.html

use strict;
use Getopt::Long;
use autodie;

my ($startrec, $howmany, $infile, $raw, $fopen, $test);
$howmany = 1;

if ((@ARGV < 1) or (! GetOptions('startrec=i' => \$startrec,
                                 'howmany=i' => \$howmany,
                                 'infile=s' => \$infile,
                                 'raw' => \$raw)))
  {usage();}
if (($startrec == 0) or ($infile eq '')) {usage();}

open(INFILE, "<", $infile);
read(INFILE, $test, 30);
close(INFILE);

if ((substr($test, 0, 3) eq 'LDR') and ($raw))
  {print "\nThe -raw- parameter has no effect on non-MARC files.\n\n";}

# rudimentary file format check; route accordingly
if    (substr($test, 20, 4) eq '4500') {gomarcfmt();}
elsif (substr($test,  0, 3) eq 'LDR')  {goreadfmt();}
else
{
  print "\nFile <$infile> appears to be neither MARC nor marcread format.\n\n";
  exit(1);
}


sub gomarcfmt
{
  my ($marcrec, $leader, $reclen, $baseaddr, $strptr, $tagid, $taglen, $offset, $tagdata);
  my $recctr = 1;
  $/ = chr(0x1d);

  open(INFILE, "<", $infile);

  # go to desired starting record
  while (($marcrec = <INFILE>) and ($recctr != $startrec)) {$recctr++;}

  # unless specified, default is 1
  while ($howmany > 0)
  {
    if (!$raw)
    {
      $leader = substr($marcrec, 0, 24);
      printf("LDR:%s\n", $leader);
      $reclen = substr($marcrec, 1, 5);
      $baseaddr = substr($marcrec, 12, 5) - 1;
      $strptr = 24;
      while ($strptr < $baseaddr-1)
      {
        $tagid = substr($marcrec, $strptr, 3);
        $taglen = substr($marcrec, $strptr+3, 4);
        $offset = substr($marcrec, $strptr+7, 5);
        $tagdata = substr($marcrec, $baseaddr+$offset, $taglen);
        $tagdata =~ s/\x1f[a-z0-9]/ \|$& /g;     # use " |x " for subfield ind,
        $tagdata =~ s/\x1f//g;                   #  remove original subfield ind,
        $tagdata =~ s/\x1e//g;                   #  remove field ind,
        if (substr($tagdata, 2, 2) eq " |")      #  & remove the "1st" space in the line
          {$tagdata = substr($tagdata, 0, 2) . substr($tagdata, 3);}
        printf("%3s:%4s:%5s:%s\n", $tagid, $taglen, $offset, $tagdata);
        $strptr+= 12;
      }
     print "\n";
    }
    else {print $marcrec;}   # raw marc format

    if (!($marcrec = <INFILE>)) {last;}
    $howmany--;
  }
  close(INFILE);
}

sub goreadfmt
{
  my ($inrec);
  my $recctr = 0;

  open(INFILE, "<", $infile);
  $inrec = <INFILE>;
  while (1 == 1)
  {
    if ($inrec =~ /^LDR/) {$recctr++;}
    if ($recctr == $startrec) {last;}
    if (!($inrec = <INFILE>)) {last;}
  }
  # will get here unless at EOF (no leading 'LDR'; corrupt format...)
  if ($recctr == $startrec)
  {
    print $inrec;
    while ($inrec = <INFILE>)
    {
      if ($inrec =~ /^LDR/) {$howmany--;}
      if ($howmany == 0) {last;}
      # if near EOF, also ignore record count line
      if (($inrec ne '') and ($inrec !~ /^<</)) {print $inrec;}
    }
  }
  close(INFILE);
}


sub usage
{
  print <<ENDUSAGE;

Usage: marcnth   -infile=inputfilename
                 -startrec=N1
               [ -howmany=N2 ]
               [ -raw ]
    -infile is required. You must specify a file to look at. It can be
    a MARC file, or a "marcread" file which is a MARC file that has been
    converted to human-readble format by the marcread utility (from
    http://homepages.wmich.edu/~zimmer/marcindex.html). The file type is
    automatically detected.

    -startrec is required. Here you indicate the number of the record to
    get or where you want to start getting. If you want the fifth record,
    enter 5, for example.

    -howmany is optional. If not used, it defaults to 1 (one). If you want
    more than one record, specify that number here.

    -raw is optional, and does not require a value. If present, and you are
    looking at a MARC format file, it will return record data in MARC format
    instead of human-readable format.
    
ENDUSAGE
  exit(0);
}
