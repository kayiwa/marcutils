#!/usr/local/bin/perl

# marcedit.pl
# desc: add, remove, edit fields as specified in the marcedit.ini file
# desc: in the current directory
# desc: for details, see the ini file (Voyager command)
# wordsettings: 
# end_autoz

use strict;
use autodie;

my $inifile = "";

my $subfdelim = chr(0x1f);
my $fdelim = chr(0x1e);
my $recdelim = chr(0x1d);

my $marcrec = '';

my @addtag = ();
my @addtagdata = ();
my @deltag = ();
my @edittask = ();

my $fopen = "";
my $findspec = "";
my ($numfindelements, $findtag, $findl1yes, $findl2yes, $findl1no, $findl2no);
my ($findlooksubfield, $findsubfield, $findcase, $findsubdata);
my $findregex = "";
my $regexnormal = 1;
my $readonly = 0;
my $notfind = 0;
my $deleterecord = 0;
my $splitonunicode = 0;
my $unicodeyesfile = "unicode_yes.marc";
my $unicodenofile = "unicode_no.marc";

# if the actual text changes, need only change it here
my $replacesubfield =       "replacesubfield";
my $replacesubfieldalways = "replacesubfieldalways";
my $subfieldaddtobeg =      "subfieldaddtobeg";
my $addsubfield =           "addsubfield";
my $fieldaddtobeg =         "fieldaddtobeg";
my $changeindicator =       "changeindicator";
my $bracket245h =           "bracket245h";
my $changeleaderchar =      "changeleaderchar";
my $unicodesplit =          "unicodesplit";
my $dropsubfield =          "dropsubfield";

my $casematch = "casematch";
my $first = "first";
my $any = "any";
my $last = "last";
my $all = "all";

my $recordcount = 0;
my $findrecordctr = 0;
my $insrrecordctr = 0;
my $delerecordctr = 0;
my $resbrecordctr = 0;
my $sf2brecordctr = 0;
my $fa2brecordctr = 0;
my $chgirecordctr = 0;
my $adsfrecordctr = 0;
my $b245recordctr = 0;
my $uniyrecordctr = 0;
my $uninrecordctr = 0;
my $chglrecordctr = 0;
my $dsbfrecordctr = 0;

