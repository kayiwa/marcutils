#!/usr/local/bin/perl

### You will need to set this up for your installation.
### Assign appropriate values for the following:
$your_machine_name = "";
$user = "";
$pw = "";
$dbname = "";

# marcget.pl
# desc: extract marc data to standard output from Voyager database as
# desc: raw Marc records or human-readable data
# wordsettings: 
# end_autoz

# written by Roy Zimmer, Western Michigan University

use DBI;

# get input arguments
if ($#ARGV < 0) {usage();}
$searchtype = $ARGV[0];
$idstart = $ARGV[1];
$idend = $ARGV[2];
if ($#ARGV == 3) {$raw = $ARGV[3];}
if ($raw) {$raw = 1;}
else {$raw = 0;}
if (($searchtype ne "auth") and ($searchtype ne "bib") and ($searchtype ne "mfhd"))
  {usage();}

### connect to database
$dbh = DBI->connect('DBI:Oracle:host=$your_machine_name;sid=LIBR',
                    $user, $pw)
  or die "connecting: $DBI::errstr";

$sqlquery = sprintf("select %s_id,
                            record_segment,
                            seqnum
                     from $dbname.%s_data
                     where %s_id >= %s and %s_id <= %s
                     order by %s_id asc, seqnum desc",
                    $searchtype, $searchtype,
                    $searchtype, $idstart,
                    $searchtype, $idend,
                    $searchtype);

$sth = $dbh->prepare($sqlquery) or die "preparing query statement";
$rc = $sth->execute;

### usual assembly of marc data in reverse order (per sort in query)
###   by auth/bib/mfhd id
# shunt complete records to stdout (screen) for raw output, or
#   write to array for processing to get human-readable output
$marcstuff = "";
$marc = "";
$oldrec_id = 0;
while (($rec_id, $recseg, $seqnum) = $sth->fetchrow_array)
{
  if ($rec_id != $oldrec_id)
  {
    if (!$raw) {$marcstuff = $marcstuff . $marc;}
    else {print $marc;}
    $oldrec_id = $rec_id;
    $marc = $recseg;
  }
  else {$marc = $recseg . $marc;}
}
if (!$raw) {$marcstuff = $marcstuff . $marc;}
else {print $marc;}

$sth->finish;
$dbh->disconnect;

# if want human-readable output
if (!$raw)
{
  @marcrec = split /\x1d/, $marcstuff;

  $idx = 0;
  while ($idx < @marcrec)
  {
    $leader = substr($marcrec[$idx], 0, 24);
    if ($idx != 0) {printf("\n");}
    printf("LDR:%s\n", $leader);
    $baseaddr = substr($marcrec[$idx], 12, 5) - 1;
    $strptr = 24;
    while ($strptr < $baseaddr-1)
    {
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
}

sub usage()
{
  printf ("\nUsage: marcget.pl [auth | bib | mfhd] startID endID [raw]\n");
  printf ("       Pick one of the 3 data types.\n");
  printf ("       Specify record ID numbers; specified range is inclusive.\n");
  printf ("       Parameters must be in the above order.\n");
  printf ("       All parameters are required except for the last one.\n");
  printf ("       Program extracts marc data from blobs in Oracle.\n");
  printf ("       Output is human-formatted unless *raw* is specified\n");
  printf ("       and it goes to STDOUT.\n");
  exit(0);
}
