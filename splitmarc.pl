#!/usr/local/bin/perl

# splitmarc.pl
# desc: marc file splitter (Voyager command)
# wordsettings: 
# end_autoz

use strict;

if ($#ARGV < 1) {usage();}

my ($ctr, $fctr, $fileout, $marcrec, $it1, $it2);

$/ = chr(0x1d);   # MARC end-of-record char for input

$ctr = 0;
$fctr = 1;

open(ofile, ">$ARGV[1].$fctr");
open(ifile, $ARGV[0]);
while ($marcrec = <ifile>)
{
  if ($ctr <= $ARGV[2]) {print ofile $marcrec;}
  $ctr++;
  if ($ctr == $ARGV[2])
  {
    close(ofile);
    $fctr++;
    open(ofile, ">$ARGV[1].$fctr");
    $ctr = 0;
  }
}
close(ifile);
close(ofile);

$it1 = $ARGV[1] . ".1";
$it2 = $ARGV[1] . "." . $fctr;
if ($fctr > 1)
  {print "Output files: $it1-$it2\n";}
else
  {print "Output file: $it1\n";}


sub usage()
{
  print "\nUsage: splitmarc infilename outfilename chunksize\n";
  print "   Splits file specified by <infilename> into chunks\n";
  print "   containing the number of lines specified by chunksize.\n";
  print "   An incrementing counter is appended to <outfilename>\n";
  print "   for each chunk so created.\n";
  print "\n   Example:\n";
  print "   splitmarc abcin.this abcthis.out 100\n";
  print "   This would create N files abcthis.out.1, abcthis.out.2, etc.,\n";
  print "   each 100 lines in size, as many as necessary to divide\n";
  print "   abcin.this as specified.\n";
  exit(0);
}