if ($#ARGV < 1) {usage();}

# let marcedit know what to do
if ($ARGV[2]) {$inifile = $ARGV[2];}
else {$inifile = "marcedit.ini";}
getini();

# check if splitting by unicode record is requested
# if so, also optionally accept output file name(s)
foreach my $etask (@edittask)
{
  my @msplit = split /\|/, $etask;
  if ($msplit[0] eq $unicodesplit)
  {
    $splitonunicode = 1;
    if ($msplit[1] ne "") {$unicodeyesfile = $msplit[1];}
    if ($msplit[2] ne "") {$unicodenofile = $msplit[2];}
  }
}

# set up normal output file if not splitting by unicode
if (!$splitonunicode)
{
  $fopen = sprintf("Cannot open %s for output\n", $ARGV[1]);
  open(fout, ">$ARGV[1]") or die $fopen;
}

$/ = chr(0x1d);   # for reading MARC files

my $marcfile = $ARGV[0];
$fopen = sprintf("Cannot open file %s for input\n", $marcfile);
open(marcfile, $marcfile) or die $fopen;

if ($splitonunicode)
{
  $fopen = sprintf("Cannot open file %s for output\n", $unicodeyesfile);
  open(unicodeyes, ">$unicodeyesfile") or die $fopen;
  $fopen = sprintf("Cannot open file %s for output\n", $unicodenofile);
  open(unicodeno, ">$unicodenofile") or die $fopen;
  while ($marcrec = <marcfile>)
  {
    $recordcount++;
    if (substr($marcrec, 9, 1) eq 'a')
    {
      print unicodeyes "$marcrec";
      $uniyrecordctr++;
    }
    else
    {
      print unicodeno "$marcrec";
      $uninrecordctr++;
    }
  }
  close(unicodeyes);
  close(unicodeno);
}
else     # normal marc processing
{
  # add, remove, and edit tags as applicable
  while ($marcrec = <marcfile>)
  {
    $recordcount++;

    # if FIND stanza is used, check if we want this record
    my $wantrecord = 1;
    if ($findspec)
    {
      $wantrecord = findrecord($marcrec);
      # if "not find", want all records not matching find spec
      if ($notfind) {$wantrecord = !$wantrecord;}
    }
    if ($wantrecord) {$findrecordctr++;}

    if (!$deleterecord)
    {
      if (($wantrecord) and (!$readonly))
      {
        # add tags
        my $addidx;
        for ($addidx=0; $addidx<@addtag; $addidx++)
          {$marcrec = inserttag($addtag[$addidx], $addtagdata[$addidx], $marcrec);}

        # remove tags
        foreach my $dtag (@deltag) {$marcrec = deletetag($dtag, $marcrec);}

        # edit tags
        foreach my $etask (@edittask) {$marcrec = edittag($etask, $marcrec);}

        print fout $marcrec;
      }
    }
    else
    {
      if ($wantrecord) {print fout $marcrec;}
    }
  }
  close(marcfile);
  close(fout);
}

# provide feedback on what was done
my $plural = '';
printf ("\n");
if ($recordcount == 1) {$plural = '';} else {$plural = 's';}
printf("%8.8s record%s read\n", $recordcount, $plural);

if ($findspec)
{
  if ($findrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s record%s found\n", $findrecordctr, $plural);
}

if ($insrrecordctr > 0)
{
  if ($insrrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s insertion-record%s processed\n", $insrrecordctr, $plural);
}

if ($delerecordctr > 0)
{
  if ($delerecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s deletion-record%s processed\n", $delerecordctr, $plural);
}

if ($sf2brecordctr > 0)
{
  if ($sf2brecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s subfield-add-to-beginning-record%s processed\n", $sf2brecordctr, $plural);
}

if ($adsfrecordctr > 0)
{
  if ($adsfrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s add-subfield-record%s processed\n", $adsfrecordctr, $plural);
}

if ($fa2brecordctr > 0)
{
  if ($fa2brecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s field-add-to-beginning-record%s processed\n", $fa2brecordctr, $plural);
}

if ($chgirecordctr > 0)
{
  if ($chgirecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s change-indicator-record%s processed\n", $chgirecordctr, $plural);
}

if ($b245recordctr > 0)
{
  if ($b245recordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s 245-|h-bracket-record%s processed\n", $b245recordctr, $plural);
}

if ($chglrecordctr > 0)
{
  if ($chglrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s change-leader-char-record%s processed\n", $chglrecordctr, $plural);
}

if ($dsbfrecordctr > 0)
{
  if ($dsbfrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s drop-subfield record%s processed\n", $dsbfrecordctr, $plural);
}

if ($resbrecordctr > 0)
{
  if ($resbrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s subfield-replace-record%s processed\n", $resbrecordctr, $plural);
}

if ($uniyrecordctr > 0)
{
  if ($uniyrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s unicode record%s output to %s\n", $uniyrecordctr, $plural, $unicodeyesfile);
}

if ($uninrecordctr > 0)
{
  if ($uninrecordctr == 1) {$plural = '';} else {$plural = 's';}
  printf("%8.8s non-unicode record%s output to %s\n", $uninrecordctr, $plural, $unicodenofile);
}

if (!$splitonunicode)
{
  printf ("\nCounts may exceed records read/found if records are processed\n");
  printf ("more than once, for example, if two insert specs are supplied.\n");
}


sub inserttag
{
  my ($addtag, $addtagdata, $oldmarcrec) = @_;
  my $newmarcrec = '';
  my $leader = '';
  my $newleader = '';
  my $baseaddr = 0;
  my $addtaglength = 0;
  my $mustinsert = 0;
  my $insertpoint = 0;
  my $append = 0;
  my $tagctr = -1;
  my $strptr = 24;
  my $tagidx = 0;
  my @tagid = ();
  my @taglen = ();
  my @offset = ();
  my @tagdata = ();

  $addtaglength = length($addtagdata);

  $leader = substr($oldmarcrec, 0, 24);
  $baseaddr = substr($oldmarcrec, 12, 5) - 1;

  # go through tags and find insertion point
  while ($strptr < $baseaddr-1)
  {
    $tagctr++;
    $tagid[$tagctr] = substr($oldmarcrec, $strptr, 3);
    $taglen[$tagctr] = substr($oldmarcrec, $strptr+3, 4);
    $offset[$tagctr] = substr($oldmarcrec, $strptr+7, 5);
    $tagdata[$tagctr] = substr($oldmarcrec, $baseaddr+$offset[$tagctr], $taglen[$tagctr]);

    # 1st time tag is greater than the current tag we have insertion point
    if ((($tagid[$tagctr] gt $addtag) or (($strptr+12) > ($baseaddr-1))) and (!$mustinsert))
    {
      $insertpoint = $tagctr;
      if (($strptr+12) > ($baseaddr-1)) {$append = 1;}
      $mustinsert = 1;
    }
    $strptr+= 12;
  }

  if ($mustinsert)
  {
    # modify record length
    $newleader = sprintf("%5.5d%s",
                         substr($leader,0,5)+$addtaglength+12, substr($leader,5));

    # modify base address
    $newleader = sprintf("%s%5.5d%s",
                         substr($newleader,0,12), substr($newleader,12,5)+12,
                         substr($newleader,17));

    # write leader and tag directory
    $newmarcrec = $newleader;
    for ($tagidx=0; $tagidx<=$tagctr; $tagidx++)
    {
      # add new tag
      if (($tagidx == $insertpoint) and (!$append))
      {
        if ($insertpoint == 0)
        {
          $newmarcrec .= sprintf ("%s%4.4d%5.5d",
                                  $addtag, $addtaglength, 0);
        }
        else
        {
          $newmarcrec .= sprintf ("%s%4.4d%5.5d",
                                  $addtag, $addtaglength, $offset[$tagidx-1]+$taglen[$tagidx-1]);
        }
      }
      if (($tagidx >= $insertpoint) and (!$append)) {$offset[$tagidx] += $addtaglength;}
      $newmarcrec .= sprintf ("%3.3d%4.4d%5.5d",
                              $tagid[$tagidx], $taglen[$tagidx], $offset[$tagidx]);
    }
    if ($append)
    {
      $newmarcrec .= sprintf ("%s%4.4d%5.5d",
                                $addtag, $addtaglength, $offset[$tagidx-1]+$taglen[$tagidx-1]);
    }

    if (!$append)
    {
      # write old data; to appear before new tag
      for ($tagidx=0; $tagidx<$insertpoint; $tagidx++) {$newmarcrec .= $tagdata[$tagidx];}

      # add new tag data
      $newmarcrec .= $addtagdata;

      # write rest of old data and we're done
      while ($tagidx <= $tagctr) {$newmarcrec .= $tagdata[$tagidx++];}
    }
    else   # tag goes at the end
    {
      # write old data; to appear before new tag
      for ($tagidx=0; $tagidx<@tagdata; $tagidx++) {$newmarcrec .= $tagdata[$tagidx];}

      # add new tag data
      $newmarcrec .= $addtagdata;
    }
    $newmarcrec .= sprintf ("$fdelim$recdelim");
    $insrrecordctr++;
    return $newmarcrec;
  }
  else {return $oldmarcrec;}
}


sub deletetag
{
  my ($deltag, $oldmarcrec) = @_;
  my $newmarcrec = '';
  my $leader = '';
  my $baseaddr = 0;
  my $mustdelete = 0;
  my $deletepoint = 0;
  my $taghole = 0;
  my $didx = 0;
  my $tagctr = -1;
  my $strptr = 24;
  my $tagidx = 0;
  my @tagid = ();
  my @taglen = ();
  my @offset = ();
  my @tagdata = ();
  my @deltaglength = ();

  $leader = substr($oldmarcrec, 0, 24);
  $baseaddr = substr($oldmarcrec, 12, 5) - 1;

  # go through tags and find deletion points
  while ($strptr < $baseaddr-1)
  {
    $tagctr++;
    $tagid[$tagctr] = substr($oldmarcrec, $strptr, 3);
    $taglen[$tagctr] = substr($oldmarcrec, $strptr+3, 4);
    $offset[$tagctr] = substr($oldmarcrec, $strptr+7, 5);
    $tagdata[$tagctr] = substr($oldmarcrec, $baseaddr+$offset[$tagctr], $taglen[$tagctr]);

    # check if current tag should be deleted
    if ($tagid[$tagctr] eq $deltag)
    {
      $deltaglength[$didx++] = $taglen[$tagctr];
      $mustdelete = 1;
    }
    $strptr += 12;
  }

  if ($mustdelete)
  {
    for ($didx=0; $didx<@deltaglength; $didx++)
    {
      # modify record length
      $leader = sprintf("%5.5d%s", substr($leader,0,5)-12-$deltaglength[$didx],
                                   substr($leader,5));
      # modify base address
      $leader = sprintf("%s%5.5d%s", substr($leader,0,12), substr($leader,12,5)-12,
                                     substr($leader,17));

      # now modify tag directory; no changes up to tag to be deleted
      $tagidx = 0;
      while (($tagidx <= $tagctr) and ($tagid[$tagidx] ne $deltag)) {$tagidx++;}

      # now at tag to be deleted
      $taghole = $tagidx;       # remember tag's number in array
      $tagidx++;                # step over tag to delete

      # keep rest of tags
      while ($tagidx <= $tagctr)
      {
        $offset[$tagidx] -= $deltaglength[$didx];   # data location has to shift over
        $tagidx++;
      }

      # shrink array to fill deleted tag's hole
      for ($tagidx=$taghole; $tagidx<$tagctr; $tagidx++)
      {
        $tagid[$tagidx] = $tagid[$tagidx+1];
        $taglen[$tagidx] = $taglen[$tagidx+1];
        $offset[$tagidx] = $offset[$tagidx+1];
        $tagdata[$tagidx] = $tagdata[$tagidx+1];
      }
      $tagctr--;   # one less tag
    }

    # write leader and tag directory
    $newmarcrec = $leader;
    for ($tagidx=0; $tagidx<=$tagctr; $tagidx++)
      {$newmarcrec .= sprintf ("%3.3d%4.4d%5.5d",
                               $tagid[$tagidx], $taglen[$tagidx], $offset[$tagidx]);
      }

    # write tag data
    for ($tagidx=0; $tagidx<=$tagctr; $tagidx++) {$newmarcrec .= $tagdata[$tagidx];}
    $newmarcrec .= sprintf ("$fdelim$recdelim");
    $delerecordctr++;
    return $newmarcrec;
  }
  else {return $oldmarcrec;}
}


sub edittag
{
  my ($parm, $oldmarcrec) = @_;
  my $action = '';
  my $edittag = '';
  my $editsubfield = '';
  my $olddata = '';
  my $newdata = '';
  my $newleader = '';
  my $char = '';
  my $thisdata = '';
  my $tagpoints = '';
  my $baseaddr = 0;
  my $newdatalength = 0;
  my $mustedit = 0;
  my $chgpoint = 0;
  my $tagctr = -1;
  my $strptr = 24;
  my $always = 0;
  my @chunk = ();
  my @piece = ();
  my $newmarcrec = '';
  my $addthis = '';
  my $whereadd = '';
  my $dropsubfwhen = '';
  my $leader = '';
  my $newtag = '';
  my $ldelta = 0;
  my $eidx = 1;
  my $mpt = 0;
  my $lastone = 0;
  my $recordchanged = 0;
  my @tagid = ();
  my @taglen = ();
  my @offset = ();
  my @tagdata = ();
  my @modpoints = ();
  my %delpoints = ();

  (@piece) = split /\|/, $parm;
  $action = $piece[0];
  if ($action eq $bracket245h)
    {$edittag = "245"; $editsubfield = "h";}
  elsif ($action eq $changeleaderchar)
  {
    $edittag = '0';
    $mustedit = 1;
  }
  else
    {$edittag = $piece[1];}
  if ($action eq $replacesubfieldalways)
  {
    $always = 1;
    $action = $replacesubfield;
  }

  $leader = substr($oldmarcrec, 0, 24);

  if ($edittag ne '0')   # will be doing typical field editing
  {
    $baseaddr = substr($oldmarcrec, 12, 5) - 1;

    # go through tags and find edit point
    while ($strptr < $baseaddr-1)
    {
      $tagctr++;
      $tagid[$tagctr] = substr($oldmarcrec, $strptr, 3);
      $taglen[$tagctr] = substr($oldmarcrec, $strptr+3, 4);
      $offset[$tagctr] = substr($oldmarcrec, $strptr+7, 5);
      $tagdata[$tagctr] = substr($oldmarcrec, $baseaddr+$offset[$tagctr], $taglen[$tagctr]);

      # want all tags, in case of multiple occurrences
      if ($tagid[$tagctr] eq $edittag)
      {
        $tagpoints .= sprintf("%s|", $tagctr);
        $mustedit = 1;
      }
      $strptr+= 12;
    }
    @modpoints = split /\|/, $tagpoints;  # might be more than 1 of this tag in this record
  }

  if ($mustedit)
  {
    if ($action eq $replacesubfield)
    {
      $editsubfield = $piece[2];
      if (!$always)   # old data to be replaced only if it exists
      {
        $olddata = $piece[3];
        $newdata = $piece[4];
      }
      # always replace
      else {$newdata = $piece[3];}   # don't need to keep olddata
      $newdatalength = length($newdata);
      $mustedit = 0;

      foreach $mpt (@modpoints)
      {
        next if ($mpt eq "");   # last piece will be empty

        # divide by subfields
        @chunk = split /\x1f/, $tagdata[$mpt];

        # we can safely ignore the 1st chunk (indicators)
        #   see initialization at beginning of routine
        # look for subfield to be replaced
        $ldelta = 0;
        for ($eidx=1; $eidx<@chunk; $eidx++)
        {
          if (substr($chunk[$eidx], 0, 1) eq $editsubfield)
          {
            $thisdata = substr($chunk[$eidx], 1);
            if ($always) {$olddata = $thisdata;}   # force replacement in this case

            # is this the data that should be replaced?
            if ($thisdata eq $olddata)
            {
              $mustedit = 1;
              $ldelta += $newdatalength - length($olddata);
              $chunk[$eidx] = $editsubfield . $newdata;
            }
          }
        }
        if ($mustedit)
        {
          # build the tag data with the new subfield contents
          $newtag = $chunk[0];   # indicators
          for ($eidx=1; $eidx<@chunk; $eidx++)
            {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx]);}
          ($newmarcrec, $leader) = createnewrec($leader, $newtag, $mpt, $ldelta, \@tagid, \@taglen, \@offset, \@tagdata);
        }
      }
      if ($mustedit)
      {
        $resbrecordctr++;
        return $newmarcrec;
      }
      else {return $oldmarcrec;}
    }

    elsif ($action eq $dropsubfield)
    {
      $editsubfield = $piece[2];
      $dropsubfwhen = $piece[3];

      foreach $mpt (@modpoints)
      {
        next if ($mpt eq "");   # last piece will be empty;
        %delpoints = ();
        $lastone = 0;

        # divide by subfields
        @chunk = split /\x1f/, $tagdata[$mpt];

        # we can safely ignore the 1st chunk (indicators)
        #   see initialization below
        # look for subfield to drop
        $ldelta = 0;
        $mustedit = 0;
        for ($eidx=1; $eidx<@chunk; $eidx++)
        {
          if (substr($chunk[$eidx], 0, 1) eq $editsubfield)
          {
            # store subfields to delete with their lengths
            $delpoints{$eidx} = 0 - (length($chunk[$eidx]) + 1);
            $mustedit = 1;
            if ($dropsubfwhen eq $first) {last;}   # no need to look further
            $lastone = $eidx;   # for when we want only the last one
          }
        }
        if ($mustedit)
        {
          $recordchanged = 1;
          $newtag = $chunk[0];   # indicators
          for ($eidx=1; $eidx<@chunk; $eidx++)
          {
            if ($dropsubfwhen ne $last)
            {
              if (!exists($delpoints{$eidx}))
                {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx]);}
              else 
                {$ldelta += $delpoints{$eidx};}
            }
            else
            {
              if ($eidx != $lastone)
                {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx]);}
              else
                {$ldelta += $delpoints{$eidx};}
            }
          }
          # update the record and
          # continue looking; there may be multiple occurrences of the field to look at
          ($newmarcrec, $leader) = createnewrec($leader, $newtag, $mpt, $ldelta, \@tagid, \@taglen, \@offset, \@tagdata);
        }
      }
      if ($recordchanged)
      {
        $dsbfrecordctr++;
        return $newmarcrec;
      }
      else {return $oldmarcrec;}
    }

    elsif ($action eq $subfieldaddtobeg)
    {
      $editsubfield = $piece[2];
      $addthis = $piece[3];

      foreach $mpt (@modpoints)
      {
        next if ($mpt eq "");   # last piece will be empty

        # divide by subfields
        @chunk = split /\x1f/, $tagdata[$mpt];

        # we can safely ignore the 1st chunk (indicators)
        #   see initialization below
        # look for subfield at which to insert
        $ldelta = 0;
        $mustedit = 0;
        for ($eidx=1; $eidx<@chunk; $eidx++)
        {
          if (substr($chunk[$eidx], 0, 1) eq $editsubfield)
          {
            $mustedit = 1;
            $ldelta += length($addthis);
            $chunk[$eidx] = $editsubfield . $addthis . substr($chunk[$eidx], 1);
          }
        }
        if ($mustedit)
        {
          # build the tag data with the new subfield contents
          $newtag = $chunk[0];   # indicators
          for ($eidx=1; $eidx<@chunk; $eidx++)
            {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx])}
          ($newmarcrec, $leader) = createnewrec($leader, $newtag, $mpt, $ldelta, \@tagid, \@taglen, \@offset, \@tagdata);
        }
      }
      if ($mustedit)
      {
        $sf2brecordctr++;
        return $newmarcrec;
      }
      else {return $oldmarcrec;}
    }

    elsif ($action eq $addsubfield)
    {
      $whereadd = uc($piece[2]);
      $editsubfield = $piece[3];
      $addthis = $piece[4];

      foreach $mpt (@modpoints)
      {
        next if ($mpt eq "");   # last piece will be empty

        # divide by subfields
        @chunk = split /\x1f/, $tagdata[$mpt];

        $ldelta = length($addthis) + 2;   # + delimiter and subfield-id
        if ($whereadd eq "B")   # add at beginning
        {
          # combine indicators and new subfield
          $newtag = $chunk[0] . $subfdelim . $editsubfield . $addthis;
          # add rest of tag
          for ($eidx=1; $eidx<@chunk; $eidx++)
            {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx])}
        }
        else                    # add at end
        {
          # start with indicators
          $newtag = $chunk[0];
          # add the current tag data, then the new subfield
          for ($eidx=1; $eidx<@chunk; $eidx++)
            {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx])}
          $newtag .= $subfdelim . $editsubfield . $addthis;
        }
        ($newmarcrec, $leader) = createnewrec($leader, $newtag, $mpt, $ldelta, \@tagid, \@taglen, \@offset, \@tagdata);
      }
      $adsfrecordctr++;
      return $newmarcrec;
    }

    elsif ($action eq $fieldaddtobeg)
    {
      $addthis = $piece[2];
      $ldelta = length($addthis);

      foreach $mpt (@modpoints)
      {
        next if ($mpt eq "");      # last piece will be empty
        $newtag = $addthis . $tagdata[$mpt];
        ($newmarcrec, $leader) = createnewrec($leader, $newtag, $mpt, $ldelta, \@tagid, \@taglen, \@offset, \@tagdata);
      }
      $fa2brecordctr++;
      return $newmarcrec;
    }

    elsif ($action eq $changeindicator)
    {
      my $replaceindalways = 0;
      my $oldind = "";

      my $indicator = $piece[2];   # which indicator to modify
      if ($piece[3] eq "*") {$replaceindalways = 1;}
      else {$oldind = $piece[3];}
      my $newind = $piece[4];

      foreach $mpt (@modpoints)
      {
        next if ($mpt eq "");   # last piece will be empty

        @chunk = split /\x1f/, $tagdata[$mpt];
        my $indicators = $chunk[0];   # get existing indicators here

        # do the replacement if necessary
        if (($replaceindalways) or (substr($indicators, $indicator, 1) eq $oldind))
        {
          substr($indicators, $indicator, 1) = $newind;
          $newtag = $indicators;      # indicators are now modified
        }
        else {$newtag = $chunk[0];}   # keep old indicators

        # and rebuild this record
        for ($eidx=1; $eidx<@chunk; $eidx++)
          {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx]);}
        $ldelta = 0;
        # create subroutine also updates the arrays, so effect below is
        #   to keep the desired most updated version of the record
        ($newmarcrec, $leader) = createnewrec($leader, $newtag, $mpt, $ldelta, \@tagid, \@taglen, \@offset, \@tagdata);
      }
      $chgirecordctr++;
      return $newmarcrec;
    } # if editaction

    elsif ($action eq $changeleaderchar)
    {
      my $pos = $piece[1];
      my $changeto = $piece[2];
      my $changeif = '';
      if (scalar(@piece) == 4)   # then have change-if character at pos-ition
        {$changeif = $piece[3];}
#print "LEADER:<<$leader>>---changeto:$changeto---changeif:$changeif\n";

      # change the leader as specified
      if ($changeif ne '')
      {
        if (substr($leader, $pos, 1) eq $changeif)
        {
          substr($leader, $pos, 1) = $changeto;
          $chglrecordctr++;
        }
      }
      else
      {
        substr($leader, $pos, 1) = $changeto;
        $chglrecordctr++;
      }
#print "NewLDR:<<$leader>>\n";
      $newmarcrec = $leader . substr($oldmarcrec, 24);
      return $newmarcrec;
    }

    elsif ($action eq $bracket245h)
    {
      my $subfseq = '';
      $mustedit = 0;

      # divide by subfields
      @chunk = split /\x1f/, $tagdata[$modpoints[0]];

      # we can safely ignore the 1st chunk (indicators)
      #   see initialization at beginning of routine
      # ...look for subfield h

      # get subfield sequence; it determines trailing |h character
      for ($eidx=1; $eidx<@chunk; $eidx++) {$subfseq .= substr($chunk[$eidx], 0, 1);}

      for ($eidx=1; $eidx<@chunk; $eidx++)
      {
        if (substr($chunk[$eidx], 0, 1) eq $editsubfield)   # now at |h
        {
          if ($chunk[$eidx] !~ /\[.+\]/)   # needs bracketing
          {
            $mustedit = 1;
            my $trailer = '';
            if    ($subfseq =~ /hc/) {$trailer = ' /';}
            elsif ($subfseq =~ /hb/) {$trailer = ' :';}
            if (($chunk[$eidx] =~ /$trailer$/) and ($trailer ne ''))
            {
              $chunk[$eidx] = substr($chunk[$eidx], 0, length($chunk[$eidx])-2);
              $ldelta = -2;
            }
            elsif (($subfseq =~ /hb/) and ($chunk[$eidx] =~ / =$/))
            {
              $chunk[$eidx] = substr($chunk[$eidx], 0, length($chunk[$eidx])-2);
              $ldelta = -2;
              $trailer = ' =';
            }
            if ($trailer eq '') {$ldelta -= 2;}   # compensate for next two lines in this case
            $chunk[$eidx] = $editsubfield . "[" . substr($chunk[$eidx], 1) . "]$trailer";
            $ldelta += 4;
          }
        }
      }
      if ($mustedit)
      {
        $newtag = $chunk[0];   # indicators
        for ($eidx=1; $eidx<@chunk; $eidx++)
          {$newtag .= sprintf("%s%s", $subfdelim, $chunk[$eidx]);}
        ($newmarcrec, $leader) = createnewrec($leader, $newtag, $modpoints[0], $ldelta, \@tagid, \@taglen, \@offset, \@tagdata);
        $b245recordctr++;
        return $newmarcrec
      }
      else {return $oldmarcrec;}
    }
  }
  else {return $oldmarcrec;}
}


