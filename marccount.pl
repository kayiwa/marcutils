#!/usr/local/bin/perl

# marccount.pl
# desc: counts records in a marc file
# wordsettings: 
# end_autoz

# written by Roy Zimmer, Western Michigan University

if ($#ARGV == -1) {usage();}

$/ = chr(0x1d);
$mctr = 0;

$marcfile = $ARGV[0];
$fopen = sprintf("Cannot open file %s for input\n", $marcfile);
open(marcfile, $marcfile) or die $fopen;
while ($marcline = <marcfile>) {$mctr++;}
close(marcfile);

printf ("File %s contains %d records\n", $marcfile, $mctr);


sub usage
{
  printf ("\nUsage: marccount.pl filename\n");
  printf ("       where filename indicates the marc file whose records are to be counted.\n");
  printf ("       Output is to screen.\n");
  exit(0);
}
