#!/usr/local/bin/perl

# marcread.pl
# desc: provides human readable output for marc format file (Voyager command)
# wordsettings: 
# end_autoz

# written by Roy Zimmer, Western Michigan University

if ($#ARGV == -1) {usage();}

$marcfile = $ARGV[0];
$fopen = sprintf("Cannot open file %s for input\n", $marcfile);
open(marcfile, $marcfile) or die $fopen;
@marclines = <marcfile>;
close(marcfile);

$marcstuff = '';
$idx = 0;
while ($idx < @marclines)
{
  $marcstuff = $marcstuff . $marclines[$idx++];
}
@marcrec = split /\x1d/, $marcstuff;


$idx = 0;
while ($idx < @marcrec)
#while ($idx < 2)
{
  $leader = substr($marcrec[$idx], 0, 24);
  if ($idx != 0) {printf("\n");}
  printf("LDR:%s\n", $leader);
  $reclen = substr($marcrec[$idx], 1, 5);
  $baseaddr = substr($marcrec[$idx], 12, 5) - 1;
  $strptr = 24;
  while ($strptr < $baseaddr-1)
  {
    $tagctr++;
    $tagid = substr($marcrec[$idx], $strptr, 3);
    $taglen = substr($marcrec[$idx], $strptr+3, 4);
    $offset = substr($marcrec[$idx], $strptr+7, 5);
    $tagdata = substr($marcrec[$idx], $baseaddr+$offset, $taglen);
    $tagdata =~ s/\x1f[a-z0-9]/ \|$& /g;     # use " |x " for subfield ind,
    $tagdata =~ s/\x1f//g;                   #  remove original subfield ind,
    $tagdata =~ s/\x1e//g;                   #  remove field ind,
    if (substr($tagdata, 2, 2) eq " |")      #  & remove the "1st" space in the line
      {$tagdata = substr($tagdata, 0, 2) . substr($tagdata, 3);}
    printf("%3s:%4s:%5s:%s\n", $tagid, $taglen, $offset, $tagdata);
    $strptr+= 12;
  }
  $idx++;
}
if ($idx > 1) {$plural = "s read";}
else {$plural = " read";}
printf ("\n<<%d Marc record%s>>\n\n", $idx, $plural);

sub usage()
{
  printf ("\nUsage: marcread.pl filename\n");
  printf ("       where filename indicates the marc file to be read.\n");
  printf ("       Output is to screen.\n");
  exit(0);
}