sub findrecord()
{
  my ($marcrec) = @_;

  my $leader;
  my @tagid = ();
  my @taglen = ();
  my @tagdata = ();
  my $offset = 0;
  my $baseaddr = 0;

  my $strptr = 24;
  my $tagctr = -1;
  my $idx = 0;
  my $actualdata = '';

  my $match = 0;
  my $bad = 0;
  my $good = 1;
  my $goodtogo;

  # by passing in good or bad here, have cleaner code below
  local *exitloop = sub{my ($status) = @_; $goodtogo = $status; last TAGCHECK;};

  $leader = substr($marcrec, 0, 24);

  # get record's data into arrays
  $baseaddr = substr($marcrec, 12, 5) - 1;
  while ($strptr < ($baseaddr-1))
  {
    $tagctr++;
    $tagid[$tagctr]  = substr($marcrec, $strptr,   3);
    $taglen[$tagctr] = substr($marcrec, $strptr+3, 4);
    $offset          = substr($marcrec, $strptr+7, 5);
    $tagdata[$tagctr] = substr($marcrec, $baseaddr+$offset, $taglen[$tagctr]);
    $strptr += 12;
  }

  $idx = 0;
TAGCHECK: while ($idx < @tagid)
  {
    if ($findtag eq $tagid[$idx])   # tag we're looking for
    {
      if ($numfindelements == 1) {exitloop($good);}   # only cared about the tag
      if ($tagid[$idx] ge '010')    # tags with indicators
      {
        ### weed record out via indicator conditions, if applicable
        my $ind1 = substr($tagdata[$idx], 1, 1);
        my $ind2 = substr($tagdata[$idx], 2, 1);

        if (($findl1yes ne '') and ($findl1yes ne $ind1)) {$idx++; next TAGCHECK;}
        if (($findl2yes ne '') and ($findl2yes ne $ind2)) {$idx++; next TAGCHECK;}

        if (($findl1no ne '') and ($findl1no eq $ind1)) {$idx++; next TAGCHECK;}
        if (($findl2no ne '') and ($findl2no eq $ind2)) {$idx++; next TAGCHECK;}

        # if made it this far and don't care about subfields, we're done
        if (!$findsubfield) {exitloop($good);}
        # else need to check subfields
        else
        {
          my $matchctr = 0;
          my $allmatchctr = 0;
          my $lastmatch = 0;

          my @chunk = split /\x1f/, $tagdata[$idx];   # put subfields in array
          my $cidx;   # ignore 1st chunk; don't care about indicators anymore
          for ($cidx=1; $cidx<@chunk; $cidx++)
          {
            $lastmatch = 0;
            if (substr($chunk[$cidx], 0, 1) eq $findsubfield)  # is subfield we want?
            {
              $matchctr++;
              if (!$findsubdata)
              {
                if ($matchctr == 1)
                {
                  if ($findlooksubfield eq $first) {exitloop($good);}
                }
                $allmatchctr++;
                $lastmatch = 1;
              }
              else   # must match subfield data by spec
              {
                $lastmatch = 0;
                $actualdata = substr($chunk[$cidx], 1);
                if ($findcase ne $casematch) {$actualdata = lc($actualdata);}

                $match = 0;
                if (!$findregex)
                {
                  if ($actualdata eq $findsubdata) {$match = 1;}
                }
                else
                {
                  if ($regexnormal)
                  {
                    if ($actualdata =~ /$findsubdata/) {$match = 1;}
                  }
                  else
                  {
                    if ($actualdata !~ /$findsubdata/) {$match = 1;}
                  }
                }
                if (!$match) {$matchctr--;}
                if ($match)
                {
                  if ($matchctr == 1)
                  {
                    if ($findlooksubfield eq $first) {exitloop($good);}
                  }
                  if ($findlooksubfield eq $any) {exitloop($good);}
                  $lastmatch = 1;
                  $allmatchctr++;
                }
              }
            }
          }
          if (($findlooksubfield eq $last)  and $lastmatch)
            {exitloop($good);}
          elsif (($findlooksubfield eq $all) and ($allmatchctr == $matchctr) and ($allmatchctr != 0))
            {exitloop($good);}
          elsif (($findlooksubfield eq $any) and ($matchctr > 0))
            {exitloop($good);}
        } # done subfield checking
      }
      
      else   # tags without indicators; case-sensitive normal/regex data check only
      {
        $actualdata = lc(substr($tagdata[$idx],1));   # drop leftover leading binary char
        if (!$findregex)
        {
          if ($actualdata eq $findsubdata) {exitloop($good);}
        }
        else
        {
          if ($regexnormal)
          {
            if ($actualdata =~ $findsubdata) {exitloop($good);}
          }
          else
          {
            if ($actualdata !~ $findsubdata) {exitloop($good);}
          }
        }
        exitloop($bad);   # no match, stop checking record
      }
    }
    $idx++;
  }
  if ($readonly and $goodtogo)
  {
    printf fout ("LDR:%s\n", $leader);
    for ($tagctr=0; $tagctr<@tagid; $tagctr++)
    {
      $tagdata[$tagctr] =~ s/\x1f[a-z0-9]/ \|$& /g;     # use " |x " for subfield ind,
      $tagdata[$tagctr] =~ s/\x1f//g;                   #  remove original subfield ind,
      $tagdata[$tagctr] =~ s/\x1e//g;                   #  remove field ind,
      if (substr($tagdata[$tagctr], 2, 2) eq " |")      #  & remove the "1st" space in the line
        {$tagdata[$tagctr] = substr($tagdata[$tagctr], 0, 2) . substr($tagdata[$tagctr], 3);}
      printf fout ("%3s:%s\n", $tagid[$tagctr], $tagdata[$tagctr]);
    }
    print fout "\n";
  }
  return $goodtogo;
}


sub getini()
{
  my $stanza = '';
  my $stanzaend = '';
  my $addidx = 0;
  my $delidx = 0;
  my $editidx = 0;

  my $fopen = sprintf("Cannot open file %s for input\n", $inifile);
  open(inifile, $inifile) or die $fopen;
  my @inilines = <inifile>;
  close(inifile);
  chomp @inilines;

  foreach my $iline (@inilines)
  {
    if (length($iline) != 0)               # ignore blank lines
    {
      if (substr($iline, 0, 1) ne '#')     # ignore comment lines
      {
        if (substr($iline, 0, 1) eq '[')   # start of a stanza
        {
          $stanzaend = index($iline, ']');
          $stanza = substr($iline, 1, $stanzaend-1);
        }
        else                               # line of a stanza
        {
          if ($stanza eq 'ADD')
          {
            my @ipart = split /\|/, $iline;
            $addtag[$addidx] = $ipart[0];
            if ($ipart[0] gt '009')
            {
              $addtagdata[$addidx] = sprintf("%s%1.1s%1.1s%s%1.1s%s",
                                             $fdelim, $ipart[1], $ipart[2], $subfdelim, $ipart[4], $ipart[5]);
              if ($ipart[3] > 1)
              {
                my $idx = 6;
                $ipart[3]--;
                while ($ipart[3] > 0)
                {
                  $addtagdata[$addidx] .= sprintf("%s%1.1s%s", $subfdelim, $ipart[$idx], $ipart[$idx+1]);
                  $idx += 2;
                  $ipart[3]--;
                }
              }
            }
            else  # adding fixed field
            {
              $addtagdata[$addidx] = sprintf("%s%s", $fdelim, $ipart[5]);
            }
            $addidx++;
          }
          elsif ($stanza eq 'REMOVE') {$deltag[$delidx++] = $iline;}
          elsif ($stanza eq 'EDIT')
          {
            $edittask[$editidx++] = $iline;
            my @check = split /\|/, $iline;
            if (($check[0] eq $fieldaddtobeg) and ($check[1] ge "010"))
            {
              printf("\nCannot add to beginning of fields 010 or greater.\n");
              printf("Check marcedit.ini file.\n");
              exit(0);
            }
          }
          elsif ($stanza eq 'FIND')
          {
            if (uc($iline) eq "NOT") {$notfind = 1;}
            else {getncheckfindstuff($iline);}
          }
        }
      }
    }
  }
  foreach my $delitem (@deltag)
  {
    if (lc($delitem) eq "record")
    {
      $deleterecord = 1;
      last;
    }
  }
  if ($deleterecord and !$findspec)
  {
    printf("\nTo enable deleting an entire record, you must use the FIND stanza.\n");
    printf("Check marcedit.ini file.\n");
    exit(0);
  }
}


sub getncheckfindstuff()
{
  ($findspec) = @_;

  my $count = 0;

  # in case more than one find line, last one will be cleanly used
  $findtag = $findl1yes = $findl2yes = $findl1no = $findl2no = '';
  $findlooksubfield = $findsubfield = $findcase = $findsubdata = '';
  $findregex = 0;
  $regexnormal = 1;

  # get the find spec elements
  ($findtag, $findl1yes, $findl2yes, $findl1no, $findl2no, $findlooksubfield,
   $findsubfield, $findcase, $findsubdata) = split /\|/, $findspec;

  # case consistency and such for any constants
  $findtag = lc($findtag);
  $findlooksubfield = lc($findlooksubfield);
  if ($findlooksubfield eq "") {$findlooksubfield = $any;}
  $findcase = lc($findcase);
  if ($findcase ne $casematch) {$findsubdata = lc($findsubdata);}

  # check for dry-run mode
  if (lc(substr($findtag, 3)) eq "readonly")
  {
    $readonly = 1;
    printf ("\n     Marcedit is running in READONLY mode.\n");
    printf ("     Readonly results will be in your output file.\n");
    printf ("     Results are formatted for readability,\n");
    printf ("      including spaces around subfield identifiers.\n");
    printf ("     Use \"less\" (or \"more\") to view your output file,\n");
    printf ("      to see which records would be processed.\n");
    $findtag = substr($findtag, 0, 3);
  }

  # get number of elements; useful in speeding up the find process
  my @testarray = split /\|/, $findspec;
  $numfindelements = scalar(@testarray);

  # check for "%" or "~" wildcards
  # if any found, and validly specified, convert to regex for internal use
  # "~" is converted to "%" and will be the opposite, via a flag
  $count = ($findsubdata =~ s/\~/\~/g);
  if ($count > 0)
  {
    $regexnormal = 0;
    $findsubdata =~ s/\~/\%/g;   # proceed normally, knowing we want the opposite
  }
  $count = ($findsubdata =~ s/\%/\%/g);
  if ($findsubdata =~ /.+\%.+/) {$count = 99;}  # bad spec

  # will want subfield data at beg or end of field
  if ($count == 1)
  {
    if ($findsubdata =~ /\%$/)      # want data at end
    {
      $findsubdata = "^" . substr($findsubdata, 0, length($findsubdata)-1);
    }
    elsif ($findsubdata =~ /^\%/)   # want data at beginning
    {
      $findsubdata = substr($findsubdata, 1) . "\$";
    }
  }
  elsif ($count == 2)
  # will want subfield data in middle of field
  {
    $findsubdata = ".*" . substr($findsubdata, 1, length($findsubdata)-2) . ".*";
  }
  elsif ($count != 0)
  {
    print "\n\nBad wildcard spec for subfield data in the FIND stanza\n";
    exit(0);
  }
  if ($count) {$findregex = 1;}

  if (($findl1yes and $findl1no) or ($findl2yes and $findl2no))
  {
    print "\n\nConflicting indicator data in the FIND stanza\n";
    exit(0);
  }
}


sub createnewrec()
{
  # the last 4 arguments are array references
  my ($leader, $newtag, $mpt, $ldelta, $tagid, $taglen, $offset, $tagdata) = @_;

  my $newmarcrec = '';

  # put new info into arrays of tag stuff
  $tagdata->[$mpt] = $newtag;
  $taglen->[$mpt] += $ldelta;

  # record changed info in array of offsets
  my $eidx = $mpt + 1;
  while ($eidx < @$offset) {$offset->[$eidx++] += $ldelta;}

  # modify record length
  $leader = sprintf("%5.5d%s", substr($leader,0,5)+$ldelta, substr($leader,5));
  # start building the new record
  $newmarcrec = $leader;

  # store directory
  for ($eidx=0; $eidx<@$tagid; $eidx++)
    {$newmarcrec .= sprintf("%3.3s%4.4d%5.5d",
                            $tagid->[$eidx], $taglen->[$eidx], $offset->[$eidx]);
    }

  # store tag data and finish up
  for ($eidx=0; $eidx<@$tagdata; $eidx++) {$newmarcrec .= $tagdata->[$eidx];}
  $newmarcrec .= sprintf ("%s%s", $fdelim, $recdelim);
  return ($newmarcrec, $leader);
}


sub usage()
{
  print "\nUsage: marcedit inputfile outputfile [xxxmarcedit.ini]\n\n";
  print "   Add, remove, and/or edit fields in MARC records.\n";
  print "   Can instead split a file into unicode and non-unicode files.\n\n";
  print "   Process <inputfile> to create <outputfile>.\n";
  print "   These two parameters are required.\n";
  print "   (When using the edit function \"unicodesplit\", <outputfile> should\n";
  print "   be a dummy value and will be otherwise ignored in that case.)\n\n";
  print "   If no third parameter is given, marcedit uses the\n";
  print "   marcedit.ini (that exact name) file in the local directory\n";
  print "   so that it knows what to do.\n\n";
  print "   If the third parameter is supplied, it can be any name,\n";
  print "   but the file must be in the format of a marcedit.ini file.\n\n";
  print "   Allowing a marcedit.ini filename on the command line conveniently\n";
  print "   lets you run marcedit for multiple tasks at one time.\n";
  exit(0);
}
